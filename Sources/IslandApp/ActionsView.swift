import AppKit
import SwiftUI
import IslandCore
import UniformTypeIdentifiers

@MainActor
struct ActionsView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var store: IslandStore
    @State private var adding = false
    @State private var title = ""
    @State private var kind: ActionKind = .application
    @State private var target = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(adding ? "Новое действие" : "Быстрые действия").font(.headline)
                Spacer()
                if !adding { Button { adding = true } label: { Image(systemName: "plus") } }
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
                    Button("Отмена") { reset() }
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
                ScrollView {
                    LazyVGrid(columns: [.init(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(store.state.actions) { action in
                            Button { store.runAction(action) } label: {
                                VStack(spacing: 12) {
                                    QuickActionIcon(action: action).frame(width: 44, height: 44)
                                    Text(action.title).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(2).multilineTextAlignment(.center)
                                }.frame(maxWidth: .infinity, minHeight: 96).padding(16)
                                    .islandCard()
                            }.buttonStyle(IslandButtonStyle(.bare)).contextMenu { Button("Удалить действие", role: .destructive) { store.removeAction(action.id) } }
                        }
                    }
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
