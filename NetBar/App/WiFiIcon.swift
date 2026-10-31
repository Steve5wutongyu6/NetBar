//
//  WiFiIcon.swift
//  NetBar
//
//  macOS ships no four-bar Wi-Fi symbol — SF Symbols' `wifi` is a fixed
//  three-arc glyph — so NetBar draws the bars the Wi-Fi menu uses and hands the
//  result to AppKit as a template image. Every other glyph in the menu comes
//  from SF Symbols.
//

import AppKit
import CoreGraphics

enum WiFiIcon {
    /// Point size of the drawing box, matching SF Symbols' text style box.
    static let boxSize: CGFloat = 15

    private static let barCount = 4
    private static let arcWidth: CGFloat = 1.55
    private static let innerRadius: CGFloat = 2.6
    private static let radiusStep: CGFloat = 3.05
    private static let centerY: CGFloat = 1.4
    /// Half of the horizontal field of view, wrapped around vertical.
    private static let arcSpread: CGFloat = 62
    private static let emptyAlpha: CGFloat = 0.32

    private static let cache = NSCache<NSString, NSImage>()

    /// Bars for a 0...4 strength. Values outside the range are clamped.
    static func bars(strength: Int) -> NSImage {
        let level = min(max(strength, 0), barCount)
        let key = "bars-\(level)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image = render(level: level)
        cache.setObject(image, forKey: key)
        return image
    }

    /// The status-bar glyph: a joined Apple hotspot is drawn as a phone, as the
    /// system Cellular menu does, instead of the usual link badge.
    static func statusSymbol(isHotspot: Bool, powerOn: Bool, strength: Int) -> NSImage? {
        if !powerOn {
            return symbol(named: "wifi.slash")
        }
        if isHotspot {
            for name in ["iphone.gen3", "iphone.gen2", "iphone"] where symbol(named: name) != nil {
                return symbol(named: name)
            }
        }
        return bars(strength: strength)
    }

    /// An SF Symbol configured as a menu bar template image.
    static func symbol(named name: String, pointSize: CGFloat = 15) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private static func render(level: Int) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int(boxSize * scale)
        guard let context = CGContext(data: nil,
                                      width: pixels,
                                      height: pixels,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: NSSize(width: boxSize, height: boxSize))
        }
        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.black.cgColor)

        for index in 0..<barCount {
            let radius = innerRadius + CGFloat(index) * radiusStep
            let isFilled = index < level
            context.setAlpha(isFilled ? 1 : emptyAlpha)
            context.setLineWidth(arcWidth)
            let spread = arcSpread * .pi / 180
            context.addArc(center: CGPoint(x: boxSize / 2, y: centerY),
                           radius: radius,
                           startAngle: .pi / 2 - spread,
                           endAngle: .pi / 2 + spread,
                           clockwise: false)
            context.strokePath()
        }

        guard let cgImage = context.makeImage() else {
            return NSImage(size: NSSize(width: boxSize, height: boxSize))
        }
        let size = NSSize(width: boxSize, height: boxSize)
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }
}
