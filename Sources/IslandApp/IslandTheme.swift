import AppKit
import SwiftUI

enum IslandPalette {
    static let background = Color(islandHex: 0x100B18)
    static let navigation = Color(islandHex: 0x171020)
    static let surface = Color(islandHex: 0x1D1528)
    static let raised = Color(islandHex: 0x291F36)
    static let text = Color(islandHex: 0xF5F1FA)
    static let secondary = Color(islandHex: 0xB7ABC6)
    static let muted = Color(islandHex: 0x9C8EAD)
    static let mint = Color(islandHex: 0x86E6C5)
    static let lavender = Color(islandHex: 0xBAA4F5)
    static let pink = Color(islandHex: 0xF590AF)
    static let separator = Color(islandHex: 0x3B2E4A)

    static func foreground(on color: Color) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return .white }
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return luminance > 0.179 ? .black : .white
    }
}

extension Color {
    init(islandHex: UInt32) {
        self.init(red: Double((islandHex >> 16) & 255) / 255,
                  green: Double((islandHex >> 8) & 255) / 255,
                  blue: Double(islandHex & 255) / 255)
    }
}

struct IslandSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(IslandPalette.text)
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(IslandPalette.secondary)
            }
        }
    }
}

struct IslandStateBadge: View {
    let title: String
    var symbol: String? = nil
    var color: Color = IslandPalette.mint
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }.foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }
}
