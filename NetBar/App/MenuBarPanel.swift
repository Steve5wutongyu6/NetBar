//
//  MenuBarPanel.swift
//  NetBar
//
//  A status item plus the panel it drops down. The panel is a borderless,
//  non-activating window so opening it never steals focus from the current app,
//  exactly like a menu.
//

import AppKit
import SwiftUI

/// Borderless panel that closes when it loses key status or the user clicks away.
final class MenuPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        onDismiss?()
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let store: WiFiStore
    private var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var dismissMonitor: Any?
    private var refreshTimer: Timer?
    private var permissionTimer: Timer?
    private var isWatchingContent = false
    private var authorizationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(store: WiFiStore) {
        self.store = store
        super.init()
    }

    deinit {
        if let authorizationObserver {
            NotificationCenter.default.removeObserver(authorizationObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        // `deinit` is not on the main actor, so the monitor is dropped directly.
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
        }
        NBWiFiMonitor.shared().stop()
    }

    /// A radio event: re-read the state only, which needs no scan, then redraw.
    private func radioDidChange() async {
        await store.refresh(scan: false)
        updateStatusItem()
        if let panel, panel.isVisible {
            resize(panel)
            position(panel, under: anchorRect(for: panel))
        }
    }

    /// A change big enough to rescan for, e.g. waking from sleep.
    private func refreshEverything() async {
        await store.refresh(scan: true)
        updateStatusItem()
        if let panel, panel.isVisible {
            resize(panel)
            position(panel, under: anchorRect(for: panel))
        }
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp])
        statusItem = item
        updateStatusItem()

        // Launch at login is on by default: the first run turns it on and later
        // runs leave whatever the user chose alone.
        LoginItem.registerOnFirstLaunch()

        // A plain click opens the system menu, and that needs the Accessibility
        // grant. The ask happens once per version: repeating it on every launch is
        // what made a missing grant feel like nagging, and after an update the new
        // signature would prompt again even though the user already answered.
        AccessibilityPermission.askOnceForThisVersion()
        Task { await store.refresh(scan: true) }

        // Granting access from System Settings while NetBar runs must reach the
        // menu without reopening it.
        // The radio reports its own changes, so the status item stays current
        // whether or not the menu is open.
        NBWiFiMonitor.shared().startObserving { [weak self] in
            Task { @MainActor in
                await self?.radioDidChange()
            }
        }
        // Waking up can land on a different network entirely.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshEverything()
            }
        }

        authorizationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NBLocationAuthorizationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.store.authorizationDidChange()
                self.updateStatusItem()
            }
        }
    }

    /// Redraws the status item glyph from the current menu state.
    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        if let title = store.statusTitle {
            button.image = WiFiIcon.statusGlyph(isHotspot: false, powerOn: false, strength: 0)
            button.toolTip = title
            button.setAccessibilityLabel(title)
        } else {
            button.image = WiFiIcon.statusGlyph(
                isHotspot: store.connectedIsHotspot,
                powerOn: true,
                strength: store.strength
            )
            button.toolTip = store.connectedName ?? "Wi-Fi"
            button.setAccessibilityLabel(store.connectedName ?? "Wi-Fi")
        }
    }

    /// The status item's action. A plain click opens the menu macOS owns, which is
    /// what people expect to find there; Option-click opens the replica NetBar
    /// draws, the only place the hotspot detail it adds exists.
    @objc private func togglePanel() {
        if NSEvent.modifierFlags.contains(.option) {
            if panel?.isVisible == true {
                panel?.dismiss()
            } else {
                showPanel()
            }
            return
        }
        openSystemWiFiMenu()
    }

    /// Hands the click to the system. The bridge blocks for as long as a menu takes
    /// to open, so it runs on a worker thread and the answer is handed back here.
    /// Nothing else about the controller crosses over, which keeps the concurrency
    /// checks happy on both the newest and the oldest toolchains this ships to.
    private func openSystemWiFiMenu() {
        panel?.dismiss()
        Task {
            let outcome = await Self.openSystemWiFiMenuOffMainThread()
            systemWiFiMenuDidFinish(outcome)
        }
    }

    /// The bridge, run away from the main actor.
    private nonisolated static func openSystemWiFiMenuOffMainThread() async -> NBSystemWiFiMenuOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: NBSystemWiFiMenu.openSystemWiFiMenu())
            }
        }
    }

    /// What the click managed to do, back on the main actor. Without the grant
    /// there is nothing to open, so the panel explains that rather than letting the
    /// click go nowhere.
    private func systemWiFiMenuDidFinish(_ outcome: NBSystemWiFiMenuOutcome) {
        switch outcome {
            case .opened:
                break
            case .notPermitted:
                // The prompt is the ask; the pane is where the answer lives once
                // the prompt has been dismissed for good.
                _ = NBSystemWiFiMenu.requestPermission()
                NBSystemWiFiMenu.openAccessibilitySettings()
                showPanel()
            case .noMenuBarItem, .noWiFiControl:
                showPanel()
            @unknown default:
                break
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // Both rows in the panel can change while it is closed — the grant, and the
        // login item if it was edited in System Settings — so the root view is
        // rebuilt on every open rather than once.
        hostingView?.rootView = makePanelRoot()
        guard let button = statusItem?.button, let window = button.window else { return }
        button.highlight(true)
        panel.onDismiss = { [weak self] in
            self?.statusItem?.button?.highlight(false)
            self?.stopRefreshTimer()
            self?.stopPermissionWatch()
            self?.removeDismissMonitor()
        }

        Task { @MainActor in
            await store.refresh(scan: true)
            updateStatusItem()
            resize(panel)
            position(panel, under: window.convertToScreen(button.convert(button.bounds, to: nil)))
            panel.makeKeyAndOrderFront(nil)
            startRefreshTimerIfNeeded()
            startPermissionWatchIfNeeded()
            watchContentChanges()
        }
    }

    /// The panel's content, rebuilt whenever something it reports may have changed.
    private func makePanelRoot() -> AnyView {
        AnyView(
            MenuPanelView(
                store: store,
                systemMenuPermitted: AccessibilityPermission.isGranted
            )
        )
    }

    /// Watches for the grant arriving while the panel is open, so the row goes away
    /// as soon as the box is ticked in System Settings.
    private func startPermissionWatchIfNeeded() {
        stopPermissionWatch()
        guard !AccessibilityPermission.isGranted else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, AccessibilityPermission.isGranted else { return }
                self.stopPermissionWatch()
                self.hostingView?.rootView = self.makePanelRoot()
            }
        }
    }

    private func stopPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func makePanel() -> MenuPanel {
        let panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let host = NSHostingView(rootView: makePanelRoot())
        host.frame = NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 200)
        panel.contentView = host
        hostingView = host

        // A borderless panel has no title bar to drag, and a click anywhere else
        // dismisses it the way a menu does. The monitor lives only while the panel
        // does: a global monitor that outlives its window keeps the app awake and
        // keeps swallowing every click on the system.
        removeDismissMonitor()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.panel?.dismiss()
        }
        return panel
    }

    private func removeDismissMonitor() {
        guard let monitor = dismissMonitor else { return }
        NSEvent.removeMonitor(monitor)
        dismissMonitor = nil
    }

    /// The panel is exactly as tall as its content.
    private func resize(_ panel: MenuPanel) {
        guard let host = hostingView else { return }
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        var frame = panel.frame
        frame.size = NSSize(width: MenuMetrics.width, height: height)
        panel.setFrame(frame, display: true)
    }

    private func position(_ panel: MenuPanel, under buttonFrame: NSRect) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(buttonFrame.origin) } ?? NSScreen.main
        var origin = NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height - 5
        )
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - size.width - 6)
            origin.y = max(origin.y, visible.minY + 6)
        }
        panel.setFrameOrigin(origin)
    }

    /// Keeps the list honest while it is open, without scanning the radio again.
    /// Re-fits the panel whenever the menu changes: unfolding "Other Networks"
    /// adds rows, and a window that keeps its old height would hide them.
    private func watchContentChanges() {
        guard !isWatchingContent else { return }
        isWatchingContent = true
        withObservationTracking {
            _ = store.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isWatchingContent = false
                guard let panel = self.panel, panel.isVisible else { return }
                self.resize(panel)
                self.position(panel, under: self.anchorRect(for: panel))
                self.watchContentChanges()
            }
        }
    }

    /// The status button's frame in screen coordinates.
    private func anchorRect(for panel: MenuPanel) -> NSRect {
        guard let button = statusItem?.button, let window = button.window else {
            return NSRect(x: panel.frame.midX, y: panel.frame.maxY, width: 1, height: 1)
        }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func startRefreshTimerIfNeeded() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.store.refresh(scan: false)
                self.updateStatusItem()
                if let panel = self.panel, panel.isVisible {
                    self.resize(panel)
                }
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
