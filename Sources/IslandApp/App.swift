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
        island = IslandWindowController(store: store, trackPointer: false)
        Task { @MainActor [self] in
            guard let window = island.window, !window.isVisible, window.level == .normal,
                  (window as? NSPanel)?.isFloatingPanel == false, let screen = NSScreen.screens.first else {
                fputs("Hidden/normal window precondition failed\n", stderr); exit(1)
            }
            let canvas = NSSize(width: store.presentationWidth, height: store.presentationHeight)
            var frames: [PreviewRecorder.Frame] = []
            @MainActor func record(_ delay: Double) {
                if let image = PreviewRecorder.animationFrame(window, canvas: canvas, neckWidth: store.cameraWidth, neckHeight: store.compactHeight) {
                    frames.append(.init(image: image, delay: delay))
                }
            }
            record(0.5)
            island.checkPointer(at: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 4))
            for _ in 0..<22 { try? await Task.sleep(nanoseconds: 30_000_000); record(0.03) }
            guard store.expanded, window.isVisible, abs(window.frame.maxY - screen.frame.maxY) < 1 else {
                fputs("Notch reveal/attachment failed\n", stderr); exit(1)
            }
            if !frames.isEmpty { frames[frames.count - 1].delay = 0.9 }
            store.pinned = true
            guard window.level.rawValue > NSWindow.Level.mainMenu.rawValue, (window as? NSPanel)?.isFloatingPanel == true else {
                fputs("Pin did not enable always-on-top\n", stderr); exit(1)
            }
            store.pinned = false
            guard window.level == .normal else { fputs("Unpin did not restore normal ordering\n", stderr); exit(1) }
            island.checkPointer(at: NSPoint(x: screen.frame.minX + 5, y: screen.frame.minY + 5))
            for _ in 0..<15 { try? await Task.sleep(nanoseconds: 70_000_000); record(0.07) }
            guard !store.expanded, !window.isVisible else { fputs("Pointer exit did not hide the window\n", stderr); exit(1) }
            if !frames.isEmpty { frames[frames.count - 1].delay = 0.9 }
            do {
                let directory = output.deletingLastPathComponent()
                try PreviewRecorder.gif(frames, to: directory.appendingPathComponent("SoloIsland-opening.gif"))
                store.pinned = true; store.reveal(.music)
                try? await Task.sleep(nanoseconds: 650_000_000)
                try PreviewRecorder.png(window, to: output)
                store.tab = .tasks
                try? await Task.sleep(nanoseconds: 350_000_000)
                try PreviewRecorder.png(window, to: directory.appendingPathComponent("SoloIsland-tasks.png"))
                store.tab = .actions
                try? await Task.sleep(nanoseconds: 400_000_000)
                try PreviewRecorder.png(window, to: directory.appendingPathComponent("SoloIsland-actions.png"))
                NSApp.terminate(nil)
            } catch { fputs("Preview: \(error.localizedDescription)\n", stderr); exit(1) }
        }
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
    private var screenObserver: NSObjectProtocol?
    private var pointerTimer: Timer?
    private var hotspot = NSRect.zero
    private var pointerInside = false
    private var motion: Task<Void, Never>?
    init(store: IslandStore, trackPointer: Bool = true) {
        self.store = store
        let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .normal; panel.isFloatingPanel = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: IslandRootView(store: store))
        store.$expanded.removeDuplicates().sink { [weak self] value in self?.layout(expanded: value, transitioning: true) }.store(in: &subscriptions)
        store.$pinned.removeDuplicates().sink { [weak self] pinned in
            guard let self, let window = self.window else { return }
            (window as? NSPanel)?.isFloatingPanel = pinned
            window.level = pinned ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) : .normal
            if pinned && window.isVisible { window.orderFront(nil) }
        }.store(in: &subscriptions)
        store.$state.map(\.settings).removeDuplicates().sink { [weak self] settings in
            guard let self else { return }; self.layout(expanded: self.store.expanded, settings: settings)
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.layout(expanded: self.store.expanded) }
            }
        layout(expanded: false)
        if trackPointer {
            pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkPointer() }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func checkPointer(at location: NSPoint? = nil) {
        guard let window, let screen = NSScreen.screens.first else { return }
        let point = location ?? NSEvent.mouseLocation
        let inNeckBand = point.y > screen.frame.maxY - store.compactHeight
        let onNeck = abs(point.x - screen.frame.midX) <= (store.cameraWidth + 16) / 2
        let onBody = store.expanded && window.frame.contains(point) && (!inNeckBand || onNeck)
        // Transparent shoulders must never block clicks on the menu bar.
        if store.expanded { window.ignoresMouseEvents = !onBody }
        let inside = hotspot.contains(point) || onBody
        if inside != pointerInside { pointerInside = inside; store.hover(inside) }
    }
    private func layout(expanded: Bool, settings: IslandSettings? = nil, transitioning: Bool = false) {
        guard let screen = NSScreen.screens.first, let window else { return }
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { cameraWidth = max(0, right.minX - left.maxX) }
        else { cameraWidth = 160 }
        let preferences = settings ?? store.state.settings
        let top = max(28, screen.safeAreaInsets.top)
        hotspot = NSRect(x: screen.frame.midX - max(110, cameraWidth / 2 + 22), y: screen.frame.maxY - top - 12,
                         width: max(220, cameraWidth + 44), height: top + 12)
        let width = min(max(640, CGFloat(preferences.expandedWidth)), screen.frame.width - 40)
        let bodyHeight = min(CGFloat(520), screen.frame.height - top - 36)
        let target = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - top - bodyHeight, width: width, height: top + bodyHeight)
        let neck = NSRect(x: screen.frame.midX - (cameraWidth + 16) / 2, y: screen.frame.maxY - top, width: cameraWidth + 16, height: top)
        store.cameraWidth = cameraWidth; store.compactHeight = top
        store.presentationWidth = width; store.presentationHeight = top + bodyHeight
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0 : preferences.animationDuration
        if !expanded {
            motion?.cancel(); store.contentVisible = false; window.ignoresMouseEvents = true
            guard window.isVisible, duration > 0 else { window.orderOut(nil); window.setFrame(neck, display: false); return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.7, 1)
                window.animator().setFrame(neck, display: true)
            }
            motion = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled, let self, !self.store.expanded else { return }
                self.window?.orderOut(nil)
            }
            return
        }
        window.ignoresMouseEvents = false
        if transitioning || !window.isVisible {
            motion?.cancel(); store.contentVisible = reduceMotion
            if !window.isVisible { window.setFrame(neck, display: false) }
            window.alphaValue = 1; window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.8, 0.2, 1)
                window.animator().setFrame(target, display: true)
            }
            motion = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 0.5 * 1_000_000_000))
                guard !Task.isCancelled, let self, self.store.expanded else { return }
                self.store.contentVisible = true
            }
        } else {
            // Theme, progress and setting updates cannot raise the window.
            window.setFrame(target, display: true)
        }
    }
}
