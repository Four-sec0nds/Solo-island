import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Expected iconset directory") }
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let side = CGFloat(pixels)
        let inset = side * 0.06
        let background = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2), xRadius: side * 0.21, yRadius: side * 0.21)
        NSColor(calibratedRed: 0.15, green: 0.08, blue: 0.24, alpha: 1).setFill(); background.fill()
        let orbit = NSBezierPath(ovalIn: NSRect(x: side * 0.12, y: side * 0.34, width: side * 0.76, height: side * 0.30))
        var transform = AffineTransform(); transform.translate(x: side / 2, y: side / 2)
        transform.rotate(byDegrees: 28); transform.translate(x: -side / 2, y: -side / 2)
        orbit.transform(using: transform)
        NSColor(calibratedRed: 0.63, green: 0.36, blue: 0.95, alpha: 0.8).setStroke()
        orbit.lineWidth = max(1, side * 0.02); orbit.stroke()
        let capsule = NSBezierPath(roundedRect: NSRect(x: side * 0.18, y: side * 0.37, width: side * 0.64, height: side * 0.26), xRadius: side * 0.13, yRadius: side * 0.13)
        NSColor.black.setFill(); capsule.fill()
        for index in 0..<3 {
            let height = side * [0.10, 0.19, 0.13][index]
            let bar = NSBezierPath(roundedRect: NSRect(x: side * (0.415 + Double(index) * 0.065), y: (side - height) / 2, width: side * 0.035, height: height), xRadius: side * 0.017, yRadius: side * 0.017)
            NSColor(calibratedRed: 0.35, green: 0.94, blue: 0.79, alpha: 1).setFill(); bar.fill()
        }
        NSColor(calibratedRed: 0.35, green: 0.94, blue: 0.79, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: side * 0.79, y: side * 0.64, width: side * 0.075, height: side * 0.075)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
