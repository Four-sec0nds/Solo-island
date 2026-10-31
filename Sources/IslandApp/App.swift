import AppKit
import SwiftUI
import Combine
import IslandCore
import QuartzCore

@main
struct SoloIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: IslandStore!
    private var island: IslandWindowController!
    private var status: NSStatusItem!
    private var previewFolder: URL?
    private var previewQuitResult: URL?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > flag + 1 {
            renderPreview(at: URL(fileURLWithPath: CommandLine.arguments[flag + 1])); return
        }
        store = IslandStore()
        island = IslandWindowController(store: store)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Solo Island")
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть Solo Island", action: #selector(showIsland), keyEquivalent: "")
        menu.addItem(withTitle: "Настройки", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Папка с данными", action: #selector(showData), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить Solo Island", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        store.start()
    }
    @objc private func showIsland() { store.reveal(); island.window?.makeKey(); NSApp.activate(ignoringOtherApps: true) }
    @objc private func showSettings() { store.reveal(.settings); island.window?.makeKey(); NSApp.activate(ignoringOtherApps: true) }
    @objc private func showData() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoloIsland")
        NSWorkspace.shared.open(folder)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.focusAutomationActive {
            let alert = NSAlert()
            alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 5)
            alert.messageText = "Режим «Не беспокоить» включён через Solo Island"
            alert.informativeText = "Отключите его в разделе «Фокус» перед выходом или выключите вручную в Пункте управления."
            alert.addButton(withTitle: "Вернуться к фокусу"); alert.addButton(withTitle: "Выйти")
            if alert.runModal() == .alertFirstButtonReturn { store.reveal(.focus); return .terminateCancel }
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let previewFolder { try? FileManager.default.removeItem(at: previewFolder) }
        else { store.stop() }
        if let previewQuitResult {
            try? Data("{\"native_quit_button\":true}\n".utf8).write(to: previewQuitResult, options: .atomic)
            fputs("Quit button: native click terminated Solo Island through its application lifecycle\n", stderr)
        }
    }
    private func renderPreview(at output: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("solo-preview-" + UUID().uuidString)
        previewFolder = folder
        var fixture = IslandState()
        let titles = ["Собрать идеи для нового проекта", "Продумать главную страницу", "Отправить готовые материалы", "Оставить время для себя"]
        fixture.tasks = titles.enumerated().map { index, title in
            IslandTask(title: title, dueAt: Date().addingTimeInterval(Double(index + 1) * 1800))
        }
        fixture.shelf = [ShelfEntry(kind: .text, text: "Здесь остаются идеи, ссылки и всё, к чему хочется вернуться.")]
        fixture.settings.animationDuration = 0.32
        fixture.settings.musicOnboardingComplete = true
        fixture.settings.musicProvider = .yandex
        fixture.actions = [
            QuickAction(title: "Finder", kind: .application, target: "/System/Library/CoreServices/Finder.app"),
            QuickAction(title: "Заметки", kind: .application, target: "/System/Applications/Notes.app"),
            QuickAction(title: "Быстрые команды", kind: .application, target: "/System/Applications/Shortcuts.app")
        ]
        do { try StateRepository(url: folder.appendingPathComponent("state.json")).save(fixture) }
        catch { fputs("Preview fixture: \(error.localizedDescription)\n", stderr); exit(1) }
        store = IslandStore(dataFolder: folder)
        store.notificationsEnabled = true
        var previewTrack = NowPlaying()
        previewTrack.bundleIdentifier = "ru.yandex.desktop.music"; previewTrack.title = "Любимый трек"
        previewTrack.artist = "Твоя музыка · предпросмотр"; previewTrack.duration = 228
        previewTrack.elapsedTime = 78; previewTrack.playing = true
        store.media.setPreview(previewTrack)
        island = IslandWindowController(store: store, trackPointer: false, reducedMotionOverride: false)
        Task { @MainActor [self] in
            guard let window = island.window, !window.isVisible,
                  window.level.rawValue > NSWindow.Level.mainMenu.rawValue,
                  (window as? NSPanel)?.isFloatingPanel == true, let screen = NSScreen.screens.first else {
                fputs("Hidden overlay window precondition failed\n", stderr); exit(1)
            }
            let canvas = NSSize(width: store.presentationWidth, height: store.presentationHeight)
            var frames: [PreviewRecorder.Frame] = []
            var openingWidths = Set<Int>()
            @MainActor func record(_ delay: Double) {
                if let image = PreviewRecorder.animationFrame(window, canvas: canvas, neckWidth: store.cameraWidth, neckHeight: store.compactHeight) {
                    frames.append(.init(image: image, delay: delay))
                }
            }
            record(0.5)
            island.checkPointer(at: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 4))
            for _ in 0..<22 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                if window.isVisible { openingWidths.insert(Int(window.frame.width)) }
                record(0.03)
            }
            guard openingWidths.count >= 3 else { fputs("Notch motion skipped intermediate widths: \(openingWidths.sorted()), min=\(window.minSize), frame=\(window.frame)\n", stderr); exit(1) }
            guard store.expanded, window.isVisible, abs(window.frame.maxY - screen.frame.maxY) < 1 else {
                fputs("Notch reveal/attachment failed\n", stderr); exit(1)
            }
            if !frames.isEmpty { frames[frames.count - 1].delay = 0.9 }
            // Raise another window after the island. Ordering must remain above it
            // without requiring a pin, including after pinning and unpinning.
            let other = NSWindow(contentRect: window.frame.insetBy(dx: 40, dy: 40),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false; other.level = .floating
            @MainActor func verifyOverlay(_ phase: String) async {
                other.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 80_000_000)
                let order = NSWindow.windowNumbers(options: []) ?? []
                guard window.isVisible, window.level.rawValue > NSWindow.Level.mainMenu.rawValue,
                      (window as? NSPanel)?.isFloatingPanel == true,
                      let islandIndex = order.firstIndex(of: NSNumber(value: window.windowNumber)),
                      let otherIndex = order.firstIndex(of: NSNumber(value: other.windowNumber)),
                      islandIndex < otherIndex else {
                    fputs("Island lost overlay ordering (\(phase))\n", stderr); exit(1)
                }
            }
            await verifyOverlay("unpinned reveal")
            store.pinned = true
            await verifyOverlay("pinned")
            island.checkPointer(at: NSPoint(x: screen.frame.minX + 5, y: screen.frame.minY + 5))
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard store.expanded, window.isVisible else {
                fputs("Pin did not keep the island open after pointer exit\n", stderr); exit(1)
            }
            island.checkPointer(at: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 4))
            store.pinned = false
            await verifyOverlay("unpinned again")
            other.close()
            fputs("Window overlay: reveal, competing window, pin and unpin passed\n", stderr)
            island.checkPointer(at: NSPoint(x: screen.frame.minX + 5, y: screen.frame.minY + 5))
            for _ in 0..<15 { try? await Task.sleep(nanoseconds: 70_000_000); record(0.07) }
            guard !store.expanded, !window.isVisible else { fputs("Pointer exit did not hide the window\n", stderr); exit(1) }
            if !frames.isEmpty { frames[frames.count - 1].delay = 0.9 }
            do {
                let directory = output.deletingLastPathComponent()
                try PreviewRecorder.gif(frames, to: directory.appendingPathComponent("SoloIsland-opening.gif"))
                try await verifyScreenSwitchHover(on: screen)
                // Each still gets a fresh, motion-free host. Reusing a host while changing
                // tabs can cache a SwiftUI crossfade rather than its final content.
                let imageURL = folder.appendingPathComponent("Дизайн проекта.png")
                let briefURL = folder.appendingPathComponent("План проекта.txt")
                try "Идея → дизайн → готовый проект".write(to: briefURL, atomically: true, encoding: .utf8)
                let stills: [(String, IslandTab)] = [
                    ("preview", .music), ("tasks", .tasks), ("focus", .focus), ("files", .files), ("actions", .actions),
                    ("onboarding", .music), ("custom-focus", .focus), ("deadline", .tasks), ("reminder", .tasks), ("settings", .settings),
                    ("music-compact", .music), ("tasks-compact", .tasks), ("focus-compact", .focus),
                    ("settings-compact", .settings), ("settings-appearance", .settings),
                    ("music-empty", .music), ("tasks-empty", .tasks), ("music-error", .music)
                ]
                for (name, tab) in stills {
                    fputs("Native snapshot: \(name)\n", stderr)
                    let destination = name == "preview" ? output : directory.appendingPathComponent("SoloIsland-" + name + ".png")
                    let stillFolder = folder.appendingPathComponent("still-" + name)
                    var stillFixture = fixture
                    if name.hasSuffix("-compact") { stillFixture.settings.expandedWidth = 640 }
                    if name == "focus" || name == "focus-compact" {
                        stillFixture.focus = FocusSession(taskID: fixture.tasks[1].id,
                            minutes: name == "focus-compact" ? 5999 : 90,
                            now: name == "focus-compact" ? Date() : Date().addingTimeInterval(-60))
                    }
                    if name == "tasks-empty" { stillFixture.tasks = [] }
                    if name == "custom-focus" { stillFixture.settings.customFocusSeconds = 37 * 60 }
                    if name == "onboarding" { stillFixture.settings.musicOnboardingComplete = false }
                    if tab == .files {
                        stillFixture.shelf.append(ShelfEntry(path: imageURL.path, kind: .image, isPinned: true))
                        stillFixture.shelf.append(ShelfEntry(path: briefURL.path))
                    }
                    try StateRepository(url: stillFolder.appendingPathComponent("state.json")).save(stillFixture)
                    let stillStore = IslandStore(dataFolder: stillFolder)
                    var stillTrack = previewTrack
                    if name == "music-compact" {
                        stillTrack.title = "Город засыпает, а мы заканчиваем большой проект"
                        stillTrack.artist = "Демонстрационный исполнитель · длинное имя для предпросмотра"
                    }
                    stillStore.media.setPreview(name == "music-empty" ? NowPlaying() : stillTrack)
                    if name == "music-error" { stillStore.media.error = "Источник временно недоступен. Переподключи плеер в настройках." }
                    stillStore.tab = tab; stillStore.pinned = true
                    if name == "deadline" || name == "reminder" {
                        var draft = fixture.tasks[1]
                        draft.dueAt = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date().addingTimeInterval(3 * 86400))
                        draft.reminderAt = Date().addingTimeInterval(2 * 86400)
                        stillStore.taskDraft = draft; stillStore.editingReminder = name == "reminder"
                    }
                    let stillController = IslandWindowController(store: stillStore, trackPointer: false, reducedMotionOverride: true)
                    stillStore.reveal(tab)
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    guard let stillWindow = stillController.window else { throw CocoaError(.fileWriteUnknown) }
                    if name == "settings-appearance" {
                        guard PreviewRecorder.revealControl("Ширина", in: stillWindow) else { throw CocoaError(.fileWriteUnknown) }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    try PreviewRecorder.png(stillWindow, to: destination, overlay: stillController.activityWindow)
                    if name == "preview" { try FileManager.default.copyItem(at: destination, to: imageURL) }
                    stillController.close()
                }
                try await verifyNotchActivity(folder: folder.appendingPathComponent("notch-activity"), directory: directory, fixture: fixture)
                try await recordFocusMotion(folder: folder.appendingPathComponent("focus-motion"), directory: directory, fixture: fixture)
                try await verifyWebPlayer(folder: folder.appendingPathComponent("web-smoke"), output: directory.appendingPathComponent("SoloIsland-web-demo.png"))
                try await InteractionRecorder.record(in: directory.appendingPathComponent("interactions"))
                let reducedStore = IslandStore(dataFolder: folder.appendingPathComponent("reduced-motion"))
                let reducedController = IslandWindowController(store: reducedStore, trackPointer: false, reducedMotionOverride: true)
                reducedStore.reveal()
                guard let reducedWindow = reducedController.window, reducedWindow.isVisible,
                      abs(reducedWindow.frame.width - reducedStore.presentationWidth) < 1 else {
                    fputs("Reduce Motion did not open immediately\n", stderr); exit(1)
                }
                reducedStore.dismiss()
                guard !reducedWindow.isVisible else { fputs("Reduce Motion did not hide immediately\n", stderr); exit(1) }
                try await verifyQuitButton(in: reducedController, store: reducedStore,
                    result: directory.appendingPathComponent("SoloIsland-quit-check.json"))
            } catch { fputs("Preview: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
    private func verifyScreenSwitchHover(on screen: NSScreen) async throws {
        guard let window = island.window else { throw CocoaError(.fileWriteUnknown) }
        let neck = NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 4)
        let outside = NSPoint(x: screen.frame.minX + 5, y: screen.frame.minY + 5)
        @MainActor func requireOpen(_ phase: String) {
            guard store.expanded, window.isVisible else {
                fputs("Immediate hover after screen switch failed: \(phase)\n", stderr); exit(1)
            }
        }
        island.screenContextDidChange(at: outside)
        island.checkPointer(at: neck)
        requireOpen("first entry after an outside sample")
        island.checkPointer(at: outside) // Queue an old close before switching again.
        island.screenContextDidChange(at: neck)
        requireOpen("stationary cursor")
        try? await Task.sleep(nanoseconds: 650_000_000)
        requireOpen("old close was cancelled")
        store.dismiss()
        island.screenContextDidChange(at: neck)
        requireOpen("cached inside state after hiding")
        store.pinned = true
        island.screenContextDidChange(at: outside)
        try? await Task.sleep(nanoseconds: 650_000_000)
        requireOpen("pin survives a Space switch")
        store.pinned = false; store.cancelPendingHover(); store.dismiss()
        try? await Task.sleep(nanoseconds: 400_000_000)
        // Exercise both actual notification subscriptions, not just the helper.
        for (center, name) in [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        ] {
            store.hover(true)
            center.post(name: name, object: nil)
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !store.expanded else { fputs("Screen notification retained a stale hover\n", stderr); exit(1) }
            island.checkPointer(at: neck)
            requireOpen("notification resets hover tracking")
            store.cancelPendingHover(); store.dismiss()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        fputs("Screen hover: Space/display notifications, immediate entry, cached cursor, stale close and pin passed\n", stderr)
    }
    private func verifyQuitButton(in controller: IslandWindowController, store: IslandStore, result: URL) async throws {
        guard let window = controller.window else { throw CocoaError(.fileWriteUnknown) }
        store.reveal(.settings); window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 250_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
        guard let rect = RecordingTargets.frames["Завершить Solo Island:\(ObjectIdentifier(store))"],
              rect.width > 10, rect.height > 10 else {
            throw NSError(domain: "SoloIsland.Preview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Native quit button was not laid out"])
        }
        previewQuitResult = result
        // AppKit may track mouse-down synchronously. Queue its release first,
        // and keep the watchdog off the UI thread so a broken click cannot hang CI.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            fputs("Native quit button did not terminate the process\n", stderr); exit(1)
        }
        var events: [NSEvent] = []
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
            guard let event = NSEvent.mouseEvent(with: type,
                location: NSPoint(x: rect.midX, y: window.frame.height - rect.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: index + 1, clickCount: 1, pressure: index == 0 ? 1 : 0) else {
                throw CocoaError(.fileWriteUnknown)
            }
            events.append(event)
        }
        NSApp.postEvent(events[1], atStart: false)
        window.sendEvent(events[0])
    }
    private func verifyNotchActivity(folder: URL, directory: URL, fixture: IslandState) async throws {
        var fixture = fixture; fixture.focus = nil
        try StateRepository(url: folder.appendingPathComponent("state.json")).save(fixture)
        let demo = IslandStore(dataFolder: folder)
        let controller = IslandWindowController(store: demo, trackPointer: false, reducedMotionOverride: true)
        defer { controller.close() }
        guard let main = controller.window, let hud = controller.activityWindow, let screen = NSScreen.screens.first else {
            throw CocoaError(.fileWriteUnknown)
        }
        func require(_ condition: Bool, _ reason: String) throws {
            guard condition else {
                throw NSError(domain: "SoloIsland.Notch", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
            }
        }
        try require(!main.isVisible && !hud.isVisible, "Idle notch must be completely hidden")
        var track = NowPlaying(); track.title = "Демонстрационный трек"; track.artist = "Предпросмотр"
        track.playing = true; track.elapsedTime = 30; track.duration = 240
        demo.media.setPreview(track)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try require(hud.isVisible && !main.isVisible && !hud.canBecomeKey && hud.ignoresMouseEvents,
                    "Playback wings must stay passive without expanding the main window")
        try require(abs(hud.frame.maxY - screen.frame.maxY) < 1 && hud.frame.height == demo.compactHeight
                    && hud.frame.width > demo.cameraWidth + 100, "Camera clearance or wing placement is invalid")
        try PreviewRecorder.png(hud, to: directory.appendingPathComponent("SoloIsland-notch-music.png"))
        track.playing = false; demo.media.setPreview(track)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try require(hud.isVisible && !main.isVisible, "Pause must retain the cover without opening the panel")
        try PreviewRecorder.png(hud, to: directory.appendingPathComponent("SoloIsland-notch-paused.png"))
        let date = Date()
        var focus = FocusSession(taskID: fixture.tasks[0].id, minutes: 5999, now: date)
        demo.previewFocus(focus, at: date)
        track.playing = true; demo.media.setPreview(track)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try require(demo.focusedTime == "99:59" && hud.isVisible, "Combined focus must retain HH:MM")
        try PreviewRecorder.png(hud, to: directory.appendingPathComponent("SoloIsland-notch-combined.png"))
        demo.media.setPreview(NowPlaying())
        try? await Task.sleep(nanoseconds: 100_000_000)
        try PreviewRecorder.png(hud, to: directory.appendingPathComponent("SoloIsland-notch-focus.png"))
        focus.pause(at: date); demo.previewFocus(focus, at: date)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try require(hud.isVisible && demo.focusedTime == "99:59", "Paused focus must retain remaining time")
        try PreviewRecorder.png(hud, to: directory.appendingPathComponent("SoloIsland-notch-focus-paused.png"))
        let outside = NSPoint(x: screen.frame.minX + 5, y: screen.frame.minY + 5)
        controller.screenContextDidChange(at: outside)
        controller.checkPointer(at: NSPoint(x: hud.frame.minX + 18, y: hud.frame.midY))
        try require(demo.expanded && main.isVisible, "Hovering a wing after a Space switch must reveal immediately")
        controller.checkPointer(at: outside)
        try? await Task.sleep(nanoseconds: 650_000_000)
        try require(!demo.expanded && !main.isVisible && hud.isVisible && hud.ignoresMouseEvents,
                    "Leaving the island must collapse the body while retaining the focus wings")
        demo.previewFocus(nil, at: date)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try require(!hud.isVisible && !main.isVisible, "Ending all activity must hide both windows")
        fputs("Notch activity: idle hidden, playback, pause, combined focus, wing hover and camera clearance passed\n", stderr)
    }
    private func recordFocusMotion(folder: URL, directory: URL, fixture: IslandState) async throws {
        var fixture = fixture; fixture.settings.customFocusSeconds = 12
        let beginning = Date()
        var focus = FocusSession(taskID: fixture.tasks[1].id, duration: 12, now: beginning)
        fixture.focus = focus
        try StateRepository(url: folder.appendingPathComponent("state.json")).save(fixture)
        let demo = IslandStore(dataFolder: folder)
        demo.tab = .focus; demo.pinned = true
        let controller = IslandWindowController(store: demo, trackPointer: false, reducedMotionOverride: true)
        demo.reveal(.focus)
        guard let window = controller.window else { throw CocoaError(.fileWriteUnknown) }
        defer { controller.close() }
        struct Sample: Encodable { let seconds: Double; let remaining: Int; let paused: Bool }
        var samples: [Sample] = [], frames: [PreviewRecorder.Frame] = []
        var paused = false, resumed = false
        // A controlled demo clock keeps the native recording smooth even when
        // bitmap rendering on the CI host takes longer than the sample interval.
        for index in 0..<128 {
            let elapsed = Double(index) * 0.05
            let date = beginning.addingTimeInterval(elapsed)
            if elapsed >= 2 && !paused { focus.pause(at: date); paused = true }
            if elapsed >= 3 && !resumed { focus.resume(at: date); resumed = true }
            demo.previewFocus(focus, at: date)
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard let image = PreviewRecorder.snapshot(window)?.cgImage else { throw CocoaError(.fileWriteUnknown) }
            frames.append(.init(image: image, delay: 0.05))
            samples.append(Sample(seconds: elapsed, remaining: Int(ceil(focus.remaining(at: date))), paused: focus.isPaused))
        }
        guard Set(samples.map(\.remaining)).count >= 4, samples.contains(where: \.paused), resumed, frames.count == 128 else {
            fputs("Focus motion did not record countdown, pause and resume\n", stderr); exit(1)
        }
        try PreviewRecorder.gif(frames, to: directory.appendingPathComponent("SoloIsland-focus-motion.gif"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(samples).write(to: directory.appendingPathComponent("SoloIsland-focus-motion.json"))
        fputs("Focus recording: countdown, progress, pause and resume passed\n", stderr)
    }
    private func verifyWebPlayer(folder: URL, output: URL) async throws {
        var fixture = IslandState(); fixture.settings.musicOnboardingComplete = true; fixture.settings.musicProvider = .yandex
        try StateRepository(url: folder.appendingPathComponent("state.json")).save(fixture)
        let webStore = IslandStore(dataFolder: folder)
        webStore.musicWebsiteVisible = true
        let controller = IslandWindowController(store: webStore, trackPointer: false, reducedMotionOverride: true)
        webStore.reveal(.music)
        webStore.webMusic.loadPreviewFixture()
        @MainActor func until(_ check: () -> Bool) async -> Bool {
            for _ in 0..<100 {
                if check() { return true }; try? await Task.sleep(nanoseconds: 60_000_000)
            }
            return check()
        }
        guard await until({ webStore.media.usingWeb && webStore.media.track.title == "Веб-трек" }) else {
            fputs("Web fixture metadata did not reach the native player\n", stderr); exit(1)
        }
        webStore.media.command(["toggle-play-pause"])
        guard await until({ webStore.media.track.isPlaying }) else { fputs("Embedded web play failed\n", stderr); exit(1) }
        webStore.media.seek(2)
        guard await until({ (webStore.media.track.elapsedTime ?? 0) >= 1.8 }) else { fputs("Embedded web seek failed\n", stderr); exit(1) }
        webStore.media.command(["next-track"])
        guard await until({ webStore.media.track.title == "Следующий веб-трек" }) else { fputs("Embedded web next failed\n", stderr); exit(1) }
        webStore.media.command(["toggle-play-pause"])
        guard await until({ !webStore.media.track.isPlaying }) else { fputs("Embedded web pause failed\n", stderr); exit(1) }
        webStore.musicWebsiteVisible = false
        try? await Task.sleep(nanoseconds: 250_000_000)
        if let window = controller.window { try PreviewRecorder.png(window, to: output, overlay: controller.activityWindow) }
        controller.close()
        webStore.webMusic.stop()
        fputs("Embedded WKWebView smoke: metadata, play, seek, next and pause passed\n", stderr)
    }

}

final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { makeKey(); NSApp.activate(ignoringOtherApps: true) }
        super.sendEvent(event)
    }
}

@MainActor
final class IslandWindowController: NSWindowController {
    private let store: IslandStore
    private var subscriptions = Set<AnyCancellable>()
    private var pointerTimer: Timer?
    private var hotspot = NSRect.zero
    private var hoverTracker = NotchHoverTracker()
    private var pointerDisplay: NSNumber?
    private let tracksPointer: Bool
    private var activity: NotchActivityController!
    var activityWindow: NSWindow? { activity?.window }
    private var motion: Task<Void, Never>?
    private var animationTarget: NSRect?
    private let reducedMotionOverride: Bool?
    init(store: IslandStore, trackPointer: Bool = true, reducedMotionOverride: Bool? = nil) {
        self.store = store; self.reducedMotionOverride = reducedMotionOverride
        self.tracksPointer = trackPointer
        let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        // The island always reveals above other apps. Pinning only keeps it open.
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        super.init(window: panel)
        let root = IslandRootView(store: store)
        let view: AnyView
        if let reducedMotionOverride { view = AnyView(root.environment(\.islandReducedMotionOverride, reducedMotionOverride)) }
        else { view = AnyView(root) }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        activity = NotchActivityController(store: store, reducedMotionOverride: reducedMotionOverride)
        panel.minSize = .zero; panel.contentMinSize = .zero
        store.$expanded.removeDuplicates().sink { [weak self] value in self?.layout(expanded: value, transitioning: true) }.store(in: &subscriptions)
        store.$state.map(\.settings).removeDuplicates().sink { [weak self] settings in
            guard let self else { return }; self.layout(expanded: self.store.expanded, settings: settings)
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .sink { [weak self] _ in
                Task { @MainActor in self?.screenContextDidChange() }
            }.store(in: &subscriptions)
        layout(expanded: false)
        if trackPointer {
            pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkPointer() }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func close() {
        activity?.close()
        super.close()
    }
    func screenContextDidChange(at location: NSPoint? = nil) {
        store.cancelPendingHover()
        hoverTracker.screenDidChange()
        pointerDisplay = nil
        layout(expanded: store.expanded)
        if tracksPointer || location != nil { checkPointer(at: location) }
        if store.pinned && store.expanded { window?.orderFrontRegardless() }
    }
    func checkPointer(at location: NSPoint? = nil) {
        guard let window, let screen = NSScreen.screens.first else { return }
        let point = location ?? NSEvent.mouseLocation
        let display = NSScreen.screens.first(where: { $0.frame.contains(point) })?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let previous = pointerDisplay, let display, previous != display {
            store.cancelPendingHover()
            hoverTracker.screenDidChange()
        }
        pointerDisplay = display
        let inNeckBand = point.y > screen.frame.maxY - store.compactHeight
        let onNeck = abs(point.x - screen.frame.midX) <= (store.cameraWidth + 16) / 2
        let onBody = store.expanded && window.frame.contains(point) && (!inNeckBand || onNeck)
        // Transparent shoulders must never block clicks on the menu bar.
        if store.expanded { window.ignoresMouseEvents = !onBody }
        let activityHotspot = activity.isPresented ? activity.window?.frame.insetBy(dx: -8, dy: -6) : nil
        let inside = hotspot.contains(point) || onBody || activityHotspot?.contains(point) == true
        switch hoverTracker.update(isInside: inside) {
        case .entered(let immediately):
            store.hover(true, immediately: immediately)
            if immediately && store.expanded { window.orderFrontRegardless() }
        case .exited: store.hover(false)
        case nil: break
        }
    }
    private func layout(expanded: Bool, settings: IslandSettings? = nil, transitioning: Bool = false) {
        guard let screen = NSScreen.screens.first, let window else { return }
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { cameraWidth = max(0, right.minX - left.maxX) }
        else { cameraWidth = 160 }
        let preferences = settings ?? store.state.settings
        // The auxiliary menu-bar areas retain the physical camera clearance
        // when macOS hides its menu bar in a full-screen Space.
        let top = [CGFloat(28), screen.safeAreaInsets.top,
                   screen.auxiliaryTopLeftArea?.height ?? 0,
                   screen.auxiliaryTopRightArea?.height ?? 0].max() ?? 28
        hotspot = NSRect(x: screen.frame.midX - max(110, cameraWidth / 2 + 22), y: screen.frame.maxY - top - 12,
                         width: max(220, cameraWidth + 44), height: top + 12)
        let width = min(max(640, CGFloat(preferences.expandedWidth)), screen.frame.width - 40)
        let bodyHeight = min(CGFloat(520), screen.frame.height - top - 36)
        let target = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - top - bodyHeight, width: width, height: top + bodyHeight)
        let neck = NSRect(x: screen.frame.midX - (cameraWidth + 16) / 2, y: screen.frame.maxY - top, width: cameraWidth + 16, height: top)
        activity.layout(on: screen, cameraWidth: cameraWidth, height: top)
        store.cameraWidth = cameraWidth; store.compactHeight = top
        store.presentationWidth = width; store.presentationHeight = top + bodyHeight
        if CommandLine.arguments.contains("--render-preview") {
            fputs("layout expanded=\(expanded) transition=\(transitioning) active=\(animationTarget != nil) frame=\(window.frame.width)\n", stderr)
        }
        let reduceMotion = reducedMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0 : preferences.animationDuration
        if CommandLine.arguments.contains("--render-preview") {
            fputs("motion system=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) effective=\(reduceMotion) duration=\(duration)\n", stderr)
        }
        if !expanded {
            if !transitioning && animationTarget == neck { return }
            store.contentVisible = false; window.ignoresMouseEvents = true
            guard window.isVisible, duration > 0 else {
                motion?.cancel(); animationTarget = nil; window.orderOut(nil); window.setFrame(neck, display: false); return
            }
            animate(to: neck, expanding: false, duration: duration)
            return
        }
        window.ignoresMouseEvents = false
        if transitioning || !window.isVisible {
            store.contentVisible = reduceMotion
            if !window.isVisible { window.setFrame(neck, display: false) }
            window.alphaValue = 1; window.orderFront(nil)
            animate(to: target, expanding: true, duration: duration)
        } else {
            // A screen notification or identical settings emission must not jump an active animation to its end.
            if let active = animationTarget {
                if active != target { animate(to: target, expanding: true, duration: duration) }
                return
            }
            window.setFrame(target, display: true); store.contentVisible = true
        }
    }
    private func animate(to target: NSRect, expanding: Bool, duration: Double) {
        motion?.cancel(); animationTarget = target
        guard let window else { return }
        guard duration > 0 else {
            animationTarget = nil; window.setFrame(target, display: true); store.contentVisible = expanding
            if !expanding { window.orderOut(nil) }; return
        }
        let origin = window.frame
        motion = Task { @MainActor [weak self] in
            let steps = max(10, Int(ceil(duration * 60)))
            for step in 0...steps {
                guard !Task.isCancelled, let self, self.store.expanded == expanding, let window = self.window else { return }
                let progress = Double(step) / Double(steps)
                let fraction = expanding ? 1 - pow(1 - progress, 3) : progress * progress * (3 - 2 * progress)
                let frame = NSRect(x: origin.minX + (target.minX - origin.minX) * fraction,
                                   y: origin.minY + (target.minY - origin.minY) * fraction,
                                   width: origin.width + (target.width - origin.width) * fraction,
                                   height: origin.height + (target.height - origin.height) * fraction)
                window.setFrame(frame, display: true)
                if CommandLine.arguments.contains("--render-preview"), step == 1 || step == steps / 2 {
                    fputs("motion step=\(step) frame=\(window.frame.width)\n", stderr)
                }
                if expanding && progress >= 0.55 && !self.store.contentVisible { self.store.contentVisible = true }
                if progress >= 1 {
                    self.animationTarget = nil
                    if !expanding { window.orderOut(nil) }
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
            }
        }
    }
}
