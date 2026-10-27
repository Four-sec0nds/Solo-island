import SwiftUI
import IslandCore

@MainActor
struct MusicView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var media: MediaService
    var now: Date
    @State private var seeking: Double?
    var body: some View {
        VStack(spacing: 18) {
            if let error = media.error {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Медиаплеер недоступен", systemImage: "music.note")
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Переподключить") { media.start() }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .islandCard()
            }
            if media.track.hasTrack {
                HStack(spacing: 20) {
                    Button { media.openSource() } label: { CoverView(image: media.artwork, size: 100) }
                        .buttonStyle(.plain).help("Открыть плеер")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(media.sourceName.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(accent)
                        Text(media.track.title ?? "").font(.system(size: 21, weight: .semibold)).lineLimit(2)
                        Text(media.track.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        if let album = media.track.album, !album.isEmpty {
                            Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 10)
                if media.track.canSeek {
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { seeking ?? media.track.position(at: now, receivedAt: media.receivedAt) },
                                              set: { seeking = $0 }), in: 0...max(1, media.track.duration ?? 1), onEditingChanged: { editing in
                            if !editing, let value = seeking { media.seek(value); seeking = nil }
                        }).accessibilityLabel("Позиция воспроизведения")
                        HStack {
                            Text(IslandStore.clock(Int(seeking ?? media.track.position(at: now, receivedAt: media.receivedAt))))
                            Spacer()
                            Text(IslandStore.clock(Int(media.track.duration ?? 0)))
                        }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 28) {
                    Button { media.command(["previous-track"]) } label: { Image(systemName: "backward.fill").font(.system(size: 22)) }
                        .disabled(media.track.prohibitsSkip == true).accessibilityLabel("Предыдущий трек")
                    Button { media.command(["toggle-play-pause"]) } label: {
                        Image(systemName: media.track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26)).frame(width: 58, height: 58)
                            .foregroundStyle(.black).background(.white, in: Circle())
                    }.accessibilityLabel(media.track.isPlaying ? "Пауза" : "Воспроизвести")
                    Button { media.command(["next-track"]) } label: { Image(systemName: "forward.fill").font(.system(size: 22)) }
                        .disabled(media.track.prohibitsSkip == true).accessibilityLabel("Следующий трек")
                }.buttonStyle(.plain)
            } else if media.error == nil {
                EmptyState(icon: "waveform", title: "Включите музыку", detail: "Яндекс Музыка, приложения и браузеры — здесь появится активный системный плеер.")
            }
            Spacer(minLength: 0)
        }
    }
}
