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
                TextField("Название кнопки", text: $title).textFieldStyle(.roundedBorder)
                Picker("Тип", selection: $kind) { ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                if kind == .shortcut {
                    TextField("Точное имя из «Быстрых команд»", text: $target).textFieldStyle(.roundedBorder)
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
                    }.buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if store.state.actions.isEmpty {
                EmptyState(icon: "bolt.fill", title: "Ваши частые действия", detail: "Добавьте приложения, папки и команды — они будут доступны в одном месте.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        ForEach(store.state.actions) { action in
                            Button { store.runAction(action) } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    Image(systemName: action.kind == .folder ? "folder.fill" : action.kind == .shortcut ? "bolt.fill" : "app.fill").font(.title2).foregroundStyle(accent)
                                    Text(action.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                }.frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).padding(14)
                                    .islandCard()
                            }.buttonStyle(.plain).contextMenu { Button("Удалить действие", role: .destructive) { store.removeAction(action.id) } }
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
        panel.canChooseDirectories = kind == .folder; panel.canChooseFiles = kind == .application
        panel.allowsMultipleSelection = false
        if kind == .application { panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        if panel.runModal() == .OK, let url = panel.url {
            target = url.path
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        }
    }
}
