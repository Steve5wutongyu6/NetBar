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

    init(store: WiFiStore) {
        self.store = store
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp])
        statusItem = item
        updateStatusItem()
        Task { await store.refresh(scan: true) }
    }

    /// Redraws the status item glyph from the current menu state.
    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        if let title = store.statusTitle {
            button.image = WiFiIcon.statusSymbol(isHotspot: false, powerOn: false, strength: 0)
            button.toolTip = title
            button.setAccessibilityLabel(title)
        } else {
            button.image = WiFiIcon.statusSymbol(
                isHotspot: store.connectedIsHotspot,
                powerOn: true,
                strength: store.strength
            )
            button.toolTip = store.connectedName ?? "Wi-Fi"
            button.setAccessibilityLabel(store.connectedName ?? "Wi-Fi")
        }
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.dismiss()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard let button = statusItem?.button, let window = button.window else { return }
        button.highlight(true)
        panel.onDismiss = { [weak self] in
            self?.statusItem?.button?.highlight(false)
            self?.stopRefreshTimer()
        }

        Task { @MainActor in
            await store.refresh(scan: true)
            updateStatusItem()
            resize(panel)
            position(panel, under: window.convertToScreen(button.convert(button.bounds, to: nil)))
            panel.makeKeyAndOrderFront(nil)
            startRefreshTimerIfNeeded()
        }
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

        let host = NSHostingView(rootView: AnyView(MenuPanelView(store: store)))
        host.frame = NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 200)
        panel.contentView = host
        hostingView = host

        // A borderless panel has no title bar to drag, and a click anywhere else
        // dismisses it the way a menu does.
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.panel?.dismiss()
        }
        return panel
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
