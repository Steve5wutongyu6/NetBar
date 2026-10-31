//
//  WiFiIcon.swift
//  NetBar
//
//  Menu bar glyphs. Both are the system's own symbols, drawn at a variable fill
//  level so one glyph covers every signal strength: `wifi` for a network and
//  `cellularbars` for a Personal Hotspot, which is how the system separates the
//  two connection types.
//

import AppKit

enum WiFiIcon {
    /// Drawing box, matching an SF Symbol's text box.
    static let boxSize: CGFloat = 15

    /// Signal levels the menu distinguishes.
    static let levels = 4

    /// The system symbols the menu draws.
    private enum SymbolName {
        static let wifi = "wifi"
        static let cellular = "cellularbars"
        static let wifiOff = "wifi.slash"
        static let wifiWeak = "wifi.exclamationmark"
    }

    /// `wifi` itself has three fill levels: one per arc above the dot.
    private static let wifiLevels = 3

    private static let cache = NSCache<NSString, NSImage>()

    /// Wi-Fi glyph for a 0...4 strength. Zero is not "very weak bars": it is a
    /// signal too poor to score, which the system draws as its own symbol.
    static func wifi(strength: Int) -> NSImage {
        let level = clamp(strength)
        return cached("wifi-\(level)") {
            guard level > 0 else {
                return symbol(named: SymbolName.wifiWeak)
            }
            // Four strengths map onto the symbol's three arcs, as the system does.
            let step = min(max(level, 1), wifiLevels)
            return symbol(named: SymbolName.wifi, variableValue: Double(step) / Double(wifiLevels))
        }
    }

    /// Cellular glyph for a 0...4 strength.
    static func cellular(strength: Int) -> NSImage {
        let level = clamp(strength)
        return cached("cellular-\(level)") {
            let step = max(level, 1)
            return symbol(named: SymbolName.cellular, variableValue: Double(step) / Double(levels))
        }
    }

    /// The status item glyph. A joined Apple hotspot shows Cellular bars, as the
    /// system's Cellular indicator does, so the two connection types never look
    /// alike.
    static func statusGlyph(isHotspot: Bool, powerOn: Bool, strength: Int) -> NSImage? {
        guard powerOn else {
            return symbol(named: SymbolName.wifiOff)
        }
        return isHotspot ? cellular(strength: strength) : wifi(strength: strength)
    }

    /// A template image of a system symbol, optionally at a variable fill level.
    static func symbol(named name: String, variableValue: Double? = nil) -> NSImage {
        let image: NSImage?
        if let variableValue {
            image = NSImage(systemSymbolName: name,
                            variableValue: min(max(variableValue, 0), 1),
                            accessibilityDescription: nil)
        } else {
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: boxSize, weight: .regular)
        guard let configured = image?.withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: boxSize, height: boxSize))
        }
        configured.isTemplate = true
        return configured
    }

    private static func clamp(_ strength: Int) -> Int {
        min(max(strength, 0), levels)
    }

    private static func cached(_ key: String, make: () -> NSImage) -> NSImage {
        let cacheKey = key as NSString
        if let existing = cache.object(forKey: cacheKey) {
            return existing
        }
        let image = make()
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
