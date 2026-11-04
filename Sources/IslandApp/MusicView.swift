import SwiftUI
import IslandCore

@MainActor
struct MusicView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @ObservedObject var media: MediaService
    @ObservedObject var web: WebMusicService
    var now: Date
    @State private var seeking: Double?
    var body: some View {
        VStack(spacing: 8) {
            if let provider = store.state.settings.musicProvider {
                HStack(spacing: 8) {
                    MusicProviderIcon(provider: provider, size: 22)
                    Text(provider.title).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.secondary)
                    Spacer()
                    Button(store.musicWebsiteVisible ? "К плееру" : "Веб-плеер / вход") {
                        web.configure(provider); store.musicWebsiteVisible.toggle()
                    }.font(.system(size: 11)).buttonStyle(IslandButtonStyle(.soft))
                        .recordingTarget(store.musicWebsiteVisible ? "К плееру" : "Веб-плеер / вход")
                }
            }
            playbackContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var playbackContent: some View {
        VStack(spacing: 6) {
            if let error = playbackError {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.orange)
                    Text(error).font(.system(size: 11)).foregroundStyle(IslandPalette.secondary).lineLimit(1).help(error)
                    Spacer(minLength: 0)
                }.padding(4).islandCard(tint: .orange)
            }
            Spacer(minLength: 0)
            if media.track.hasTrack { player }
            else {
                VStack(spacing: 8) {
                    IslandBrandMark(size: 40)
                    Text("Включи любимую музыку").font(.system(size: 20, weight: .semibold, design: .rounded))
                    if let provider = store.state.settings.musicProvider {
                        Text("Войди на сайте сервиса и выбери трек.\nМузыка играет прямо внутри Solo Island.")
                            .font(.system(size: 12)).foregroundStyle(IslandPalette.secondary).multilineTextAlignment(.center)
                        Button { web.configure(provider); store.musicWebsiteVisible = true } label: {
                            Label("Открыть веб-плеер", systemImage: "play.fill")
                        }.buttonStyle(IslandButtonStyle(.filled))
                        Button("Открыть сервис в браузере") { web.openInBrowser() }.font(.caption)
                    } else {
                        Text("Системный плеер работает с активным источником macOS.")
                            .font(.system(size: 12)).foregroundStyle(IslandPalette.secondary).multilineTextAlignment(.center)
                        Button("Выбрать музыкальный сервис") { store.setSettings { $0.musicOnboardingComplete = false } }
                            .buttonStyle(IslandButtonStyle(.filled))
                    }
                }.frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
    }
    private var player: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Button { media.openSource() } label: {
                    CoverView(image: media.artwork, size: 104,
                              isPlaying: media.track.isPlaying && store.expanded && store.contentVisible)
                }.buttonStyle(IslandButtonStyle(.bare)).help("Открыть текущий плеер")
                    .accessibilityLabel("Открыть текущий плеер")
                VStack(alignment: .leading, spacing: 6) {
                    Text(media.track.title ?? "").font(.system(size: 19, weight: .semibold, design: .rounded))
                        .lineLimit(playbackError == nil ? 2 : 1).minimumScaleFactor(0.8).foregroundStyle(IslandPalette.text)
                    if let artist = media.track.artist, !artist.isEmpty {
                        Text(artist).font(.system(size: 12)).foregroundStyle(IslandPalette.secondary).lineLimit(1)
                    }
                    HStack(spacing: 7) {
                        Circle().fill(media.track.isPlaying ? accent : IslandPalette.lavender).frame(width: 5, height: 5)
                        Button { media.openSource() } label: {
                            Label(media.sourceName, systemImage: "arrow.up.right")
                                .font(.system(size: 10)).lineLimit(1).foregroundStyle(IslandPalette.secondary)
                        }.buttonStyle(IslandButtonStyle(.bare)).help("Открыть текущий плеер")
                    }
                    transport.padding(.top, 2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 1) {
                IslandSlider(value: Binding(get: { seeking ?? displayedPosition }, set: { seeking = $0 }),
                       in: 0...max(1, media.track.duration ?? 1), emphasized: true, onEditingChanged: { editing in
                    if !editing, let value = seeking { media.seek(value); seeking = nil }
                }).disabled(!media.track.canSeek)
                    .accessibilityLabel("Позиция воспроизведения").recordingTarget("Позиция воспроизведения")
                HStack {
                    Text(media.track.elapsedTime != nil || seeking != nil ? IslandStore.clock(Int(seeking ?? displayedPosition)) : "—:—")
                    Spacer()
                    if media.track.canSeek { Text(IslandStore.clock(Int(media.track.duration ?? 0))) }
                    else { Text("Длительность пока недоступна").font(.system(size: 10)) }
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(IslandPalette.secondary)
            }
        }.padding(12).islandCard(radius: 16)
    }
    private var displayedPosition: Double {
        media.track.elapsedTime == nil ? 0 : media.track.position(at: now, receivedAt: media.receivedAt)
    }
    private var playbackError: String? { web.error ?? (media.usingWeb ? nil : media.error) }
    private var transport: some View {
        HStack(spacing: 8) {
            Button { media.command(["previous-track"]) } label: {
                Image(systemName: "backward.fill").font(.system(size: 15)).frame(width: 20, height: 22)
            }.buttonStyle(IslandButtonStyle(.icon)).disabled(media.track.prohibitsSkip == true)
                .accessibilityLabel("Предыдущий трек").recordingTarget("Предыдущий трек")
            Button { media.command(["toggle-play-pause"]) } label: {
                Image(systemName: media.track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17)).frame(width: 23, height: 23)
            }.buttonStyle(IslandButtonStyle(.filled))
                .accessibilityLabel(media.track.isPlaying ? "Пауза" : "Воспроизвести")
                .recordingTarget(media.track.isPlaying ? "Пауза" : "Воспроизвести")
            Button { media.command(["next-track"]) } label: {
                Image(systemName: "forward.fill").font(.system(size: 15)).frame(width: 20, height: 22)
            }.buttonStyle(IslandButtonStyle(.icon)).disabled(media.track.prohibitsSkip == true)
                .accessibilityLabel("Следующий трек").recordingTarget("Следующий трек")
        }
    }
}
