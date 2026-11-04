import SwiftUI
import IslandCore

/// Small original pixel sprites, rendered at native resolution. Their motion
/// reflects a real session; no activity or permission state is invented here.
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
        TimelineView(.animation(minimumInterval: 0.25, paused: !moving)) { timeline in
            let frame = moving ? Int(timeline.date.timeIntervalSinceReferenceDate * 4) % 4 : 0
            Canvas { context, canvas in
                let unit = min(canvas.width / 28, canvas.height / 24)
                let origin = CGPoint(x: (canvas.width - 28 * unit) / 2, y: (canvas.height - 24 * unit) / 2)
                func pixel(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                    let rect = CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit, height: height * unit)
                    context.fill(Path(rect), with: .color(color))
                }
                let ink = Color(islandHex: 0x1C1726)
                let body = provider == .claude ? Color(islandHex: 0xF3A06A) : IslandPalette.mint
                let light = provider == .claude ? Color(islandHex: 0xFFD0A3) : Color(islandHex: 0xD3FFF1)
                let shade = provider == .claude ? Color(islandHex: 0xC66B42) : Color(islandHex: 0x58B3A6)
                let step: CGFloat = frame == 1 || frame == 2 ? 1 : 0
                if provider == .claude {
                    // Eight short, stepped legs make the orange spider legible
                    // even beside the physical camera at 24 points.
                    for index in 0..<4 {
                        let y = CGFloat(6 + index * 3), shift = index % 2 == 0 ? step : -step
                        pixel(4, y, 4, 2, body); pixel(2, y - 1 + shift, 2, 3, body)
                        pixel(20, y, 4, 2, body); pixel(24, y - 1 - shift, 2, 3, body)
                    }
                    pixel(8, 4, 12, 2, light); pixel(6, 6, 16, 11, body)
                    pixel(8, 17, 12, 2, shade); pixel(7, 6, 2, 3, light)
                    pixel(10, 9, 2, frame == 3 ? 1 : 3, ink)
                    pixel(16, 9, 2, frame == 3 ? 1 : 3, ink)
                    pixel(13, 14, 2, 1, shade)
                } else {
                    // Byte is a mint robot cat: square ears, a little muzzle,
                    // four paws and a stepped tail, not a generic terminal icon.
                    pixel(6, 3, 4, 5, body); pixel(18, 3, 4, 5, body)
                    pixel(7, 4, 2, 2, IslandPalette.lavender); pixel(19, 4, 2, 2, IslandPalette.lavender)
                    pixel(9, 5, 10, 2, light); pixel(6, 7, 16, 10, body)
                    pixel(8, 17, 12, 2, shade); pixel(7, 7, 2, 3, light)
                    pixel(10, 10, 2, frame == 3 ? 1 : 2, ink); pixel(16, 10, 2, frame == 3 ? 1 : 2, ink)
                    pixel(13, 13, 2, 1, ink); pixel(12, 14, 4, 1, shade)
                    pixel(8, 19 - step, 3, 2, body); pixel(17, 19 + step, 3, 2, body)
                    pixel(22, 14, 3, 2, shade); pixel(24, 10 - step, 2, 5, body)
                    if waiting { pixel(3, 7 - step, 2, 5, light) }
                }
            }
        }.frame(width: size, height: size)
            .accessibilityLabel(provider == .claude ? "Паучок — питомец Claude Code" : "Байт — кот-робот Codex")
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
