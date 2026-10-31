//
//  MenuRowViews.swift
//  NetBar
//
//  The panel's rows. The layout follows the Wi-Fi menu: one 24 pt line per
//  network, the joined network checked, and only as much trailing detail as the
//  row needs. Rows are inert — joining a network stays with the system — so the
//  panel never promises an action it cannot finish.
//

import AppKit
import SwiftUI

/// Metrics shared by every row, so the panel lines up like a menu.
enum MenuMetrics {
    static let width: CGFloat = 288
    static let rowHeight: CGFloat = 24
    static let sectionHeight: CGFloat = 22
    static let innerPadding: CGFloat = 5
    static let textPadding: CGFloat = 9
    static let cornerRadius: CGFloat = 5
}

/// The menu itself: header, sections, footer.
struct MenuPanelView: View {
    let store: WiFiStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(isOn: Binding(get: { store.powerOn }, set: { value in
                Task { await store.setPower(value) }
            }))
            if let title = store.statusTitle {
                StatusRow(title: title)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                row
            }
            FooterSeparator()
            if store.namesUnavailable {
                // Only shown when macOS actually withheld the names; elsewhere
                // the panel stays silent about privacy.
                SettingsLinkRow(title: "Allow NetBar to See Network Names…") {
                    Task {
                        // Asking first is what puts NetBar in the Location
                        // Services list the pane opens.
                        await store.requestNameAccess()
                        NBWiFiBridge.openPrivacySettings()
                    }
                }
            } else {
                SettingsLinkRow(title: "Wi-Fi Settings…") {
                    NBWiFiBridge.openWiFiSettings()
                }
            }
        }
        .padding(.vertical, MenuMetrics.innerPadding)
        .frame(width: MenuMetrics.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    /// Engine rows, minus the footer the panel draws itself.
    private var rows: [AnyView] {
        var rendered: [AnyView] = []
        let breaks = MenuRowPlanner.separatorOffsets(in: store.output.items)
        for (offset, item) in store.output.items.enumerated() {
            guard let row = rowView(for: item) else { continue }
            if breaks.contains(offset) {
                rendered.append(AnyView(SectionSeparator()))
            }
            rendered.append(row)
        }
        return rendered
    }

    private func rowView(for item: NBEngineItem) -> AnyView? {
        switch item.role {
            case .header:
                return AnyView(SectionHeaderRow(title: item.title ?? ""))
            case .network:
                return AnyView(NetworkRow(item: item))
            case .otherNetworks:
                return AnyView(OtherNetworksRow(
                    hiddenCount: Int(store.output.hiddenOtherCount),
                    isExpanded: store.revealsOther
                ) {
                    store.revealsOther.toggle()
                })
            case .settings:
                return nil
            @unknown default:
                return nil
        }
    }
}

/// Decides where the menu puts a hairline. The Wi-Fi menu divides Personal
/// Hotspots, saved networks and strangers, so a separator sits between sections
/// and never inside one.
enum MenuRowPlanner {
    /// Offsets of the rows that need a separator drawn above them.
    static func separatorOffsets(in items: [NBEngineItem]) -> Set<Int> {
        var offsets: Set<Int> = []
        var previous: NBItemSection?
        for (offset, item) in items.enumerated() {
            defer { previous = item.section }
            guard let previous, previous != item.section else { continue }
            // The footer draws its own rule.
            guard item.role != .settings else { continue }
            offsets.insert(offset)
        }
        return offsets
    }
}

/// Hairline between two sections.
private struct SectionSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, MenuMetrics.innerPadding)
            .padding(.vertical, 3)
    }
}

/// "Wi-Fi" and the power switch.
private struct HeaderRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Wi-Fi")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Toggle("Wi-Fi", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, MenuMetrics.textPadding + MenuMetrics.innerPadding)
        .frame(height: 34)
    }
}

/// "Wi-Fi Off" and friends; one quiet line when there is nothing to list.
private struct StatusRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MenuMetrics.textPadding + MenuMetrics.innerPadding)
            .frame(height: MenuMetrics.rowHeight, alignment: .leading)
    }
}

private struct SectionHeaderRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MenuMetrics.textPadding + MenuMetrics.innerPadding)
            .frame(height: MenuMetrics.sectionHeight, alignment: .bottomLeading)
    }
}

/// One network: name, then whatever trailing detail the engine asked for.
private struct NetworkRow: View {
    let item: NBEngineItem

    var body: some View {
        HStack(spacing: 6) {
            CheckmarkSlot(isJoined: item.isJoined)
            Text(displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.isJoined ? .primary : .primary)
            Spacer(minLength: 6)
            TrailingDetail(item: item)
        }
        .padding(.horizontal, MenuMetrics.textPadding)
        .frame(height: MenuMetrics.rowHeight)
        .padding(.horizontal, MenuMetrics.innerPadding)
    }

    private var displayName: String {
        // A joined network whose name the OS withheld has no name to print.
        if item.redacted { return item.title ?? "Not Nearby" }
        return item.ssid ?? item.title ?? ""
    }
}

/// The checkmark column; empty rows keep the same width so names stay aligned.
private struct CheckmarkSlot: View {
    let isJoined: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .opacity(isJoined ? 1 : 0)
            .frame(width: 12, alignment: .leading)
            .accessibilityHidden(!isJoined)
    }
}

/// Signal bars, and for an Apple hotspot the Cellular generation and battery.
private struct TrailingDetail: View {
    let item: NBEngineItem

    var body: some View {
        HStack(spacing: 5) {
            if item.detailKind == .lock {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if item.detailKind == .appleHotspot {
                if item.cell != .none {
                    Text(item.cell == .fiveG ? "5G" : "4G")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if item.battery > 0 {
                    Text("\(item.battery)%")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Image(nsImage: signalGlyph)
                .renderingMode(.template)
                .foregroundStyle(.primary)
                // Symbols carry their own padding; keep the natural drawing and
                // only reserve a minimum column so rows stay aligned.
                .frame(minWidth: WiFiIcon.boxSize, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// A Personal Hotspot is drawn with the Cellular glyph so it never reads as
    /// an ordinary Wi-Fi network.
    private var signalGlyph: NSImage {
        if item.detailKind == .appleHotspot {
            return WiFiIcon.cellular(strength: Int(item.strength))
        }
        return WiFiIcon.wifi(strength: Int(item.strength))
    }
}

/// The folding row for strangers; the chevron points at what a click does.
private struct OtherNetworksRow: View {
    let hiddenCount: Int
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text("Other Networks")
                    .font(.system(size: 13))
                Spacer(minLength: 6)
                if hiddenCount > 0 || isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, MenuMetrics.textPadding)
            .frame(height: MenuMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MenuMetrics.innerPadding)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: MenuMetrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel(isExpanded ? "Other Networks, expanded" : "Other Networks")
    }
}

/// The settings row at the foot of the menu.
private struct SettingsLinkRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MenuMetrics.textPadding)
                .frame(height: MenuMetrics.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MenuMetrics.innerPadding)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: MenuMetrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .onHover { isHovering = $0 }
    }
}

/// The hairline above the settings row.
private struct FooterSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, MenuMetrics.innerPadding)
            .padding(.vertical, 4)
    }
}
