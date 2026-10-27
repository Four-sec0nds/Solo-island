import SwiftUI
import IslandCore

struct IslandBrandMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.12, blue: 0.4), Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Ellipse().stroke(Color.purple.opacity(0.65), lineWidth: max(1, size * 0.025))
                .frame(width: size * 0.84, height: size * 0.37).rotationEffect(.degrees(-28))
            Capsule().fill(Color.black).frame(width: size * 0.64, height: size * 0.28)
            HStack(spacing: size * 0.035) {
                ForEach(0..<3) { index in
                    Capsule().fill(Color(red: 0.35, green: 0.94, blue: 0.79))
                        .frame(width: size * 0.035, height: size * [0.10, 0.19, 0.13][index])
                }
            }
            Circle().fill(Color(red: 0.35, green: 0.94, blue: 0.79)).frame(width: size * 0.075, height: size * 0.075)
                .offset(x: size * 0.33, y: -size * 0.18)
        }.frame(width: size, height: size).accessibilityLabel("Solo Island")
    }
}

struct MusicProviderIcon: View {
    let provider: MusicProvider
    var size: CGFloat = 34
    var body: some View {
        Canvas { context, geometry in
            let s = geometry.width
            func path(_ points: [CGPoint], close: Bool = false) -> Path {
                var p = Path(); guard let first = points.first else { return p }; p.move(to: first)
                for point in points.dropFirst() { p.addLine(to: point) }; if close { p.closeSubpath() }; return p
            }
            switch provider {
            case .yandex:
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: s * 0.26), with: .color(Color(red: 1, green: 0.78, blue: 0.18)))
                context.draw(Text("Я").font(.system(size: s * 0.7, weight: .bold)).foregroundColor(.black), at: CGPoint(x: s / 2, y: s / 2))
            case .spotify:
                context.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: s, height: s)), with: .color(Color(red: 0.12, green: 0.83, blue: 0.37)))
                for index in 0..<3 {
                    var p = Path(); let y = s * (0.33 + Double(index) * 0.17)
                    p.move(to: CGPoint(x: s * 0.22, y: y)); p.addQuadCurve(to: CGPoint(x: s * 0.78, y: y + s * 0.05), control: CGPoint(x: s * 0.5, y: y - s * 0.13))
                    context.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: s * (0.065 - Double(index) * 0.009), lineCap: .round))
                }
            case .youtube:
                context.fill(Path(roundedRect: CGRect(x: 0, y: s * 0.12, width: s, height: s * 0.76), cornerRadius: s * 0.22), with: .color(Color(red: 0.98, green: 0.15, blue: 0.24)))
                context.fill(path([CGPoint(x: s * 0.4, y: s * 0.29), CGPoint(x: s * 0.72, y: s * 0.5), CGPoint(x: s * 0.4, y: s * 0.71)], close: true), with: .color(.white))
            case .soundcloud:
                let color = Color(red: 1, green: 0.43, blue: 0.12)
                for i in 0..<5 {
                    let h = s * (0.2 + Double(i) * 0.075)
                    context.fill(Path(roundedRect: CGRect(x: Double(i) * s * 0.09, y: s * 0.65 - h, width: s * 0.045, height: h), cornerRadius: s * 0.02), with: .color(color))
                }
                context.fill(Path(ellipseIn: CGRect(x: s * 0.4, y: s * 0.23, width: s * 0.43, height: s * 0.5)), with: .color(color))
                context.fill(Path(roundedRect: CGRect(x: s * 0.4, y: s * 0.45, width: s * 0.6, height: s * 0.28), cornerRadius: s * 0.14), with: .color(color))
            case .apple:
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: s * 0.25), with: .linearGradient(Gradient(colors: [.pink, .red]), startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
                context.draw(Text("♪").font(.system(size: s * 0.83, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: s / 2, y: s / 2))
            }
        }.frame(width: size, height: size).accessibilityLabel(provider.title)
    }
}

@MainActor
struct MusicProviderGrid: View {
    let selected: MusicProvider?
    var select: (MusicProvider) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            ForEach(MusicProvider.allCases) { provider in
                Button { select(provider) } label: {
                    HStack(spacing: 10) {
                        MusicProviderIcon(provider: provider, size: 30)
                        Text(provider.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if selected == provider { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint) }
                    }.padding(10).frame(maxWidth: .infinity).islandCard(tint: selected == provider ? .mint : .purple)
                }.buttonStyle(IslandButtonStyle(.bare)).recordingTarget(provider.title)
            }
        }
    }
}

@MainActor
struct MusicOnboardingView: View {
    @ObservedObject var store: IslandStore
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                IslandBrandMark(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Что ты слушаешь?").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Выбери сервис для своего островка.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            MusicProviderGrid(selected: store.state.settings.musicProvider) { store.selectMusicProvider($0) }
            Text("Сайт сервиса откроется внутри Solo Island. Войди в свой аккаунт и запусти музыку — управление появится в островке.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Пока использовать системный плеер") { store.skipMusicSetup() }
                .buttonStyle(IslandButtonStyle(.bare)).font(.system(size: 11)).foregroundStyle(.mint)
            Spacer(minLength: 0)
        }
    }
}
