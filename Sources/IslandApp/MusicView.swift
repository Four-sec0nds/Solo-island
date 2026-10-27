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
        VStack(spacing: 10) {
            if let provider = store.state.settings.musicProvider {
                HStack(spacing: 8) {
                    MusicProviderIcon(provider: provider, size: 22)
                    Text(provider.title).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button(store.musicWebsiteVisible ? "К плееру" : "Веб-плеер / вход") {
                        web.configure(provider); store.musicWebsiteVisible.toggle()
                    }.font(.system(size: 10)).buttonStyle(IslandButtonStyle(.soft))
                }
            }
            if store.musicWebsiteVisible, let provider = store.state.settings.musicProvider {
                website(provider)
            } else {
                if let error = web.error ?? (media.usingWeb ? nil : media.error) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.orange)
                        Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 0)
                    }.padding(8).islandCard(tint: .orange)
                }
                Spacer(minLength: 0)
                if media.track.hasTrack { player }
                else {
                    VStack(spacing: 13) {
                        IslandBrandMark(size: 76)
                        Text("Включи любимую музыку").font(.system(size: 20, weight: .semibold, design: .rounded))
                        if let provider = store.state.settings.musicProvider {
                            Text("Войди на сайте сервиса и выбери трек.\nМузыка играет прямо внутри Solo Island.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button { web.configure(provider); store.musicWebsiteVisible = true } label: {
                                Label("Открыть веб-плеер", systemImage: "play.fill")
                            }.buttonStyle(IslandButtonStyle(.filled))
                            Button("Открыть сервис в браузере") { web.openInBrowser() }.font(.caption)
                        } else {
                            Text("Системный плеер работает с активным источником macOS.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Выбрать музыкальный сервис") { store.setSettings { $0.musicOnboardingComplete = false } }
                                .buttonStyle(IslandButtonStyle(.filled))
                        }
                    }.frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: store.musicWebsiteVisible) { _, visible in store.editingForm = visible }
            .onAppear { store.editingForm = store.musicWebsiteVisible }
            .onDisappear { store.editingForm = false }
    }
    private func website(_ provider: MusicProvider) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 9) {
                Button { if let popup = web.popup { popup.goBack() } else { web.webView.goBack() } } label: { Image(systemName: "chevron.left") }
                Button { if let popup = web.popup { popup.reload() } else { web.reload() } } label: { Image(systemName: "arrow.clockwise") }
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                Text((web.popup ?? web.webView).url?.host ?? provider.url.host ?? "").font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if web.popup != nil { Button("Назад") { web.popup = nil }.font(.system(size: 9)) }
                if web.loading { ProgressView().controlSize(.small) }
                Button { web.openInBrowser() } label: { Image(systemName: "safari") }.help("Открыть в браузере")
            }.buttonStyle(IslandButtonStyle(.bare)).padding(.horizontal, 3)
            if let error = web.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
            EmbeddedMusicWebsite(webView: web.popup ?? web.webView)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Вход и подписка — на стороне сервиса. Если сайт ограничивает встроенный вход или защищённое аудио, открой его в браузере: системный плеер продолжит работать.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private var player: some View {
        VStack(spacing: 14) {
            Button { media.openSource() } label: {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 4, height: 4)
                    Text(media.sourceName).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(accent)
                }.padding(.horizontal, 10).padding(.vertical, 5)
            }.buttonStyle(IslandButtonStyle(.bare)).help("Открыть текущий плеер")
            Button { media.openSource() } label: { CoverView(image: media.artwork, size: 96) }
                .buttonStyle(IslandButtonStyle(.bare)).shadow(color: accent.opacity(0.2), radius: 16, y: 6)
            VStack(spacing: 5) {
                Text(media.track.title ?? "").font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                Text(media.track.artist ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity)
            if media.track.canSeek {
                VStack(spacing: 2) {
                    IslandSlider(value: Binding(get: { seeking ?? media.track.position(at: now, receivedAt: media.receivedAt) }, set: { seeking = $0 }),
                           in: 0...max(1, media.track.duration ?? 1), onEditingChanged: { editing in
                        if !editing, let value = seeking { media.seek(value); seeking = nil }
                    }).accessibilityLabel("Позиция воспроизведения")
                    HStack {
                        Text(IslandStore.clock(Int(seeking ?? media.track.position(at: now, receivedAt: media.receivedAt))))
                        Spacer()
                        Text(IslandStore.clock(Int(media.track.duration ?? 0)))
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(maxWidth: 310)
            }
            HStack(spacing: 16) {
                Button { media.command(["previous-track"]) } label: { Image(systemName: "backward.fill").font(.system(size: 18)).frame(width: 27, height: 30) }
                    .buttonStyle(IslandButtonStyle(.soft)).disabled(media.track.prohibitsSkip == true).accessibilityLabel("Предыдущий трек")
                Button { media.command(["toggle-play-pause"]) } label: {
                    Image(systemName: media.track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 24)).frame(width: 38, height: 34)
                }.buttonStyle(IslandButtonStyle(.filled)).accessibilityLabel(media.track.isPlaying ? "Пауза" : "Воспроизвести")
                Button { media.command(["next-track"]) } label: { Image(systemName: "forward.fill").font(.system(size: 18)).frame(width: 27, height: 30) }
                    .buttonStyle(IslandButtonStyle(.soft)).disabled(media.track.prohibitsSkip == true).accessibilityLabel("Следующий трек")
            }.frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity)
    }
}
