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
    private var stream: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var buffer = Data()
    private var lastArtwork: String?
    private var generation = UUID()

    var executable: String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("MediaControl/bin/media-control").path
        return [bundled, "/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"].compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
    var sourceName: String {
        guard let id = track.applicationID else { return "Медиаплеер" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
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
                receivedAt = Date(); track = next
                if next.artworkData != lastArtwork {
                    lastArtwork = next.artworkData
                    artwork = next.artworkData.flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
                    artworkColor = artwork?.averageColor ?? .systemMint
                }
                error = nil
            } catch {
                self.error = "Не удалось прочитать данные плеера: \(error.localizedDescription)"
            }
        }
    }
    func command(_ arguments: [String]) {
        guard let executable else { return }
        Task {
            do {
                let result = try await ProcessRunner.run(executable, arguments)
                if result.status != 0 { error = result.error.isEmpty ? "Плеер не выполнил команду." : result.error }
            } catch { self.error = error.localizedDescription }
        }
    }
    func seek(_ seconds: Double) {
        command(["seek", String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds)])
    }
    func openSource() {
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
