import AppKit
import Combine
import IslandCore
import UniformTypeIdentifiers

@MainActor
final class IslandStore: ObservableObject {
    @Published private(set) var state: IslandState
    @Published var now = Date()
    @Published var tab: IslandTab = .music
    @Published var cameraWidth: CGFloat = 160
    @Published var compactHeight: CGFloat = 37
    @Published var expanded = false
    @Published var pinned = false
    @Published var editingForm = false
    @Published var draggingFiles = false
    @Published var fullScreen = false
    @Published var error: String?
    @Published var toast: IslandToast?
    @Published var notificationsEnabled = false
    @Published var focusAutomationActive = false
    let media = MediaService()
    let notifications = NotificationService()
    private let repository: StateRepository
    private var canPersist = true
    private var timer: Timer?
    private var pasteboardCount = NSPasteboard.general.changeCount
    private var audio: AudioSnapshot?
    private var toastUntil = Date.distantPast
    private var tickCount = 0
    private var collapseTask: Task<Void, Never>?
    private var focusAutomationBusy = false

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoloIsland", isDirectory: true)
        repository = StateRepository(url: folder.appendingPathComponent("state.json"))
        var loadingError: String?
        do { state = try repository.load() }
        catch {
            state = IslandState(); canPersist = false
            loadingError = "Не удалось прочитать сохранённые данные. Исходный файл оставлен без изменений: \(error.localizedDescription)"
        }
        error = loadingError
        notifications.onAction = { [weak self] action, id in
            Task { @MainActor in self?.handleNotification(action, id: id) }
        }
        notifications.onError = { [weak self] message in
            Task { @MainActor in self?.error = "Уведомления: \(message)" }
        }
        notifications.center.getNotificationSettings { [weak self] settings in
            let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in self?.notificationsEnabled = enabled }
        }
        audio = AudioService.snapshot()
    }
    func start() {
        media.start()
        notifications.sync(tasks: state.tasks)
        notifications.scheduleFocus(state.focus, taskTitle: focusTask?.title ?? "Можно сделать перерыв")
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func stop() {
        timer?.invalidate(); media.stop(); save()
        // Focus reminders remain scheduled; no assumptions about a surviving process.
    }
    var focusTask: IslandTask? { state.tasks.first { $0.id == state.focus?.taskID } }
    var focusedTime: String {
        let remaining = Int(ceil(state.focus?.remaining(at: now) ?? 0))
        return Self.clock(remaining)
    }
    static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
    func save() {
        guard canPersist else { return }
        do { try repository.save(state) }
        catch { self.error = "Не удалось сохранить данные: \(error.localizedDescription)" }
    }
    private func tick() {
        now = Date(); tickCount += 1
        let isFullScreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        if isFullScreen != fullScreen {
            fullScreen = isFullScreen
            if isFullScreen { collapseTask?.cancel(); expanded = false }
        }
        if now >= toastUntil { toast = nil }
        if let focus = state.focus, !focus.isPaused, focus.remaining(at: now) <= 0 {
            creditFocus(); state.focus = nil; save()
            notify("Сессия завершена", symbol: "checkmark.circle.fill")
            stopFocusAutomation()
        }
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != pasteboardCount {
            pasteboardCount = pasteboard.changeCount
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                addFiles(urls, announce: false)
            }
        }
        if tickCount % 2 == 0, let next = AudioService.snapshot() {
            if let old = audio {
                if old.device != next.device || old.name != next.name {
                    notify(next.name, symbol: "headphones")
                } else if abs(old.volume - next.volume) > 0.009 || old.muted != next.muted {
                    let level = next.muted ? 0 : max(0, next.volume)
                    notify("Громкость \(Int(level * 100))%", symbol: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", progress: Double(level))
                }
            }
            audio = next
        }
    }
    func notify(_ message: String, symbol: String, progress: Double? = nil) {
        toast = IslandToast(message: message, symbol: symbol, progress: progress)
        toastUntil = Date().addingTimeInterval(3)
    }
    func hover(_ inside: Bool) {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(nanoseconds: inside ? 180_000_000 : 550_000_000)
            guard !Task.isCancelled else { return }
            if inside { expanded = true }
            else if (!pinned || fullScreen) && !editingForm && !draggingFiles && NSApp.modalWindow == nil { expanded = false }
        }
    }
    func reveal(_ target: IslandTab? = nil) {
        collapseTask?.cancel(); expanded = true
        if let target { tab = target }
    }
    func dismiss() { pinned = false; expanded = false }
    func setSettings(_ transform: (inout IslandSettings) -> Void) {
        transform(&state.settings); save()
    }
    func upsertTask(_ task: IslandTask) {
        let clean = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var task = task; task.title = clean
        if let index = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[index] = task }
        else { state.tasks.insert(task, at: 0) }
        save(); notifications.sync(tasks: state.tasks)
    }
    func completeTask(_ id: UUID) {
        guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        if state.focus?.taskID == id { endFocus() }
        state.tasks[index].completedAt = state.tasks[index].isCompleted ? nil : Date()
        save(); notifications.sync(tasks: state.tasks)
    }
    func deleteTask(_ id: UUID) {
        if state.focus?.taskID == id { endFocus() }
        state.tasks.removeAll { $0.id == id }; save(); notifications.sync(tasks: state.tasks)
    }
    func startFocus(taskID: UUID) {
        guard state.tasks.contains(where: { $0.id == taskID && !$0.isCompleted }) else { return }
        guard state.focus == nil else {
            if state.focus?.taskID == taskID { reveal(.focus) }
            else { error = "Сначала завершите текущую фокус-сессию." }
            return
        }
        state.focus = FocusSession(taskID: taskID, minutes: state.settings.focusMinutes)
        now = Date(); save(); reveal(.focus)
        notifications.scheduleFocus(state.focus, taskTitle: focusTask?.title ?? "")
    }
    func toggleFocusPause() {
        guard var focus = state.focus else { return }
        if focus.isPaused { focus.resume(at: Date()) } else { focus.pause(at: Date()) }
        state.focus = focus; creditFocus(); save()
        notifications.scheduleFocus(state.focus, taskTitle: focusTask?.title ?? "")
    }
    private func creditFocus() {
        guard var focus = state.focus else { return }
        let credit = focus.uncreditedSeconds(at: Date())
        if let index = state.tasks.firstIndex(where: { $0.id == focus.taskID }) {
            state.tasks[index].focusedSeconds += credit
        }
        state.focus = focus
    }
    func endFocus(completeTask: Bool = false) {
        let id = state.focus?.taskID
        creditFocus(); state.focus = nil
        if completeTask, let index = state.tasks.firstIndex(where: { $0.id == id }) {
            state.tasks[index].completedAt = Date()
        }
        save(); notifications.scheduleFocus(nil, taskTitle: ""); notifications.sync(tasks: state.tasks)
        stopFocusAutomation()
    }
    func addFiles(_ urls: [URL], announce: Bool = true) {
        let files = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        state.shelf = ShelfHistory.adding(files, to: state.shelf); save()
        if announce { notify("Добавлено: \(files.count)", symbol: "tray.and.arrow.down.fill") }
    }
    func removeFile(_ id: UUID) { state.shelf.removeAll { $0.id == id }; save() }
    func openFile(_ entry: ShelfEntry) {
        guard FileManager.default.fileExists(atPath: entry.path) else {
            error = "Файл перемещён или удалён. Добавьте его на полку заново."; return
        }
        if !NSWorkspace.shared.open(entry.url) { error = "Не удалось открыть файл." }
    }
    func pickFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }
    func addAction(_ action: QuickAction) { state.actions.append(action); save() }
    func removeAction(_ id: UUID) { state.actions.removeAll { $0.id == id }; save() }
    func runAction(_ action: QuickAction) {
        if action.kind == .shortcut { runShortcut(action.target); return }
        let url = URL(fileURLWithPath: action.target)
        guard FileManager.default.fileExists(atPath: url.path) else { error = "Объект перемещён или удалён."; return }
        if !NSWorkspace.shared.open(url) { error = "Не удалось открыть \(action.title)." }
    }
    func runShortcut(_ name: String, completion: ((Bool) -> Void)? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { error = "Укажите имя команды в настройках."; completion?(false); return }
        Task {
            do {
                let result = try await ProcessRunner.run("/usr/bin/shortcuts", ["run", clean])
                if result.status != 0 { error = "Быстрая команда: \(result.error)" }
                completion?(result.status == 0)
            } catch { self.error = error.localizedDescription; completion?(false) }
        }
    }
    func toggleFocusAutomation() {
        guard !focusAutomationBusy else { return }
        if focusAutomationActive { stopFocusAutomation(); return }
        guard !state.settings.endFocusShortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Сначала укажите команду выключения «Не беспокоить» в настройках."; return
        }
        focusAutomationBusy = true
        runShortcut(state.settings.focusShortcut) { [weak self] success in
            self?.focusAutomationBusy = false; self?.focusAutomationActive = success
            if success, self?.state.focus == nil { self?.stopFocusAutomation() }
        }
    }
    private func stopFocusAutomation() {
        guard focusAutomationActive, !focusAutomationBusy else { return }
        focusAutomationBusy = true
        runShortcut(state.settings.endFocusShortcut) { [weak self] success in
            self?.focusAutomationBusy = false
            if success { self?.focusAutomationActive = false }
        }
    }
    func enableNotifications() {
        Task {
            notificationsEnabled = await notifications.requestPermission()
            if notificationsEnabled {
                notifications.sync(tasks: state.tasks)
                notifications.scheduleFocus(state.focus, taskTitle: focusTask?.title ?? "")
            } else { error = "Разрешите уведомления Solo Island в настройках macOS → Уведомления." }
        }
    }
    private func handleNotification(_ action: String, id: UUID) {
        switch action {
        case "COMPLETE": completeTask(id)
        case "SNOOZE":
            if var task = state.tasks.first(where: { $0.id == id }) {
                task.reminderAt = Date().addingTimeInterval(600); upsertTask(task)
            }
        case "START": startFocus(taskID: id)
        default: reveal(.tasks)
        }
    }
}

enum IslandTab: String, CaseIterable, Identifiable {
    case music = "Музыка", tasks = "Задачи", focus = "Фокус", files = "Файлы", actions = "Действия", settings = "Настройки"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .music: return "music.note"
        case .tasks: return "checklist"
        case .focus: return "timer"
        case .files: return "tray.full"
        case .actions: return "bolt.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}
struct IslandToast { var message: String; var symbol: String; var progress: Double? }
