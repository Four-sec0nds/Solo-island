import AppKit
import Combine
import Darwin
import IslandCore

@MainActor
final class AgentService: ObservableObject {
    @Published private(set) var activity = AgentActivity()
    @Published private(set) var installed: Set<AgentProvider> = []
    @Published private(set) var observed: Set<AgentProvider> = []
    @Published private(set) var webConnections: [AgentProvider: String] = [:]
    @Published var message: String?
    private let mailbox: AgentMailbox
    private let instance = UUID()
    private var timer: Timer?
    private var seen = Set<UUID>()
    private var demo = false
    private let helper: URL
    private var webBrowsers: [AgentProvider: WebAgentBrowser] = [:]
    func openWeb(_ provider: AgentProvider) {
        if webBrowsers[provider] == nil { webBrowsers[provider] = WebAgentBrowser(provider: provider, agents: self) }
        webBrowsers[provider]?.present()
    }
    func webConnection(_ provider: AgentProvider, status: String) { webConnections[provider] = status }
    func receiveWeb(_ data: Data) {
        do {
            let web = try WebAgentEvent.decode(data)
            let event = try web.bridgeEvent(instance: instance, pid: ProcessInfo.processInfo.processIdentifier)
            try mailbox.write(event, to: mailbox.eventURL(event.id)); poll()
            webConnections[web.provider] = "Статусы поступают"
        } catch { message = "Веб-сеанс не передал поддерживаемый статус." }
    }
    func installBrowserBridge() {
        do {
            guard let binary = Bundle.main.url(forAuxiliaryExecutable: "SoloBridge"),
                  let resources = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension") else { return }
            let directory = helper.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(contentsOf: binary).write(to: helper, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            let extensionFolder = directory.appendingPathComponent("BrowserExtension")
            if FileManager.default.fileExists(atPath: extensionFolder.path) { try FileManager.default.removeItem(at: extensionFolder) }
            try FileManager.default.copyItem(at: resources, to: extensionFolder)
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            for browser in ["Google/Chrome", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Chromium"] {
                let folder = support.appendingPathComponent(browser + "/NativeMessagingHosts")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let manifest: [String: Any] = ["name": BrowserBridgeIdentity.host, "description": "Solo Island local agent activity",
                    "path": helper.path, "type": "stdio", "allowed_origins": [BrowserBridgeIdentity.origin]]
                let bytes = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                try bytes.write(to: folder.appendingPathComponent(BrowserBridgeIdentity.host + ".json"), options: .atomic)
            }
            NSWorkspace.shared.open(extensionFolder)
            message = "В chrome://extensions включите режим разработчика → Загрузить распакованное расширение → выберите открытую папку BrowserExtension. Затем обновите вкладки Claude/ChatGPT."
        } catch { message = "Не удалось подключить браузер: \(error.localizedDescription)" }
    }

    init(dataFolder: URL) {
        mailbox = AgentMailbox(root: dataFolder.appendingPathComponent("AgentBridge/runtime", isDirectory: true))
        helper = dataFolder.appendingPathComponent("AgentBridge/SoloBridge")
    }
    var pending: [AgentEvent] { activity.pending }
    private func configuration(_ provider: AgentProvider) -> URL {
        let variable = provider == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"
        let directory: URL
        if let override = ProcessInfo.processInfo.environment[variable], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(provider.configDirectory, isDirectory: true)
        }
        return directory.appendingPathComponent(provider.configFilename)
    }
    func start() {
        do {
            try mailbox.prepare()
            // The previous instance cannot authorise a request in this one.
            for folder in ["events", "replies"] {
                for file in try FileManager.default.contentsOfDirectory(at: mailbox.root.appendingPathComponent(folder), includingPropertiesForKeys: nil) {
                    if file.pathExtension == "json" { try? FileManager.default.removeItem(at: file) }
                }
            }
            refreshInstallation()
            poll()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        } catch { message = "Не удалось запустить подключение агентов: \(error.localizedDescription)" }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        // Waiting hooks see the missing heartbeat and return to native prompts.
        if (try? mailbox.read(AgentHeartbeat.self, from: mailbox.heartbeatURL))?.instance == instance {
            try? FileManager.default.removeItem(at: mailbox.heartbeatURL)
        }
        for request in pending {
            try? FileManager.default.removeItem(at: mailbox.eventURL(request.id))
            try? FileManager.default.removeItem(at: mailbox.replyURL(request.id))
        }
    }
    private func poll() {
        do {
            try mailbox.write(AgentHeartbeat(instance: instance, pid: ProcessInfo.processInfo.processIdentifier), to: mailbox.heartbeatURL)
            let files = try FileManager.default.contentsOfDirectory(at: mailbox.root.appendingPathComponent("events"), includingPropertiesForKeys: nil)
            let events = files.prefix(256).compactMap { file -> AgentEvent? in
                guard file.pathExtension == "json", let event = try? mailbox.read(AgentEvent.self, from: file),
                      event.instance == instance, event.date <= Date().addingTimeInterval(2) else { return nil }
                return event
            }.sorted { $0.date < $1.date }
            var next = activity
            var changed = false
            for event in events where !seen.contains(event.id) {
                if event.hook == .permission && !mailbox.isLive(event, instance: instance) { continue }
                next.ingest(event); seen.insert(event.id); if !event.isWeb { observed.insert(event.provider) }; changed = true
                if event.hook != .permission { try? FileManager.default.removeItem(at: mailbox.eventURL(event.id)) }
            }
            let previous = next.sessions
            next.expire(at: Date(), clientAlive: { $0 > 1 && kill($0, 0) == 0 }) { mailbox.isLive($0, instance: instance) }
            if changed || next.sessions != previous { activity = next }
            // IDs are only needed while their on-disk request exists.
            seen = Set(events.filter { $0.hook == .permission }.map(\.id))
        } catch { message = "Подключение агентов приостановлено: \(error.localizedDescription)" }
    }
    func respond(_ event: AgentEvent, decision: AgentDecision) {
        do {
            if !demo { try mailbox.respond(to: event, instance: instance, decision: decision) }
            var next = activity; next.resolved(event.id, at: Date(), inClient: decision == .client); activity = next
        } catch {
            message = "Запрос уже завершён. Проверьте подтверждение в самом клиенте."
            poll()
        }
    }
    func refreshInstallation() {
        guard !demo else { return }
        installed = Set(AgentProvider.allCases.filter {
            AgentHookConfiguration.isEnabled(try? Data(contentsOf: configuration($0)), provider: $0, helper: helper.path)
        })
    }
    func setEnabled(_ provider: AgentProvider, enabled: Bool) {
        do {
            let config = configuration(provider)
            let existing = FileManager.default.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
            let merged = try AgentHookConfiguration.merging(existing, provider: provider, helper: helper.path, enabled: enabled)
            try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if enabled {
                guard let bundled = Bundle.main.url(forAuxiliaryExecutable: "SoloBridge") else {
                    throw NSError(domain: "SoloIsland.Agents", code: 1, userInfo: [NSLocalizedDescriptionKey: "В сборке отсутствует SoloBridge."])
                }
                // Atomic replacement also works while an older hook is waiting.
                try Data(contentsOf: bundled).write(to: helper, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            }
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let existing {
                let backup = helper.deletingLastPathComponent().appendingPathComponent(provider.rawValue + "-config-" + UUID().uuidString + ".backup")
                try existing.write(to: backup, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            try merged.write(to: config, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
            refreshInstallation()
            message = enabled ? "\(provider.title): перезапустите клиент и начните новую задачу. Статус появится после первого события."
                              : "Подключение \(provider.title) удалено из настроек. Перезапустите клиент, чтобы отключить уже загруженные события."
        } catch { message = "Не удалось изменить подключение: \(error.localizedDescription)" }
    }
    /// Synthetic native captures never read or modify the user's agent config.
    func preview(_ events: [AgentEvent]) {
        guard CommandLine.arguments.contains("--render-preview") else { return }
        demo = true
        var next = AgentActivity(); events.forEach { next.ingest($0) }; activity = next
        observed = Set(events.map(\.provider))
    }
}
