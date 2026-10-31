import SwiftUI

struct IslandButtonStyle: ButtonStyle {
    enum Kind { case filled, soft, icon, bare }
    var kind: Kind = .soft
    init(_ kind: Kind = .soft) { self.kind = kind }
    func makeBody(configuration: Configuration) -> some View {
        IslandButtonSurface(configuration: configuration, kind: kind)
    }
}
private struct IslandButtonSurface: View {
    let configuration: ButtonStyleConfiguration
    let kind: IslandButtonStyle.Kind
    @Environment(\.islandAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }
    @State private var hovered = false
    private var color: Color { configuration.role == .destructive ? IslandPalette.pink : accent }
    private var radius: CGFloat { kind == .icon ? 12 : 13 }
    var body: some View {
        label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, kind == .bare ? 0 : kind == .icon ? 8 : 14)
            .padding(.vertical, kind == .bare ? 0 : kind == .icon ? 7 : 10)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color.opacity(focused ? 0.9 : kind == .bare ? (hovered ? 0.14 : 0) : hovered ? 0.4 : 0.16), lineWidth: focused ? 1.5 : 0.8)
            }
            .scaleEffect(!reduceMotion && configuration.isPressed && enabled ? 0.96 : 1)
            .offset(y: !reduceMotion && configuration.isPressed && enabled ? 1 : 0)
            .brightness(configuration.isPressed && enabled ? -0.035 : hovered && enabled ? 0.035 : 0)
            .opacity(enabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .onHover { hovered = $0 }
    }
    @ViewBuilder private var label: some View {
        if kind == .bare { configuration.label }
        else { configuration.label.foregroundStyle(kind == .filled ? IslandPalette.foreground(on: color) : color) }
    }
    private var background: Color {
        if kind == .filled { return color }
        if kind == .bare { return color.opacity(hovered || configuration.isPressed ? 0.08 : 0) }
        return color.opacity(hovered || configuration.isPressed ? 0.17 : 0.09)
    }
}

struct IslandSegments<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let title: (Selection) -> String
    @Environment(\.islandAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17)) { selection = option }
                } label: {
                    Text(title(option)).font(.system(size: 11, weight: selection == option ? .semibold : .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selection == option ? IslandPalette.text : IslandPalette.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(IslandPalette.raised)
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1))
                            }
                        }
                }.buttonStyle(IslandButtonStyle(.bare)).accessibilityAddTraits(selection == option ? .isSelected : [])
                    .recordingTarget(title(option))
            }
        }.padding(4).background(IslandPalette.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
struct IslandTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).padding(11)
            .background(IslandPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(IslandPalette.separator, lineWidth: 0.8))
    }
}

struct IslandSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void
    @Environment(\.islandAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }
    @State private var dragging = false
    @State private var hovered = false
    init(value: Binding<Double>, in range: ClosedRange<Double>, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value; self.range = range; self.onEditingChanged = onEditingChanged
    }
    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound))) }
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 12)
            ZStack(alignment: .leading) {
                Capsule().fill(IslandPalette.raised).frame(height: 4)
                Capsule().fill(accent)
                    .frame(width: 6 + width * fraction, height: 4)
                Circle().fill(IslandPalette.text).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(accent, lineWidth: 2))
                    .scaleEffect(!reduceMotion && dragging ? 1.35 : 1)
                    .offset(x: 1 + width * fraction)
            }.frame(height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    setFraction((event.location.x - 6) / width)
                }.onEnded { event in
                    setFraction((event.location.x - 6) / width)
                    dragging = false; onEditingChanged(false)
                })
        }.frame(height: 22)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragging)
            .accessibilityElement().accessibilityValue("\(Int(fraction * 100))%")
            .accessibilityAdjustableAction { direction in
                let delta = (range.upperBound - range.lowerBound) / 50
                onEditingChanged(true)
                if direction == .increment { value = min(range.upperBound, value + delta) }
                else if direction == .decrement { value = max(range.lowerBound, value - delta) }
                onEditingChanged(false)
            }
            .focusable()
            .onMoveCommand { direction in
                guard direction == .left || direction == .right else { return }
                onEditingChanged(true)
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .right ? 1 : -1) * (range.upperBound - range.lowerBound) / 50))
                onEditingChanged(false)
            }
    }
    private func setFraction(_ fraction: Double) { value = range.lowerBound + min(1, max(0, fraction)) * (range.upperBound - range.lowerBound) }
}

private struct IslandReducedMotionOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    var islandReducedMotionOverride: Bool? {
        get { self[IslandReducedMotionOverrideKey.self] }
        set { self[IslandReducedMotionOverrideKey.self] = newValue }
    }
}

struct IslandToggleStyle: ToggleStyle {
    @Environment(\.islandAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? accent : IslandPalette.raised)
                    Circle().fill(configuration.isOn ? IslandPalette.foreground(on: accent) : IslandPalette.secondary).padding(3)
                        .frame(width: 22, height: 22)
                }.frame(width: 38, height: 22)
                    .animation((motionOverride ?? systemReduceMotion) ? nil : .easeOut(duration: 0.16), value: configuration.isOn)
            }.buttonStyle(IslandButtonStyle(.bare)).accessibilityLabel(configuration.isOn ? "Выключить" : "Включить")
                .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
        }.contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
