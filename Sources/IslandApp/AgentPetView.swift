import AppKit
import SwiftUI
import ImageIO
import IslandCore

/// Downloaded sprite atlases are decoded once and cropped in memory. No web
/// view, network fetch, cache directory or external pet app runs at runtime.
@MainActor
enum AgentPetSprites {
    private static var atlases: [AgentProvider: CGImage] = [:]
    private static var cells: [String: CGImage] = [:]
    static func frame(provider: AgentProvider, row: Int, column: Int) -> CGImage? {
        let key = provider.rawValue + ":" + String(row) + ":" + String(column)
        if let cached = cells[key] { return cached }
        let atlas: CGImage
        if let cached = atlases[provider] { atlas = cached }
        else {
            guard let url = Bundle.main.url(forResource: provider.rawValue, withExtension: "webp", subdirectory: "AgentPets"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 1536, image.height == 1872 else { return nil }
            atlases[provider] = image; atlas = image
        }
        guard let image = atlas.cropping(to: CGRect(x: CGFloat(column * 192), y: CGFloat(row * 208), width: 192, height: 208)) else { return nil }
        cells[key] = image; return image
    }
}

struct AgentPetView: View {
    var provider: AgentProvider
    var size: CGFloat = 42
    var working = false
    var waiting = false
    var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    private var moving: Bool { visible && (working || waiting) && !(motionOverride ?? reduceMotion) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !moving)) { timeline in
            let column = moving ? Int(timeline.date.timeIntervalSinceReferenceDate * 6) % 6 : 0
            let row = waiting ? 6 : working ? 7 : 0
            Group {
                if let image = AgentPetSprites.frame(provider: provider, row: row, column: column) {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: provider == .claude ? "text.bubble" : "terminal")
                        .foregroundStyle(IslandPalette.secondary)
                }
            }
        }.frame(width: size, height: size)
            .accessibilityLabel(provider == .claude ? "Clawd — питомец Claude Code" : "Питомец Codex")
    }
}

@MainActor
struct AgentTabButton: View {
    @ObservedObject var agents: AgentService
    var selected: Bool
    var action: () -> Void
    @Environment(\.islandAccent) private var accent
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: agents.pending.isEmpty ? "terminal" : "hand.raised.fill")
                    .font(.system(size: 15, weight: .medium)).frame(height: 17)
                    .overlay(alignment: .topTrailing) {
                        if agents.activity.current != nil {
                            Circle().fill(accent).frame(width: 5, height: 5).offset(x: 5, y: -2)
                        }
                    }
                Text("Агенты").font(.system(size: 9, weight: selected ? .semibold : .medium))
            }.frame(maxWidth: .infinity).frame(height: 42)
                .background(selected ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(IslandButtonStyle(.bare))
            .foregroundStyle(selected || !agents.pending.isEmpty ? accent : IslandPalette.secondary)
            .accessibilityLabel("Агенты, запросов: \(agents.pending.count)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .keyboardShortcut("6", modifiers: .command).help("Агенты (⌘6)")
            .recordingTarget("Вкладка:Агенты")
    }
}
