import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Development previews use only synthetic state and never capture the user's desktop.
@MainActor
enum PreviewRecorder {
    struct Frame { let image: CGImage; var delay: Double }
    static func snapshot(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap); return bitmap
    }
    static func png(_ window: NSWindow, to url: URL) throws {
        guard let data = snapshot(window)?.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
    static func animationFrame(_ window: NSWindow, canvas: NSSize, neckWidth: CGFloat, neckHeight: CGFloat) -> CGImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: Int(canvas.width) * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let actual = window.isVisible ? snapshot(window) : nil
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.1, green: 0.09, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: (canvas.width - neckWidth) / 2, y: canvas.height - neckHeight,
            width: neckWidth, height: neckHeight + 12), xRadius: 12, yRadius: 12).fill()
        if let actual {
            let size = window.frame.size
            let image = NSImage(size: size); image.addRepresentation(actual)
            image.draw(in: NSRect(x: (canvas.width - size.width) / 2, y: canvas.height - size.height, width: size.width, height: size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
    static func gif(_ frames: [Frame], to url: URL) throws {
        guard !frames.isEmpty, let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay, kCGImagePropertyGIFUnclampedDelayTime: frame.delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
