import AppKit
import Combine
import SwiftUI
import IslandCore

@MainActor
private final class NotchPresentation: ObservableObject {
    @Published var activity: NotchActivity = .hidden
    @Published var cameraWidth: CGFloat = 176
    @Published var height: CGFloat = 28
    @Published var visible = false
}

/// It never takes focus or intercepts menu-bar clicks. Hover is tracked by the
/// main island controller, including these two small wings.
private final class NotchActivityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchActivityController: NSWindowController {
    static let wingWidth: CGFloat = 72
    private let store: IslandStore
    private let presentation = NotchPresentation()
    private var subscriptions = Set<AnyCancellable>()
    private var sleeping = false
    var isPresented: Bool { presentation.visible }

    init(store: IslandStore, reducedMotionOverride: Bool?) {
        self.store = store
        let panel = NotchActivityPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        super.init(window: panel)
        let root = NotchActivityView(store: store, media: store.media, presentation: presentation)
        let view: AnyView
        if let reducedMotionOverride { view = AnyView(root.environment(\.islandReducedMotionOverride, reducedMotionOverride)) }
        else { view = AnyView(root) }
        let hosting = NSHostingView(rootView: view); hosting.sizingOptions = []
        panel.contentView = hosting; panel.minSize = .zero; panel.contentMinSize = .zero
        store.$state.map(\.focus).removeDuplicates().sink { [weak self] focus in
            guard let self else { return }; self.update(track: self.store.media.track, focus: focus)
        }.store(in: &subscriptions)
        store.media.$track.sink { [weak self] track in
            guard let self else { return }; self.update(track: track, focus: self.store.state.focus)
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.sleeping = true; self?.updateVisibility() }
            }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.sleeping = false; self?.updateVisibility() }
            }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func close() {
        subscriptions.removeAll()
        presentation.visible = false
        super.close()
    }

    func layout(on screen: NSScreen, cameraWidth: CGFloat, height: CGFloat) {
        presentation.cameraWidth = cameraWidth + 16
        presentation.height = height
        let width = presentation.cameraWidth + Self.wingWidth * 2
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        if window?.frame != frame { window?.setFrame(frame, display: presentation.visible) }
        updateVisibility()
    }
    private func update(track: NowPlaying, focus: FocusSession?) {
        let next = NotchActivity(track: track, focus: focus)
        guard presentation.activity != next else { return }
        presentation.activity = next; updateVisibility()
    }
    private func updateVisibility() {
        let visible = presentation.activity.isVisible && !sleeping && (window?.frame.height ?? 0) > 0
        presentation.visible = visible
        if visible {
            if window?.isVisible != true { window?.orderFrontRegardless() }
        } else { window?.orderOut(nil) }
    }
}

@MainActor
private struct NotchActivityView: View {
    @ObservedObject var store: IslandStore
    @ObservedObject var media: MediaService
    @ObservedObject var presentation: NotchPresentation

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: NotchActivityController.wingWidth)
            Color.clear.frame(width: presentation.cameraWidth).accessibilityHidden(true)
            trailing.frame(width: NotchActivityController.wingWidth)
        }.frame(height: presentation.height)
            .background(.black, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12,
                                                           bottomTrailingRadius: 12, topTrailingRadius: 0))
            .foregroundStyle(IslandPalette.mint).preferredColorScheme(.dark).ignoresSafeArea()
            .accessibilityElement(children: .ignore).accessibilityLabel(accessibleStatus)
    }

    @ViewBuilder private var leading: some View {
        switch presentation.activity {
        case .hidden: EmptyView()
        case .music:
            Group {
                if let artwork = media.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let provider = store.state.settings.musicProvider {
                    MusicProviderIcon(provider: provider, size: 22)
                } else { Image(systemName: "music.note").font(.system(size: 17, weight: .medium)) }
            }
        case .focus(let paused, _):
            ZStack {
                Circle().stroke(IslandPalette.raised, lineWidth: 2)
                Circle().trim(from: 0, to: focusProgress)
                    .stroke(paused ? IslandPalette.lavender : IslandPalette.mint,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: paused ? "pause.fill" : "timer").font(.system(size: 10, weight: .medium))
            }.frame(width: 22, height: 22).foregroundStyle(paused ? IslandPalette.lavender : IslandPalette.mint)
        }
    }
    @ViewBuilder private var trailing: some View {
        switch presentation.activity {
        case .hidden: EmptyView()
        case .music(let playback):
            PlaybackBars(track: media.track, receivedAt: media.receivedAt,
                         playing: playback == .playing, visible: presentation.visible).frame(width: 19, height: 18)
        case .focus(let paused, let music):
            HStack(spacing: 6) {
                Text(store.focusedTime).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).fixedSize().foregroundStyle(paused ? IslandPalette.lavender : IslandPalette.mint)
                if let music {
                    PlaybackBars(track: media.track, receivedAt: media.receivedAt,
                                 playing: music == .playing, visible: presentation.visible).frame(width: 12, height: 14)
                }
            }
        }
    }
    private var focusProgress: Double {
        guard let focus = store.state.focus else { return 0 }
        return min(1, max(0, 1 - focus.remaining(at: store.now) / focus.duration))
    }
    private var accessibleStatus: String {
        switch presentation.activity {
        case .hidden: return ""
        case .music(let playback):
            return (playback == .playing ? "Играет: " : "Музыка на паузе: ") + (media.track.title ?? "")
        case .focus(let paused, let music):
            return (paused ? "Фокус на паузе, осталось " : "Фокус, осталось ") + store.focusedTime
                + (music == .playing ? ", музыка играет" : "")
        }
    }
}

struct PlaybackBars: View {
    var track: NowPlaying
    var receivedAt: Date
    var playing: Bool
    var visible = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.islandReducedMotionOverride) private var motionOverride
    private var moving: Bool { playing && visible && !(motionOverride ?? systemReduceMotion) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { timeline in
            let identity = (track.applicationID ?? "") + (track.artist ?? "") + (track.title ?? "")
            let levels = PlaybackIndicator.levels(position: track.position(at: timeline.date, receivedAt: receivedAt),
                                                  identity: identity, moving: moving)
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: max(1, geometry.size.width * 0.16)) {
                    ForEach(0..<3) { index in
                        Capsule().fill(playing ? IslandPalette.mint : IslandPalette.lavender)
                            .frame(height: max(2, geometry.size.height * levels[index]))
                    }
                }.frame(height: geometry.size.height)
            }
        }.accessibilityLabel(playing ? "Воспроизведение" : "Музыка на паузе")
    }
}
