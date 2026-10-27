import SwiftUI
import IslandCore

@MainActor
struct MusicView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var media: MediaService
    var now: Date
    @State private var seeking: Double?
    var body: some View {
        VStack(spacing: 14) {
            if let error = media.error {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform.badge.exclamationmark").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Повторить") { media.start() }.buttonStyle(IslandButtonStyle(.soft))
                }.padding(12).islandCard(tint: .orange)
            }
            Spacer(minLength: 0)
            if media.track.hasTrack {
                player
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LinearGradient(colors: [.purple.opacity(0.28), accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "music.note").font(.system(size: 38, weight: .light)).foregroundStyle(accent)
                    }.frame(width: 92, height: 92)
                    VStack(spacing: 7) {
                        Text("Включи любимую музыку").font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("Открой Яндекс Музыку и запусти трек.\nУправление появится здесь автоматически.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
                    }
                    Button { media.openYandexMusic() } label: { Label("Открыть Яндекс Музыку", systemImage: "play.fill") }
                        .buttonStyle(IslandButtonStyle(.filled))
                    Button("Открыть в браузере") { media.openMusicWebsite() }.buttonStyle(IslandButtonStyle(.soft))
                }.frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
