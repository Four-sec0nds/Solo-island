import AppKit
import SwiftUI
import IslandCore

@MainActor
struct FilesView: View {
    @ObservedObject var store: IslandStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Файловая полка").font(.headline)
                    Text("Последние 5 файлов · копируйте или перетаскивайте сюда").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.pickFiles() } label: { Image(systemName: "plus") }.buttonStyle(.bordered).help("Добавить файлы")
            }
            if store.state.shelf.isEmpty {
                EmptyState(icon: "tray.and.arrow.down", title: "Файлы под рукой", detail: "Скопируйте файл в Finder через ⌘C или перетащите его на островок. Затем заберите его отсюда в нужное приложение.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.state.shelf) { entry in
                            fileRow(entry)
                        }
                    }
                }
            }
            Text("Оригиналы остаются на своих местах. Полка хранит ссылки на файлы.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func fileRow(_ entry: ShelfEntry) -> some View {
        let exists = FileManager.default.fileExists(atPath: entry.path)
        return HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(exists ? entry.url.deletingLastPathComponent().lastPathComponent : "Файл перемещён или удалён")
                    .font(.system(size: 10)).foregroundStyle(exists ? .secondary : .orange).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { store.openFile(entry) } label: { Image(systemName: "arrow.up.right.square") }.disabled(!exists).help("Открыть файл")
            Button { store.removeFile(entry.id) } label: { Image(systemName: "xmark") }.help("Убрать с полки")
        }.buttonStyle(.plain).padding(11).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .onDrag { exists ? NSItemProvider(contentsOf: entry.url) ?? NSItemProvider() : NSItemProvider() }
            .onTapGesture(count: 2) { store.openFile(entry) }
            .contextMenu {
                Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }.disabled(!exists)
                Button("Скопировать файл") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([entry.url as NSURL])
                }.disabled(!exists)
                Button("Убрать с полки") { store.removeFile(entry.id) }
            }
    }
}
