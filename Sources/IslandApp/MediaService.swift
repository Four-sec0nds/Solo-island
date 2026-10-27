import AppKit
import Combine
import IslandCore

@MainActor
final class MediaService: ObservableObject {
    @Published var track = NowPlaying()
    @Published var receivedAt = Date()
    @Published var artwork: NSImage?
    @Published var artworkColor = NSColor.systemMint
    @Published var error: String?
    @Published private(set) var usingWeb = false
    var onOpenWeb: (() -> Void)?
    private weak var web: WebMusicService?
    private var subscriptions = Set<AnyCancellable>()
    private var nativeTrack = NowPlaying()
    private var webTrack = NowPlaying()
    private var nativeReceivedAt = Date()
    private var webReceivedAt = Date()
    private var webArtwork: NSImage?
    private var stream: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var buffer = Data()
    private var nativeArtwork: NSImage?
    private var nativeArtworkColor = NSColor.systemMint
    private var lastArtwork: String?
    private var generation = UUID()
    private var continuity = NowPlayingContinuity()
    private var emptyReset: Task<Void, Never>?

    var executable: String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("MediaControl/bin/media-control").path
        return [bundled, "/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"].compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
    var sourceName: String {
        if usingWeb, let provider = web?.provider { return provider.title }
        guard let id = track.applicationID else { return "Медиаплеер" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        if id.localizedCaseInsensitiveContains("yandex") { return "Яндекс Музыка" }
        return id
    }
    func attach(_ service: WebMusicService) {
        subscriptions.removeAll(); web = service
        service.$track.sink { [weak self] snapshot in
            guard let self else { return }
            self.webTrack = snapshot; self.webReceivedAt = Date(); self.updateVisible()
        }.store(in: &subscriptions)
        service.$artwork.sink { [weak self] image in
            guard let self else { return }; self.webArtwork = image
            if self.usingWeb { self.artwork = image; self.artworkColor = image?.averageColor ?? .systemMint }
        }.store(in: &subscriptions)
    }
    private func updateVisible() {
        usingWeb = webTrack.hasTrack && (webTrack.isPlaying || !nativeTrack.isPlaying)
        apply(usingWeb ? webTrack : nativeTrack, sampledAt: usingWeb ? webReceivedAt : nativeReceivedAt)
        if usingWeb { artwork = webArtwork; artworkColor = webArtwork?.averageColor ?? .systemMint }
    }
    private func receiveNative(_ snapshot: NowPlaying) {
        nativeTrack = snapshot; nativeReceivedAt = Date(); updateVisible()
    }
    func start() {
        stop()
        guard let executable else {
            error = "Медиамодуль отсутствует. Переустановите Solo Island из полного DMG."; return
        }
        error = nil
        let process = Process(), output = Pipe(), errors = Pipe()
        let token = UUID(); generation = token
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["stream", "--no-diff", "--debounce=150"]
        process.standardOutput = output; process.standardError = errors
        outputPipe = output; errorPipe = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.consume(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.error = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.error = "Медиамодуль остановлен (\(status)). Нажмите «Переподключить» в настройках."
            }
        }
        do { try process.run(); stream = process }
        catch { self.error = error.localizedDescription }
    }
    func stop() {
        generation = UUID()
        emptyReset?.cancel(); emptyReset = nil
        continuity = NowPlayingContinuity()
        stream?.terminationHandler = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        if stream?.isRunning == true { stream?.terminate() }
        stream = nil; buffer.removeAll()
    }
    private func consume(_ data: Data) {
        buffer.append(data)
        // A corrupt/unbounded helper must not exhaust app memory.
        guard buffer.count < 24 * 1024 * 1024 else {
            stop(); error = "Некорректный ответ медиамодуля. Переподключите его в настройках."; return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let next = try NowPlaying.decodeLine(Data(line))
                if let visible = continuity.receive(next, at: Date()) {
                    emptyReset?.cancel(); emptyReset = nil
                    receiveNative(visible)
                } else if emptyReset == nil {
                    let token = generation
                    emptyReset = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_050_000_000)
                        guard !Task.isCancelled, let self, self.generation == token else { return }
                        if let empty = self.continuity.expire(at: Date()) { self.receiveNative(empty) }
                        self.emptyReset = nil
                    }
                }
                error = nil
            } catch {
                self.error = "Не удалось прочитать данные плеера: \(error.localizedDescription)"
            }
        }
    }
    private func apply(_ next: NowPlaying, sampledAt: Date = Date()) {
        receivedAt = sampledAt; track = next
        if !usingWeb {
            if next.artworkData != lastArtwork {
                lastArtwork = next.artworkData
                nativeArtwork = next.artworkData.flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
                nativeArtworkColor = nativeArtwork?.averageColor ?? .systemMint
            }
            artwork = nativeArtwork; artworkColor = nativeArtworkColor
        }
    }

    func setPreview(_ snapshot: NowPlaying) { nativeTrack = snapshot; usingWeb = false; apply(snapshot) }
    func command(_ arguments: [String]) {
        if usingWeb, let action = arguments.first { web?.command(action); return }
        guard let executable else { return }
        Task {
            do {
                let result = try await ProcessRunner.run(executable, arguments)
                if result.status != 0 { error = result.error.isEmpty ? "Плеер не выполнил команду." : result.error }
            } catch { self.error = error.localizedDescription }
        }
    }
    func seek(_ seconds: Double) {
        if usingWeb { web?.command("seek", value: seconds); return }
        command(["seek", String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds)])
    }
    func openSource() {
        if usingWeb { onOpenWeb?(); return }
        guard let id = track.applicationID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

private extension NSImage {
    var averageColor: NSColor? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard let color = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return nil }
        let maxComponent = max(color.redComponent, color.greenComponent, color.blueComponent, 0.01)
        return NSColor(calibratedRed: min(1, color.redComponent / maxComponent * 0.8 + 0.15),
                       green: min(1, color.greenComponent / maxComponent * 0.8 + 0.15),
                       blue: min(1, color.blueComponent / maxComponent * 0.8 + 0.15), alpha: 1)
    }
}
