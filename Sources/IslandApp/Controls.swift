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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    private var color: Color { configuration.role == .destructive ? .pink : accent }
    private var radius: CGFloat { kind == .icon ? 12 : 14 }
    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, kind == .bare ? 0 : kind == .icon ? 8 : 14)
            .padding(.vertical, kind == .bare ? 0 : kind == .icon ? 7 : 10)
            .foregroundStyle(kind == .filled ? .white : color.opacity(enabled ? 1 : 0.5))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: background, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color.opacity(kind == .bare ? (hovered ? 0.16 : 0) : hovered ? 0.4 : 0.18), lineWidth: 1)
            }
            .shadow(color: color.opacity(hovered && enabled && kind != .bare ? 0.16 : 0), radius: 10, y: 3)
            .scaleEffect(!reduceMotion && configuration.isPressed && enabled ? 0.96 : 1)
            .offset(y: !reduceMotion && configuration.isPressed && enabled ? 1 : 0)
            .brightness(configuration.isPressed && enabled ? 0.06 : 0)
            .opacity(enabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .onHover { hovered = $0 }
    }
    private var background: [Color] {
        if kind == .filled { return [color.opacity(configuration.isPressed ? 1 : 0.85), Color.purple.opacity(0.8)] }
        if kind == .bare { return [color.opacity(hovered || configuration.isPressed ? 0.08 : 0), .clear] }
        return [color.opacity(hovered || configuration.isPressed ? 0.2 : 0.12), Color.purple.opacity(0.08)]
    }
}

struct IslandSegments<Selection: Hashable>: View {
    let options: [Selection]
    @Binding var selection: Selection
    let title: (Selection) -> String
    @Environment(\.islandAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17)) { selection = option }
                } label: {
                    Text(title(option)).font(.system(size: 11, weight: selection == option ? .semibold : .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selection == option ? Color.white : Color.white.opacity(0.48))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(LinearGradient(colors: [accent.opacity(0.32), .purple.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1))
                            }
                        }
                }.buttonStyle(IslandButtonStyle(.bare)).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }.padding(4).background(Color.purple.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.purple.opacity(0.12), lineWidth: 1))
    }
}
struct IslandTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(11)
            .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.purple.opacity(0.18), lineWidth: 1))
    }
}
