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
            header.padding(.horizontal, 22).padding(.top, 19).padding(.bottom, 16)
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            HStack(spacing: 0) {
                sidebar.frame(width: 150)
                Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
                VStack(alignment: .leading, spacing: 13) {
                    if let error = store.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(error).font(.caption).lineLimit(3).textSelection(.enabled)
                            Spacer(minLength: 0)
                            Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }.padding(11).islandCard(tint: .orange)
                    }
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color(red: 0.055, green: 0.035, blue: 0.085)
                RadialGradient(colors: [Color.purple.opacity(0.13), .clear], center: .topLeading, startRadius: 0, endRadius: 500)
                RadialGradient(colors: [Color.blue.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 400)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: store.state.settings.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: store.state.settings.cornerRadius, style: .continuous)
                .strokeBorder(dropTargeted ? accent.opacity(0.8) : .white.opacity(0.1), lineWidth: dropTargeted ? 2 : 1)
        }
        .foregroundStyle(Color(red: 0.94, green: 0.92, blue: 0.98))
        .tint(accent).environment(\.islandAccent, accent)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: store.state.settings.animationDuration), value: store.tab)
        .onDrop(of: [UTType.fileURL, .image, .plainText], isTargeted: $dropTargeted) { providers in
            receive(providers)
        }
        .onChange(of: dropTargeted) { _, targeted in
            store.draggingFiles = targeted
            if targeted { store.reveal(.files) } else { store.hover(false) }
        }
        .onExitCommand { store.dismiss() }
    }
    @ViewBuilder private var content: some View {
        switch store.tab {
        case .music: MusicView(media: store.media, now: store.now)
        case .tasks: TasksView(store: store)
        case .focus: FocusView(store: store)
        case .files: FilesView(store: store)
        case .actions: ActionsView(store: store)
        case .settings: IslandSettingsView(store: store, media: store.media)
        }
    }
    private var accent: Color {
        if store.state.settings.coverAccent, store.media.artwork != nil { return Color(nsColor: store.media.artworkColor) }
        switch store.state.settings.accent {
        case "mint": return Color(red: 0.25, green: 0.86, blue: 0.78)
        case "orange": return .orange
        case "blue": return .cyan
        default: return Color(red: 0.67, green: 0.5, blue: 1)
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [.purple.opacity(0.9), .indigo.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkle").font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Solo Island").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(store.tab.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let toast = store.toast {
                Label(toast.message, systemImage: toast.symbol).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(accent).padding(.horizontal, 10).padding(.vertical, 8).background(accent.opacity(0.1), in: Capsule())
            } else if store.state.focus != nil {
                Button { store.tab = .focus } label: { Label(store.focusedTime, systemImage: "timer").monospacedDigit() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
            }
            Button { store.pinned.toggle() } label: {
                Image(systemName: store.pinned ? "pin.fill" : "pin").frame(width: 30, height: 30)
                    .foregroundStyle(store.pinned ? accent : Color.white.opacity(0.45))
            }.buttonStyle(.plain).help("Оставить окно открытым")
            Button { store.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 30, height: 30)
                    .background(.white.opacity(0.05), in: Circle())
            }.buttonStyle(.plain).help("Скрыть до наведения")
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ПРОСТРАНСТВО").font(.system(size: 8, weight: .semibold)).tracking(1.7).foregroundStyle(.white.opacity(0.3)).padding(.horizontal, 11).padding(.bottom, 6)
            ForEach(IslandTab.allCases) { tab in
                Button { store.tab = tab } label: {
                    HStack(spacing: 11) {
                        Image(systemName: tab.icon).font(.system(size: 14, weight: .medium)).frame(width: 20).foregroundStyle(tab.color)
                        Text(tab.rawValue).font(.system(size: 12, weight: store.tab == tab ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if tab == .files && !store.state.shelf.isEmpty {
                            Text("\(store.state.shelf.count)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        }
                    }.padding(.horizontal, 11).padding(.vertical, 11)
                        .background {
                            if store.tab == tab {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(LinearGradient(colors: [tab.color.opacity(0.18), tab.color.opacity(0.06)], startPoint: .leading, endPoint: .trailing))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain).foregroundStyle(store.tab == tab ? .white : .white.opacity(0.65))
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(.green.opacity(0.8)).frame(width: 5, height: 5)
                Text("Только на этом Mac").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.horizontal, 10)
        }.padding(.horizontal, 10).padding(.vertical, 20)
            .background(Color(red: 0.065, green: 0.04, blue: 0.095).opacity(0.65))
    }
    private func receive(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        if let image = NSImage(data: data) { store.addImage(image); store.reveal(.files) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                    let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    guard let url else { return }
                    // Load image bytes while a temporary drag representation is still alive.
                    let imageData = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? try? Data(contentsOf: url) : nil
                    Task { @MainActor in
                        if let imageData, let image = NSImage(data: imageData) { store.addImage(image) }
                        else { store.addFiles([url]) }
                        store.reveal(.files)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String else { return }
                    Task { @MainActor in store.addText(text); store.reveal(.files) }
                }
            }
        }
        return true
    }
}

@MainActor
struct CoverView: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else {
                ZStack {
                    LinearGradient(colors: [.purple.opacity(0.6), .indigo.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.36))
                }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }
}

@MainActor
struct EmptyState: View {
    @Environment(\.islandAccent) private var accent
    var icon: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(accent)
                .frame(width: 72, height: 72).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }
}

private struct IslandAccentKey: EnvironmentKey { static let defaultValue = Color.purple }
extension EnvironmentValues {
    var islandAccent: Color {
        get { self[IslandAccentKey.self] }
        set { self[IslandAccentKey.self] = newValue }
    }
}
extension View {
    func islandCard(tint: Color = .purple, radius: CGFloat = 18) -> some View {
        background(LinearGradient(colors: [tint.opacity(0.07), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}
private extension IslandTab {
    var color: Color {
        switch self {
        case .music: return .purple
        case .tasks: return .cyan
        case .focus: return .orange
        case .files: return .pink
        case .actions: return .yellow
        case .settings: return .indigo
        }
    }
}
