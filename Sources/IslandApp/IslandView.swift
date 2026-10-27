import AppKit
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

@MainActor
struct IslandRootView: View {
    @ObservedObject var store: IslandStore
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(store: store, media: store.media)
                .frame(height: store.compactHeight)
                .contentShape(Rectangle())
                .onTapGesture { store.reveal() }
            if store.expanded {
                VStack(spacing: 12) {
                    navigation
                    if let error = store.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(error).font(.caption).lineLimit(3).textSelection(.enabled)
                            Spacer(minLength: 0)
                            Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Group {
                        switch store.tab {
                        case .music: MusicView(media: store.media, now: store.now)
                        case .tasks: TasksView(store: store)
                        case .focus: FocusView(store: store)
                        case .files: FilesView(store: store)
                        case .actions: ActionsView(store: store)
                        case .settings: IslandSettingsView(store: store, media: store.media)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .clipShape(IslandShape(radius: store.state.settings.cornerRadius))
        .overlay { if dropTargeted { IslandShape(radius: store.state.settings.cornerRadius).stroke(accent.opacity(0.8), lineWidth: 2) } }
        .foregroundStyle(.white)
        .tint(accent)
        .environment(\.islandAccent, accent)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: store.state.settings.animationDuration), value: store.expanded)
        .onHover { store.hover($0) }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            let group = DispatchGroup(), collector = DroppedURLs()
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL { collector.add(url) }
                    else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { collector.add(url) }
                }
            }
            group.notify(queue: .main) { store.addFiles(collector.values); store.reveal(.files) }
            return !providers.isEmpty
        }
        .onChange(of: dropTargeted) { _, targeted in
            store.draggingFiles = targeted
            if targeted { store.reveal(.files) } else { store.hover(false) }
        }
        .onExitCommand { store.dismiss() }
    }
    private var accent: Color {
        if store.state.settings.coverAccent { return Color(nsColor: store.media.artworkColor) }
        switch store.state.settings.accent {
        case "purple": return .purple
        case "orange": return .orange
        case "blue": return .blue
        default: return .mint
        }
    }
    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach(IslandTab.allCases) { tab in
                Button { store.tab = tab } label: {
                    Image(systemName: tab.icon).font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .foregroundStyle(store.tab == tab ? accent : Color.white.opacity(0.5))
                        .background(store.tab == tab ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help(tab.rawValue).accessibilityLabel(tab.rawValue)
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            Button { store.pinned.toggle() } label: {
                Image(systemName: store.pinned ? "pin.fill" : "pin").frame(width: 30, height: 32)
                    .foregroundStyle(store.pinned ? accent : .white.opacity(0.5))
            }.buttonStyle(.plain).help("Закрепить раскрытым")
            Button { store.dismiss() } label: { Image(systemName: "chevron.up").frame(width: 24, height: 32) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help("Свернуть")
        }
    }
}

private final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func add(_ url: URL) { lock.lock(); defer { lock.unlock() }; storage.append(url) }
    var values: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

struct IslandShape: Shape {
    var radius: Double
    var animatableData: Double { get { radius } set { radius = newValue } }
    func path(in rect: CGRect) -> Path {
        let r = min(CGFloat(radius), rect.height / 2)
        var p = Path()
        p.move(to: .zero); p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - r), control: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath(); return p
    }
}

@MainActor
struct IslandHeader: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @ObservedObject var media: MediaService
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let toast = store.toast { Image(systemName: toast.symbol).foregroundStyle(accent) }
                else if store.state.focus != nil { Image(systemName: "timer").foregroundStyle(accent) }
                else { CoverView(image: media.artwork, size: 24) }
                if store.expanded {
                    Text(store.toast?.message ?? "SOLO").font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(store.toast == nil ? 2 : 0).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: store.cameraWidth)
            HStack(spacing: 6) {
                if let toast = store.toast, let progress = toast.progress {
                    Text("\(Int(progress * 100))%").font(.system(size: 10, weight: .semibold, design: .monospaced))
                } else if store.state.focus != nil {
                    Text(store.focusedTime).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(accent)
                } else { Waveform(playing: media.track.isPlaying).frame(width: 24, height: 18) }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.state.focus != nil ? "Фокус: \(store.focusedTime)" : (media.track.title ?? "Solo Island"))
        .help(store.toast?.message ?? media.track.title ?? "Solo Island")
    }
}

@MainActor
struct CoverView: View {
    @Environment(\.islandAccent) private var accent
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { LinearGradient(colors: [.mint.opacity(0.4), .indigo.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "music.note").font(.system(size: size * 0.36)) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
@MainActor
struct Waveform: View {
    @Environment(\.islandAccent) private var accent
    var playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !playing || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5) { index in
                    Capsule().fill(accent).frame(width: 3, height: playing && !reduceMotion ? 4 + abs(sin(time * 4 + Double(index) * 1.7)) * 13 : 4)
                }
            }.frame(height: 18)
        }
    }
}

@MainActor
struct EmptyState: View {
    @Environment(\.islandAccent) private var accent
    var icon: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(accent)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }
}

private struct IslandAccentKey: EnvironmentKey { static let defaultValue = Color.mint }
extension EnvironmentValues {
    var islandAccent: Color {
        get { self[IslandAccentKey.self] }
        set { self[IslandAccentKey.self] = newValue }
    }
}
