import AppKit
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

@MainActor
struct IslandRootView: View {
    @ObservedObject var store: IslandStore
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }
    var body: some View {
        GeometryReader { geometry in
            let shape = NotchAttachmentShape(neckWidth: store.cameraWidth + 16, neckHeight: store.compactHeight, radius: store.state.settings.cornerRadius)
            ZStack(alignment: .top) {
                IslandPalette.background
                RadialGradient(colors: [IslandPalette.lavender.opacity(0.065), .clear], center: .topTrailing, startRadius: 0, endRadius: 500)
                Color.black.frame(height: store.compactHeight)
                expandedBody
                    .frame(width: store.presentationWidth, height: store.presentationHeight - store.compactHeight)
                    .opacity(store.contentVisible ? 1 : 0)
                    .position(x: geometry.size.width / 2, y: store.compactHeight + (store.presentationHeight - store.compactHeight) / 2)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: store.contentVisible)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(shape)
            .overlay(shape.stroke(dropTargeted ? accent.opacity(0.8) : IslandPalette.separator.opacity(0.7), lineWidth: dropTargeted ? 2 : 0.8))
        }
        .ignoresSafeArea()
        .foregroundStyle(IslandPalette.text)
        .tint(accent).environment(\.islandAccent, accent)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .preferredColorScheme(.dark)
        .buttonStyle(IslandButtonStyle(.soft))
        .toggleStyle(IslandToggleStyle())
        .animation(reduceMotion ? nil : .easeInOut(duration: store.state.settings.animationDuration), value: store.tab)
        .onDrop(of: [UTType.fileURL, .image, .plainText], isTargeted: $dropTargeted) { receive($0) }
        .onChange(of: dropTargeted) { _, targeted in
            store.draggingFiles = targeted
            if targeted { store.reveal(.files) } else { store.hover(false) }
        }
        .onExitCommand { store.dismiss() }
    }
    private var expandedBody: some View {
        VStack(spacing: 0) {
            topBar.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 10) {
                if let error = store.error {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).font(.system(size: 11)).lineLimit(3).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { store.error = nil } label: { Image(systemName: "checkmark") }
                            .buttonStyle(IslandButtonStyle(.icon)).accessibilityLabel("Скрыть сообщение")
                    }.padding(10).islandCard(tint: .orange)
                }
                Group {
                    if !store.state.settings.musicOnboardingComplete { MusicOnboardingView(store: store) }
                    else { content }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
            bottomBar
        }
    }
    @ViewBuilder private var content: some View {
        switch store.tab {
        case .music: MusicView(store: store, media: store.media, web: store.webMusic, now: store.now)
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
        case "mint": return IslandPalette.mint
        case "orange": return Color(islandHex: 0xF5BA88)
        case "blue": return Color(islandHex: 0x8BCBEF)
        default: return IslandPalette.lavender
        }
    }
    private var topBar: some View {
        HStack(spacing: 8) {
            IslandBrandMark(size: 22).accessibilityHidden(true)
            Text("Solo Island").font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandPalette.secondary)
            Spacer(minLength: 8)
            if let toast = store.toast {
                Label(toast.message, systemImage: toast.symbol)
                    .font(.system(size: 11)).foregroundStyle(accent).lineLimit(1)
                    .frame(maxWidth: 280, alignment: .trailing)
            } else if store.state.focus != nil && store.tab != .focus {
                Button { store.tab = .focus } label: {
                    Label(store.focusedTime, systemImage: "timer").monospacedDigit()
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(IslandButtonStyle(.bare)).foregroundStyle(accent)
                    .accessibilityLabel("Открыть фокус, осталось " + store.focusedTime)
            }
        }.frame(height: 24)
    }
    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Array(IslandTab.allCases.prefix(5).enumerated()), id: \.element.id) { index, tab in
                    Button { store.tab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon).font(.system(size: 16, weight: .medium))
                                .frame(height: 18)
                            Text(tab.rawValue).font(.system(size: 10, weight: store.tab == tab ? .semibold : .medium))
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }.frame(maxWidth: .infinity).frame(height: 44)
                            .background(store.tab == tab ? accent.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(IslandButtonStyle(.bare))
                        .foregroundStyle(store.tab == tab ? accent : IslandPalette.secondary)
                        .accessibilityLabel(tab.rawValue)
                        .accessibilityAddTraits(store.tab == tab ? .isSelected : [])
                        .help(tab.rawValue + " (⌘" + String(index + 1) + ")")
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .recordingTarget("Вкладка:" + tab.rawValue)
                }
            }.frame(maxWidth: 420)
            Spacer(minLength: 0)
            Rectangle().fill(IslandPalette.separator).frame(width: 0.5, height: 24)
            HStack(spacing: 6) {
                Button { store.tab = .settings } label: {
                    Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 20, height: 22)
                }.buttonStyle(IslandButtonStyle(.icon))
                    .background(store.tab == .settings ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(store.tab == .settings ? accent : IslandPalette.secondary)
                    .accessibilityLabel("Настройки").help("Настройки (⌘,)")
                    .accessibilityAddTraits(store.tab == .settings ? .isSelected : [])
                    .keyboardShortcut(",", modifiers: .command).recordingTarget("Вкладка:" + IslandTab.settings.rawValue)
                Button { store.pinned.toggle() } label: {
                    Image(systemName: store.pinned ? "pin.fill" : "pin").font(.system(size: 14)).frame(width: 20, height: 22)
                }.buttonStyle(IslandButtonStyle(.icon))
                    .background(store.pinned ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(store.pinned ? "Закреплено" : "Закрепить")
                    .accessibilityValue(store.pinned ? "Включено" : "Выключено")
                    .help("Удерживать островок открытым поверх остальных окон")
                    .recordingTarget(store.pinned ? "Закреплено" : "Закрепить")
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 14, weight: .medium)).frame(width: 20, height: 22)
                }.buttonStyle(IslandButtonStyle(.icon))
                    .accessibilityLabel("Завершить Solo Island").help("Завершить Solo Island полностью (⌘Q)")
                    .keyboardShortcut("q", modifiers: .command)
                    .recordingTarget("Завершить Solo Island:\(ObjectIdentifier(store))")
            }.fixedSize()
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
            .background(IslandPalette.navigation.opacity(0.85))
            .overlay(alignment: .top) { Rectangle().fill(IslandPalette.separator.opacity(0.45)).frame(height: 0.5) }
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
    var isPlaying = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying || (motionOverride ?? systemReduceMotion))) { timeline in
                    ZStack {
                        IslandPalette.surface
                        ZStack {
                            Circle().fill(Color(islandHex: 0x0C0A10))
                            ForEach(0..<5) { index in
                                Circle().stroke(IslandPalette.lavender.opacity(0.08), lineWidth: 0.7)
                                    .padding(CGFloat(index + 1) * size * 0.04)
                            }
                            Circle().fill(IslandPalette.lavender).frame(width: size * 0.34, height: size * 0.34)
                            Capsule().fill(IslandPalette.background).frame(width: size * 0.24, height: size * 0.105)
                                .rotationEffect(.degrees(-24))
                            Circle().fill(IslandPalette.mint).frame(width: size * 0.05, height: size * 0.05)
                                .offset(x: size * 0.11, y: -size * 0.045)
                        }.padding(size * 0.075)
                            .rotationEffect(.degrees(isPlaying && !(motionOverride ?? systemReduceMotion) ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 45) * 8 : 0))
                    }
                }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.16).strokeBorder(.white.opacity(0.06), lineWidth: 0.8))
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
            Image(systemName: icon).font(.system(size: 27, weight: .light)).foregroundStyle(accent)
                .frame(width: 64, height: 64).background(IslandPalette.surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(IslandPalette.secondary).multilineTextAlignment(.center).lineSpacing(3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }
}

private struct IslandAccentKey: EnvironmentKey { static let defaultValue = IslandPalette.mint }
extension EnvironmentValues {
    var islandAccent: Color {
        get { self[IslandAccentKey.self] }
        set { self[IslandAccentKey.self] = newValue }
    }
}
extension View {
    func islandCard(tint: Color = IslandPalette.lavender, radius: CGFloat = 16) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(IslandPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: radius).fill(tint.opacity(0.025)))
        }.overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(IslandPalette.separator.opacity(0.65), lineWidth: 0.7))
    }
}
/// A narrow black neck touches the screen edge; the body grows from the hardware notch.
struct NotchAttachmentShape: Shape {
    var neckWidth: CGFloat
    var neckHeight: CGFloat
    var radius: Double
    func path(in rect: CGRect) -> Path {
        guard rect.height > neckHeight + 1 else {
            return RoundedRectangle(cornerRadius: min(12, rect.height / 2), style: .continuous).path(in: rect)
        }
        let bodyY = neckHeight
        let r = min(CGFloat(radius), max(0, (rect.height - bodyY) / 2), rect.width / 3)
        let neck = min(neckWidth, max(1, rect.width - 2 * r))
        let left = (rect.width - neck) / 2, right = left + neck
        let shoulder = min(8, max(0, left - r))
        var p = Path()
        p.move(to: CGPoint(x: left, y: 0)); p.addLine(to: CGPoint(x: right, y: 0))
        p.addLine(to: CGPoint(x: right, y: bodyY - shoulder))
        p.addQuadCurve(to: CGPoint(x: right + shoulder, y: bodyY), control: CGPoint(x: right, y: bodyY))
        p.addLine(to: CGPoint(x: rect.width - r, y: bodyY))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: bodyY + r), control: CGPoint(x: rect.width, y: bodyY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        p.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: r, y: rect.height))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.height - r), control: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: bodyY + r))
        p.addQuadCurve(to: CGPoint(x: r, y: bodyY), control: CGPoint(x: 0, y: bodyY))
        p.addLine(to: CGPoint(x: left - shoulder, y: bodyY))
        p.addQuadCurve(to: CGPoint(x: left, y: bodyY - shoulder), control: CGPoint(x: left, y: bodyY))
        p.addLine(to: CGPoint(x: left, y: 0)); p.closeSubpath()
        return p
    }
}
