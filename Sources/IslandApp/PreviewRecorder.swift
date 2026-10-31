import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Development previews use only synthetic state and never capture the user's desktop.
@MainActor
enum PreviewRecorder {
    struct Frame { let image: CGImage; var delay: Double }
    static func snapshot(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap); return bitmap
    }
    static func png(_ window: NSWindow, to url: URL, overlay: NSWindow? = nil) throws {
        guard var bitmap = snapshot(window) else { throw CocoaError(.fileWriteUnknown) }
        // Composite only our own two native windows, never the desktop or camera.
        if let overlay, overlay.isVisible, let foreground = snapshot(overlay) {
            let size = window.frame.size
            guard let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: Int(size.width) * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: canvas) else { throw CocoaError(.fileWriteUnknown) }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            context.cgContext.clear(NSRect(origin: .zero, size: size))
            let background = NSImage(size: size); background.addRepresentation(bitmap)
            background.draw(in: NSRect(origin: .zero, size: size))
            let image = NSImage(size: overlay.frame.size); image.addRepresentation(foreground)
            image.draw(in: NSRect(x: overlay.frame.minX - window.frame.minX, y: overlay.frame.minY - window.frame.minY,
                                 width: overlay.frame.width, height: overlay.frame.height))
            NSGraphicsContext.restoreGraphicsState(); bitmap = canvas
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
    /// Native test navigation follows a real control, independent of section height.
    static func revealControl(_ name: String, in window: NSWindow, topMargin: CGFloat = 45) -> Bool {
        guard CommandLine.arguments.contains("--render-preview"), let view = window.contentView,
              let target = RecordingTargets.frames[name] else { return false }
        func scrollViews(_ root: NSView) -> [NSScrollView] {
            (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap(scrollViews)
        }
        guard let scroll = scrollViews(view).filter({ !$0.isHidden && $0.bounds.height > 70 })
            .max(by: { $0.bounds.height < $1.bounds.height }), let document = scroll.documentView else { return false }
        let viewport = scroll.convert(scroll.bounds, to: nil)
        let viewportTop = window.frame.height - viewport.maxY
        let current = scroll.contentView.bounds.origin
        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
        let y = min(maximum, max(0, current.y + target.midY - viewportTop - topMargin))
        scroll.contentView.scroll(to: NSPoint(x: current.x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
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
