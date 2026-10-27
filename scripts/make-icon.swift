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
        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1).setFill(); background.fill()
        let capsule = NSBezierPath(roundedRect: NSRect(x: side * 0.16, y: side * 0.34, width: side * 0.68, height: side * 0.32), xRadius: side * 0.16, yRadius: side * 0.16)
        NSColor.black.setFill(); capsule.fill()
        for index in 0..<5 {
            let height = side * [0.07, 0.14, 0.2, 0.11, 0.06][index]
            let bar = NSBezierPath(roundedRect: NSRect(x: side * (0.36 + Double(index) * 0.055), y: (side - height) / 2, width: side * 0.025, height: height), xRadius: side * 0.012, yRadius: side * 0.012)
            NSColor.systemMint.setFill(); bar.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
