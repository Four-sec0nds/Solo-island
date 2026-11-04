import AppKit
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

@MainActor
struct ActionsView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @State private var adding = false
    @State private var page = 0
    @State private var title = ""
    @State private var kind: ActionKind = .application
    @State private var target = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IslandSectionHeading(title: adding ? "Новое действие" : "Быстрый запуск",
                                     subtitle: adding ? nil : "Приложения, папки и команды")
                Spacer()
                if !adding {
                    Button { adding = true } label: { IslandAddIcon() }
                        .buttonStyle(IslandButtonStyle(.filled)).accessibilityLabel("Добавить действие").recordingTarget("Добавить действие")
                }
            }
            if adding {
                TextField("Название кнопки", text: $title).textFieldStyle(IslandTextFieldStyle())
                IslandSegments(options: ActionKind.allCases, selection: $kind, title: { $0.rawValue })
                if kind == .shortcut {
                    TextField("Точное имя из «Быстрых команд»", text: $target).textFieldStyle(IslandTextFieldStyle())
                } else {
                    HStack {
                        Text(target.isEmpty ? "Объект не выбран" : URL(fileURLWithPath: target).lastPathComponent).font(.caption).lineLimit(1)
                        Spacer()
                        Button("Выбрать…", action: choose)
                    }
                }
                Spacer()
                HStack {
                    Button("Отмена") { reset() }.recordingTarget("Отмена")
                    Spacer()
                    Button("Добавить") {
                        store.addAction(QuickAction(title: title.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, target: target))
                        reset()
                    }.buttonStyle(IslandButtonStyle(.filled))
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if store.state.actions.isEmpty {
                EmptyState(icon: "bolt.fill", title: "Ваши частые действия", detail: "Добавьте приложения, папки и команды — они будут доступны в одном месте.")
            } else {
                GeometryReader { geometry in
                    let capacity = max(3, Int((geometry.size.height - 26) / 64) * 3)
                    let count = ContentPages.count(items: store.state.actions.count, capacity: capacity)
                    let range = ContentPages.range(items: store.state.actions.count, capacity: capacity, page: page)
                    VStack(spacing: 6) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Array(store.state.actions[range])) { action in
                                Button { store.runAction(action) } label: {
                                    HStack(spacing: 8) {
                                        QuickActionIcon(action: action).frame(width: 28, height: 28)
                                        Text(action.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Spacer(minLength: 0)
                                    }.padding(8).frame(maxWidth: .infinity).frame(height: 56).islandCard()
                                }.buttonStyle(IslandButtonStyle(.bare)).recordingTarget(action.title)
                                    .contextMenu { Button("Удалить", role: .destructive) { store.removeAction(action.id) } }
                            }
                        }
                        Spacer(minLength: 0)
                        if count > 1 { CompactPageBar(page: $page, count: count, id: "действия") }
                    }.onChange(of: count) { _, value in page = min(page, value - 1) }
                }
            }
        }.onChange(of: kind) { _, _ in target = "" }
            .onChange(of: adding) { _, value in store.editingForm = value }
            .onDisappear { store.editingForm = false }
    }
    private func reset() { adding = false; title = ""; target = "" }
    private func choose() {
        let panel = NSOpenPanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 5)
        panel.canChooseDirectories = kind == .folder; panel.canChooseFiles = kind == .application
        panel.allowsMultipleSelection = false
        if kind == .application { panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        if panel.runModal() == .OK, let url = panel.url {
            target = url.path
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        }
    }
}

@MainActor
private struct QuickActionIcon: View {
    let action: QuickAction
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: action.kind == .folder ? "folder.fill" : action.kind == .shortcut ? "bolt.fill" : "app.fill").resizable().aspectRatio(contentMode: .fit).padding(7).foregroundStyle(.purple) }
        }.task(id: action.target) {
            let path = action.kind == .shortcut ? "/System/Applications/Shortcuts.app" : action.target
            if FileManager.default.fileExists(atPath: path) { image = NSWorkspace.shared.icon(forFile: path) }
        }
    }
}
