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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = IslandStore()
        island = IslandWindowController(store: store)
        island.showWindow(nil)
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
    func applicationWillTerminate(_ notification: Notification) { store.stop() }
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
    init(store: IslandStore) {
        self.store = store
        let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func layout(expanded: Bool, settings: IslandSettings? = nil) {
        guard let screen = NSScreen.screens.first, let window else { return }
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 110 }
        let compactWidth = max(250, cameraWidth + 108)
        let compactHeight = max(34, screen.safeAreaInsets.top)
        let preferences = settings ?? store.state.settings
        let width = expanded ? min(CGFloat(preferences.expandedWidth), screen.frame.width - 60) : compactWidth
        let height: CGFloat = expanded ? compactHeight + 410 : compactHeight
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        store.cameraWidth = cameraWidth
        store.compactHeight = compactHeight
        // Resizing the NSPanel itself keeps transparent areas from swallowing clicks.
        if window.frame.isEmpty || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = preferences.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        }
        window.orderFrontRegardless()
    }
}
