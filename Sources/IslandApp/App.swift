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
        do { try StateRepository(url: folder.appendingPathComponent("state.json")).save(fixture) }
        catch { fputs("Preview fixture: \(error.localizedDescription)\n", stderr); exit(1) }
        store = IslandStore(dataFolder: folder)
        store.notificationsEnabled = true
        island = IslandWindowController(store: store)
        store.pinned = true; store.reveal(.tasks)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            guard let view = island.window?.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                fputs("Cannot capture preview view\n", stderr); exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            do {
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: output, options: .atomic)
                NSApp.terminate(nil)
            } catch { fputs("Preview: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
}

final class IslandPanel: NSPanel {
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
    init(store: IslandStore) {
        self.store = store
        let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: IslandRootView(store: store))
        store.$expanded.removeDuplicates().sink { [weak self] expanded in self?.layout(expanded: expanded) }.store(in: &subscriptions)
        store.$state.map(\.settings).removeDuplicates().sink { [weak self] settings in
            guard let self else { return }; self.layout(expanded: self.store.expanded, settings: settings)
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.layout(expanded: self.store.expanded) }
            }
        layout(expanded: false)
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPointer() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func checkPointer() {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let inside = hotspot.contains(point) || (store.expanded && window.frame.contains(point))
        if inside != pointerInside {
            pointerInside = inside; store.hover(inside)
        }
    }
    private func layout(expanded: Bool, settings: IslandSettings? = nil) {
        guard let screen = NSScreen.screens.first, let window else { return }
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 140 }
        let preferences = settings ?? store.state.settings
        let top = max(28, screen.safeAreaInsets.top)
        hotspot = NSRect(x: screen.frame.midX - max(110, cameraWidth / 2 + 22),
            y: screen.frame.maxY - top - 14, width: max(220, cameraWidth + 44), height: top + 14)
        store.cameraWidth = cameraWidth; store.compactHeight = top
        guard expanded else {
            // No collapsed capsule and no transparent window intercepting other applications.
            window.ignoresMouseEvents = true
            if window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = preferences.animationDuration
                    window.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor in if self?.store.expanded == false { self?.window?.orderOut(nil) } }
                })
            } else { window.orderOut(nil) }
            return
        }
        let width = min(max(640, CGFloat(preferences.expandedWidth)), screen.frame.width - 40)
        let height = min(CGFloat(520), screen.frame.height - top - 36)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - top - 8 - height, width: width, height: height)
        window.ignoresMouseEvents = false
        if !window.isVisible {
            window.setFrame(frame, display: true)
            window.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            // Normal window ordering: a subsequently opened application can cover this panel.
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = preferences.animationDuration
                window.animator().alphaValue = 1
            }
        } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = preferences.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
                window.animator().alphaValue = 1
            }
        }
        // Intentionally no orderFront on settings or timer updates.
    }
}
