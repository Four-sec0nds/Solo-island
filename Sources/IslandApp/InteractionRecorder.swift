import AppKit
import IslandCore
import CryptoKit
import SwiftUI

@MainActor
enum RecordingTargets { static var frames: [String: CGRect] = [:] }

@MainActor
private struct RecordingTargetModifier: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        if CommandLine.arguments.contains("--render-preview") {
            content.background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { RecordingTargets.frames[key] = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, rect in RecordingTargets.frames[key] = rect }
                        .onChange(of: key) { old, next in
                            RecordingTargets.frames.removeValue(forKey: old)
                            RecordingTargets.frames[next] = geometry.frame(in: .global)
                        }
                        .onDisappear { RecordingTargets.frames.removeValue(forKey: key) }
                }.allowsHitTesting(false)
            }
        } else { content }
    }
}
extension View {
    @MainActor func recordingTarget(_ key: String) -> some View { modifier(RecordingTargetModifier(key: key)) }
}

/// Offline native footage. Local events go to our own window; no accessibility,
/// screen-recording permission, personal session or external music site is used.
@MainActor
final class InteractionRecorder {
    struct Sample: Encodable {
        let file: String
        let x: Double
        let y: Double
        let pressed: Bool
        let width: Double
        let height: Double
    }
    struct Event: Encodable { let frame: Int; let kind: String; let label: String }
    struct Clip: Encodable {
        let name: String
        let fps: Int
        let frames: [Sample]
        let events: [Event]
    }
    private let folder: URL
    private let store: IslandStore
    private let controller: IslandWindowController
    private var window: NSWindow { controller.window! }
    private var name = ""
    private var frames: [Sample] = []
    private var events: [Event] = []
    private var clips: [Clip] = []
    private var pointer = NSPoint(x: 680, y: 510)
    private var pressed = false
    private var eventNumber = 0
    private var sliderValues: [String: [Double]] = [:]
    private var cachedFrames: [String: String] = [:]

    static func record(in output: URL) async throws {
        guard CommandLine.arguments.contains("--render-preview") else { return }
        let recorder = try InteractionRecorder(folder: output)
        try await recorder.run()
    }

    private init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var fixture = IslandState()
        let titles = ["Собрать идеи для проекта", "Продумать главную страницу", "Подготовить прототип",
                      "Согласовать иллюстрации", "Проверить адаптивность", "Настроить сервер",
                      "Провести ревью", "Отправить готовые материалы", "Обновить портфолио", "Оставить время для себя"]
        fixture.tasks = titles.enumerated().map { index, title in
            IslandTask(title: title, dueAt: index < 8 ? nil : Date().addingTimeInterval(86400 * 3),
                       completedAt: index == 9 ? Date() : nil)
        }
        fixture.settings.musicProvider = .yandex; fixture.settings.musicOnboardingComplete = false
        fixture.settings.animationDuration = 0.32
        let apps = [("Finder", "/System/Library/CoreServices/Finder.app"), ("Заметки", "/System/Applications/Notes.app"),
                    ("Календарь", "/System/Applications/Calendar.app"), ("Напоминания", "/System/Applications/Reminders.app"),
                    ("Калькулятор", "/System/Applications/Calculator.app"), ("Терминал", "/System/Applications/Utilities/Terminal.app"),
                    ("Быстрые команды", "/System/Applications/Shortcuts.app"), ("Просмотр", "/System/Applications/Preview.app"),
                    ("Настройки", "/System/Applications/System Settings.app")]
        fixture.actions = apps.map { QuickAction(title: $0.0, kind: .application, target: $0.1) }
        let dataFolder = folder.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        let brief = dataFolder.appendingPathComponent("План проекта.txt")
        try "Идея → прототип → готовый проект".write(to: brief, atomically: true, encoding: .utf8)
        let imageURL = dataFolder.appendingPathComponent("Дизайн.png")
        let image = NSImage(size: NSSize(width: 180, height: 120))
        image.lockFocus()
        NSColor(calibratedRed: 0.2, green: 0.12, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 180, height: 120)).fill()
        NSColor.systemMint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 25, y: 30, width: 130, height: 60), xRadius: 20, yRadius: 20).fill()
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: imageURL) }
        fixture.shelf = (0..<12).map { index in
            if index % 3 == 0 { return ShelfEntry(path: imageURL.path, kind: .image, isPinned: true) }
            if index % 3 == 1 { return ShelfEntry(path: brief.path) }
            return ShelfEntry(kind: .text, text: "Идея \(index / 3 + 1). Сделать интерфейс спокойнее и оставить больше воздуха.\n" + String(repeating: "Задачи, музыка и важные материалы всегда рядом.\n", count: 12))
        }
        // Every fixture entry needs its own ID, even when it points at one demo asset.
        try StateRepository(url: dataFolder.appendingPathComponent("state.json")).save(fixture)
        store = IslandStore(dataFolder: dataFolder)
        store.notificationsEnabled = true; store.pinned = true
        controller = IslandWindowController(store: store, trackPointer: false, reducedMotionOverride: false)
        store.reveal()
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
    }

    private func begin(_ value: String) throws {
        fputs("Native validation phase: \(value)\n", stderr)
        if !frames.isEmpty { clips.append(Clip(name: name, fps: 20, frames: frames, events: events)) }
        name = value; frames = []; events = []
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    private func capture(_ count: Int = 1) async throws {
        for _ in 0..<count {
            try await Task.sleep(nanoseconds: 35_000_000)
            guard let source = PreviewRecorder.snapshot(window)?.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let w = Int(window.frame.width.rounded()), h = Int(window.frame.height.rounded())
            guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let cg = context.makeImage(), let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let path: String
            if let previous = cachedFrames[digest] { path = previous }
            else {
                path = String(format: "%@/%04d.png", name, frames.count)
                try data.write(to: folder.appendingPathComponent(path)); cachedFrames[digest] = path
            }
            frames.append(Sample(file: path, x: pointer.x, y: pointer.y, pressed: pressed,
                                 width: window.frame.width, height: window.frame.height))
        }
    }
    private func move(to target: NSPoint, count: Int = 6) async throws {
        let origin = pointer
        for step in 1...count {
            let t = Double(step) / Double(count), p = t * t * (3 - 2 * t)
            pointer = NSPoint(x: origin.x + (target.x - origin.x) * p, y: origin.y + (target.y - origin.y) * p)
            try await capture()
        }
    }
    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, queued: Bool = false) {
        eventNumber += 1
        if let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x, y: window.frame.height - point.y),
                                         modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                                         clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
            if queued { NSApp.postEvent(event, atStart: false) }
            else { window.sendEvent(event) }
        }
    }
    private func press(_ query: String, fallback: NSPoint, after: () -> Void = {}) async throws {
        fputs("Native input: click \(query)\n", stderr)
        let deadline = inputDeadline("click " + query)
        defer { deadline.cancel() }
        guard let rect = RecordingTargets.frames[query], rect.width > 2, rect.height > 2 else {
            throw failure("Interactive control is not laid out: " + query)
        }
        let point = NSPoint(x: query.hasPrefix("Алерт:") ? rect.maxX - 18 : rect.midX, y: rect.midY)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await move(to: point)
        events.append(Event(frame: frames.count, kind: "click", label: query))
        try PreviewRecorder.png(window, to: folder.deletingLastPathComponent().appendingPathComponent("SoloIsland-interaction-debug.png"))
        // NSApplication owns event dispatch and synchronous tracking. Enqueue
        // down and up in normal order so currentEvent and release both exist.
        pressed = true
        mouse(.leftMouseDown, at: point, queued: true)
        mouse(.leftMouseUp, at: point, queued: true)
        try await capture(2)
        pressed = false; after(); try await capture(5)
    }
    private func inputDeadline(_ label: String, seconds: Double = 20) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler {
            fputs("Native input timed out: \(label)\n", stderr)
            exit(1)
        }
        timer.resume()
        return timer
    }
    private func tab(_ target: IslandTab) async throws {
        let index = IslandTab.allCases.firstIndex(of: target)!
        try await press("Вкладка:" + target.rawValue, fallback: NSPoint(x: 75, y: 170 + index * 48))
        guard store.tab == target else { throw failure("Tab did not change to \(target.rawValue)") }
    }
    private func failure(_ reason: String) -> NSError {
        fputs("Interaction recording: \(reason)\n", stderr)
        try? PreviewRecorder.png(window, to: folder.deletingLastPathComponent().appendingPathComponent("SoloIsland-interaction-debug.png"))
        for (key,rect) in RecordingTargets.frames.sorted(by: { $0.key < $1.key }) { fputs("TARGET \(key) \(rect)\n", stderr) }
        return NSError(domain: "SoloIsland.Interactions", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }
    private func scrollViews(_ root: NSView) -> [NSScrollView] {
        (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap(scrollViews)
    }
    private func scroll(to fraction: Double, steps: Int = 14) async throws {
        guard let view = window.contentView,
              let scroll = scrollViews(view).filter({ !$0.isHidden && $0.bounds.height > 70 }).max(by: { $0.bounds.height < $1.bounds.height }),
              let document = scroll.documentView else { throw failure("No native scroll view in \(name)") }
        let origin = scroll.contentView.bounds.origin
        let maxY = max(0, document.bounds.height - scroll.contentView.bounds.height)
        let target = maxY * fraction
        let bounds = scroll.convert(scroll.bounds, to: nil)
        try await move(to: NSPoint(x: bounds.midX, y: window.frame.height - bounds.midY), count: 3)
        events.append(Event(frame: frames.count, kind: "scroll", label: name))
        for step in 1...steps {
            let t = Double(step) / Double(steps), p = t * t * (3 - 2 * t)
            scroll.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + (target - origin.y) * p))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await capture()
        }
        guard maxY > 1 else { throw failure("Fixture does not overflow in \(name)") }
    }
    private func drag(_ label: String, fractions: [Double], fallback: NSRect) async throws {
        fputs("Native input: drag \(label)\n", stderr)
        let deadline = inputDeadline("drag " + label)
        defer { deadline.cancel() }
        guard RecordingTargets.frames[label] != nil else { throw failure("Slider is not laid out: " + label) }
        let initial = RecordingTargets.frames[label] ?? fallback
        try await move(to: NSPoint(x: initial.minX + 6 + (initial.width - 12) * fractions[0], y: initial.midY))
        events.append(Event(frame: frames.count, kind: "drag", label: label))
        pressed = true; mouse(.leftMouseDown, at: pointer, queued: true)
        for (start, end) in zip(fractions, fractions.dropFirst()) {
            for step in 1...14 {
                let rect = RecordingTargets.frames[label] ?? initial
                let t = Double(step) / 14, p = t * t * (3 - 2 * t)
                pointer = NSPoint(x: rect.minX + 6 + (rect.width - 12) * (start + (end - start) * p), y: rect.midY)
                mouse(.leftMouseDragged, at: pointer, queued: true); try await capture()
                let value: Double?
                switch label {
                case "Ширина": value = store.state.settings.expandedWidth
                case "Скругление": value = store.state.settings.cornerRadius
                case "Скорость анимации": value = store.state.settings.animationDuration
                default: value = nil
                }
                if let value { sliderValues[label, default: []].append(value) }
            }
        }
        pressed = false; mouse(.leftMouseUp, at: pointer, queued: true); try await capture(5)
    }
    private func type(_ value: String, field: String, at point: NSPoint) async throws {
        fputs("Native input: type \(field)\n", stderr)
        let deadline = inputDeadline("type " + field)
        defer { deadline.cancel() }
        guard let target = RecordingTargets.frames[field] else { throw failure("Text field is not visible: " + field) }
        try await press(field, fallback: NSPoint(x: target.midX, y: target.midY))
        if !(window.firstResponder is NSTextView), let root = window.contentView {
            let point = NSPoint(x: target.midX, y: window.frame.height - target.midY)
            func fieldView(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable,
                   field.convert(field.bounds, to: nil).contains(point) { return field }
                return view.subviews.lazy.compactMap(fieldView).first
            }
            if let field = fieldView(root) { window.makeFirstResponder(field) }
        }
        guard let editor = window.firstResponder as? NSTextView else { throw failure("Text field did not acquire its native editor: " + field) }
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        events.append(Event(frame: frames.count, kind: "type", label: value))
        editor.insertText(value, replacementRange: editor.selectedRange())
        try await capture(4)
        guard window.makeFirstResponder(nil) else { throw failure("Text field refused to commit: " + field) }
        try await capture(2)
    }

    private func run() async throws {
        let deadline = inputDeadline("complete interaction validation", seconds: 480)
        defer { deadline.cancel() }
        defer { store.webMusic.stop(); controller.close() }
        try await Task.sleep(nanoseconds: 900_000_000)
        store.webMusic.loadPreviewFixture(duration: 228)
        for _ in 0..<100 {
            if store.media.usingWeb && store.media.track.hasTrack { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard store.media.usingWeb else { throw failure("Offline music fixture did not load") }
        store.notificationsEnabled = true

        try begin("onboarding"); try await capture(10)
        try await press("Яндекс Музыка", fallback: NSPoint(x: 290, y: 213))
        try await capture(12)
        try await press("К плееру", fallback: NSPoint(x: 640, y: 143)); try await capture(8)
        guard store.state.settings.musicOnboardingComplete else { throw failure("Provider selection did not finish onboarding") }

        try begin("music"); try await capture(8)
        try await press("Воспроизвести", fallback: NSPoint(x: 435, y: 480)); try await capture(6)
        try await drag("Позиция воспроизведения", fractions: [0.05,0.72,0.36], fallback: NSRect(x: 280, y: 422, width: 310, height: 22))
        try await press("Следующий трек", fallback: NSPoint(x: 520, y: 480)); try await capture(12)
        guard store.media.track.title == "Следующий веб-трек" else { throw failure("Native next button did not reach the web player") }
        try await press("Предыдущий трек", fallback: NSPoint(x: 350, y: 480))
        try await press("Пауза", fallback: NSPoint(x: 435, y: 480)); try await capture(10)

        try begin("tasks"); try await tab(.tasks); try await capture(8)
        try await scroll(to: 1); try await scroll(to: 0)
        try await press("Завершить:Собрать идеи для проекта", fallback: NSPoint(x: 200,y: 250))
        guard store.state.tasks.first?.isCompleted == true else { throw failure("Task completion button did not complete the task") }
        try await press("Выполненные", fallback: NSPoint(x: 610,y: 143)); try await capture(8)
        try await press("Предстоящие", fallback: NSPoint(x: 435,y: 143)); try await capture(8)
        try await press("Сегодня", fallback: NSPoint(x: 260,y: 143)); try await capture(5)

        try begin("deadline")
        try await press("Добавить срок и напоминание", fallback: NSPoint(x: 660,y: 198))
        guard store.taskDraft != nil else { throw failure("Deadline editor did not open from its button") }
        try await type("Подготовить новый проект", field: "Название задачи", at: NSPoint(x: 330,y:145))
        try await press("Алерт:срок", fallback: NSPoint(x: 680,y: 235))
        try await capture(8)
        try await drag("Через сколько дней выполнить задачу", fractions: [1.0/14,0.85,0.36], fallback: NSRect(x: 186,y: 293,width: 496,height: 22))
        for _ in 0..<2 {
            try await press("Алерт:день", fallback: NSPoint(x: 665,y: 436))
            try await press("Алерт:час", fallback: NSPoint(x: 665,y: 465))
        }
        try await press("Своя дата", fallback: NSPoint(x: 645,y: 348))
        try await scroll(to: 1); try await scroll(to: 0); try await capture(5)

        try begin("reminder")
        try await press("Напоминание", fallback: NSPoint(x: 565,y: 194))
        try await press("Алерт:напоминание", fallback: NSPoint(x: 680,y: 235))
        try await press("Календарь:вперёд", fallback: NSPoint(x: 685,y: 273)); try await capture(7)
        try await press("Календарь:назад", fallback: NSPoint(x: 185,y: 273)); try await capture(7)
        let futureDay = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let futureLabel = futureDay.formatted(date: .complete, time: .omitted)
        // At month end the future date is not a cell in the current month.
        // Navigate explicitly instead of silently clicking a fallback position.
        if RecordingTargets.frames[futureLabel] == nil {
            try await press("Календарь:вперёд", fallback: NSPoint(x: 685,y: 273)); try await capture(7)
        }
        guard RecordingTargets.frames[futureLabel] != nil else { throw failure("Future reminder day is not visible in the calendar") }
        try await press(futureLabel, fallback: NSPoint(x: 575,y: 400)); try await capture(8)
        try await press("Сохранить задачу", fallback: NSPoint(x: 675,y: 145)); try await capture(8)
        guard store.taskDraft == nil,
              let saved = store.state.tasks.first(where: { $0.title == "Подготовить новый проект" }),
              let reminder = saved.reminderAt,
              Calendar.current.isDate(reminder, inSameDayAs: futureDay) else {
            throw failure("Reminder form did not save its chosen future date")
        }

        try begin("custom-focus"); try await tab(.focus)
        try await scroll(to: 1); try await scroll(to: 0)
        try await press("45 мин", fallback: NSPoint(x: 390,y: 175))
        try await press("Своё", fallback: NSPoint(x: 655,y: 175))
        try await type("1", field: "Часы", at: NSPoint(x: 270,y: 258))
        try await type("30", field: "Минуты", at: NSPoint(x: 570,y: 258))
        guard store.state.settings.focusDuration == 5400 else { throw failure("Hour/minute fields did not commit the custom duration") }
        try await press("Продумать главную страницу", fallback: NSPoint(x: 420,y: 398)); try await capture(8)
        guard store.state.focus != nil else { throw failure("Focus session did not start from the task list") }

        try begin("focus")
        let start = Date(); var focus = FocusSession(taskID: store.state.focus!.taskID, minutes: 90, now: start)
        var logical: TimeInterval = 0
        for step in 0..<64 {
            let date = start.addingTimeInterval(logical)
            if step == 20 {
                try await press("Пауза", fallback: NSPoint(x: 336,y: 335), after: { focus.pause(at: date); self.store.previewFocus(focus, at: date) })
            }
            if step == 36 {
                try await press("Продолжить", fallback: NSPoint(x: 330,y: 335), after: { focus.resume(at: date); self.store.previewFocus(focus, at: date) })
            }
            store.previewFocus(focus, at: date); try await capture()
            logical += 45
        }
        store.endFocus()

        try begin("files"); try await tab(.files)
        try await scroll(to: 1); try await scroll(to: 0)
        for (label,x) in [("Файлы",370.0),("Текст",500.0),("Скрины",630.0),("Всё",240.0)] {
            try await press(label, fallback: NSPoint(x:x,y:196)); try await capture(6)
        }
        try await press("Закрепить:" + store.state.shelf[1].id.uuidString, fallback: NSPoint(x:675,y:357))
        try await press("Копировать:" + store.state.shelf[0].id.uuidString, fallback: NSPoint(x:675,y:245)); try await capture(8)

        try begin("actions"); try await tab(.actions)
        try await scroll(to: 1); try await scroll(to: 0)
        try await press("Finder", fallback: NSPoint(x:250,y:228)); try await capture(8)
        window.makeKeyAndOrderFront(nil)
        try await press("Добавить действие", fallback: NSPoint(x:675,y:135)); try await capture(8)
        try await press("Папка", fallback: NSPoint(x:435,y:230)); try await capture(6)
        try await press("Быстрая команда", fallback: NSPoint(x:610,y:230)); try await capture(6)
        try await press("Отмена", fallback: NSPoint(x:215,y:499)); try await capture(6)

        try begin("settings"); try await tab(.settings)
        guard PreviewRecorder.revealControl("Ширина", in: window) else { throw failure("Appearance controls were not found") }
        events.append(Event(frame: frames.count, kind: "scroll", label: name)); try await capture(8)
        let before = store.state.settings
        try await drag("Ширина", fractions: [(720.0-640)/260,0.65,0.18,(720.0-640)/260], fallback: NSRect(x:180,y:240,width:510,height:22))
        guard let widths = sliderValues["Ширина"], (widths.max()! - widths.min()!) > 100,
              abs(store.state.settings.expandedWidth - before.expandedWidth) < 12 else { throw failure("Native width slider did not move and return to its initial value") }
        try await drag("Скругление", fractions: [(before.cornerRadius-22)/18,1,0,0.44], fallback: NSRect(x:180,y:295,width:510,height:22))
        try await drag("Скорость анимации", fractions: [(before.animationDuration-0.12)/0.48,1,0,0.42], fallback: NSRect(x:180,y:350,width:510,height:22))
        guard let radii = sliderValues["Скругление"], radii.max()! - radii.min()! > 10,
              let speeds = sliderValues["Скорость анимации"], speeds.max()! - speeds.min()! > 0.3 else { throw failure("Native appearance sliders did not change settings") }
        guard PreviewRecorder.revealControl("Алерт:акцент", in: window, topMargin: 75) else { throw failure("Accent control was not found") }
        events.append(Event(frame: frames.count, kind: "scroll", label: name)); try await capture(8)
        if store.state.settings.coverAccent { try await press("Алерт:акцент", fallback: NSPoint(x:680,y:230)) }
        try await press("Фиолетовый", fallback: NSPoint(x:510,y:270)); try await capture(6)
        try await press("Мятный", fallback: NSPoint(x:230,y:270)); try await capture(6)
        try await scroll(to: 1); try await scroll(to: 0)
        store.setSettings { $0.expandedWidth = 720; $0.cornerRadius = 30; $0.animationDuration = 0.32; $0.accent = "mint" }
        try await capture(8)
        try await press("Закреплено", fallback: NSPoint(x: 640,y: 70))

        clips.append(Clip(name: name, fps: 20, frames: frames, events: events))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(clips).write(to: folder.appendingPathComponent("manifest.json"))
        try encoder.encode(sliderValues).write(to: folder.appendingPathComponent("slider-values.json"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("fixture"))
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent().appendingPathComponent("SoloIsland-interaction-debug.png"))
        fputs("Interactive native footage: \(clips.count) clips, \(clips.reduce(0) { $0 + $1.frames.count }) frames; music, all five sliders, calendars, lists, focus and buttons recorded\n", stderr)
    }
}
