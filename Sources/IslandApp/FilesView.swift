import AppKit
import SwiftUI
import IslandCore
import ImageIO

@MainActor
struct FilesView: View {
    @ObservedObject var store: IslandStore
    @Environment(\.islandAccent) private var accent
    @State private var filter = ShelfFilter.all
    @State private var preview: ShelfEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let preview {
                HStack {
                    Button { self.preview = nil } label: { Label("Назад", systemImage: "chevron.left") }
                    Spacer()
                    Button("Скопировать") { store.copyEntry(preview) }.buttonStyle(.borderedProminent)
                }.buttonStyle(.plain)
                ScrollView { Text(preview.text ?? "").font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                    .islandCard()
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Всё нужное — рядом").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("Файлы, текст и скриншоты из буфера обмена").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button { store.captureClipboardNow() } label: { Image(systemName: "doc.on.clipboard").frame(width: 24, height: 26) }
                        .buttonStyle(.plain).help("Добавить текущий буфер обмена")
                    Button { store.pickFiles() } label: { Image(systemName: "plus").frame(width: 24, height: 26) }
                        .buttonStyle(.plain).help("Добавить файлы")
                }
                Picker("Показать", selection: $filter) {
                    ForEach(ShelfFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                let entries = store.state.shelf.filter { filter.kind == nil || $0.kind == filter.kind }
                if entries.isEmpty {
                    EmptyState(icon: "square.on.square", title: "Место для важного", detail: "Скопируйте текст или файл, сделайте скриншот в буфер либо перетащите его сюда. История останется после перезапуска.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) { ForEach(entries) { entry in entryRow(entry) } }
                        .padding(1)
                    }
                }
                Label("Скриншоты закреплены и хранятся до удаления", systemImage: "pin.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private func entryRow(_ entry: ShelfEntry) -> some View {
        let exists = entry.kind == .text || FileManager.default.fileExists(atPath: entry.path)
        return HStack(spacing: 12) {
            ShelfPreview(entry: entry).frame(width: 62, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(title(entry)).font(.system(size: 12, weight: .medium)).lineLimit(entry.kind == .text ? 2 : 1).truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(subtitle(entry, exists: exists)).lineLimit(1)
                    if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(accent) }
                }.font(.system(size: 10)).foregroundStyle(exists ? Color.secondary : Color.orange)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                Button { store.copyEntry(entry) } label: { Image(systemName: "doc.on.doc").frame(width: 23) }.disabled(!exists).help("Скопировать")
                Button { store.toggleShelfPin(entry.id) } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin").frame(width: 23).foregroundStyle(entry.isPinned ? accent : Color.secondary)
                }.help(entry.isPinned ? "Открепить" : "Хранить до удаления")
            }
        }
        .buttonStyle(.plain).padding(12).islandCard(tint: entry.kind == .text ? .cyan : entry.kind == .image ? .pink : .purple)
        .onDrag {
            if entry.kind == .text { return NSItemProvider(object: (entry.text ?? "") as NSString) }
            return exists ? NSItemProvider(contentsOf: entry.url) ?? NSItemProvider() : NSItemProvider()
        }
        .onTapGesture(count: 2) {
            if entry.kind == .text { preview = entry } else { store.openFile(entry) }
        }
        .contextMenu {
            Button("Скопировать") { store.copyEntry(entry) }.disabled(!exists)
            Button(entry.kind == .text ? "Просмотреть текст" : "Открыть") {
                if entry.kind == .text { preview = entry } else { store.openFile(entry) }
            }.disabled(!exists)
            Button(entry.isPinned ? "Открепить" : "Закрепить") { store.toggleShelfPin(entry.id) }
            if entry.kind != .text { Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }.disabled(!exists) }
            Divider()
            Button("Удалить с полки", role: .destructive) { store.removeFile(entry.id) }
        }
    }
    private func title(_ entry: ShelfEntry) -> String {
        switch entry.kind {
        case .text: return String((entry.text ?? "").prefix(160))
        case .image: return "Скриншот / изображение"
        case .file: return entry.url.lastPathComponent
        }
    }
    private func subtitle(_ entry: ShelfEntry, exists: Bool) -> String {
        guard exists else { return "Файл перемещён или удалён" }
        switch entry.kind {
        case .text: return "Текст · \(entry.text?.count ?? 0) символов"
        case .image: return entry.addedAt.formatted(date: .abbreviated, time: .shortened)
        case .file: return entry.url.deletingLastPathComponent().lastPathComponent
        }
    }
}

private enum ShelfFilter: String, CaseIterable, Identifiable {
    case all = "Всё", files = "Файлы", text = "Текст", images = "Скрины"
    var id: String { rawValue }
    var kind: ShelfKind? {
        switch self { case .all: return nil; case .files: return .file; case .text: return .text; case .images: return .image }
    }
}
@MainActor
private struct ShelfPreview: View {
    var entry: ShelfEntry
    @State private var image: NSImage?
    var body: some View {
        Group {
            if entry.kind == .text {
                ZStack {
                    LinearGradient(colors: [.cyan.opacity(0.16), .blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "text.alignleft").font(.system(size: 22)).foregroundStyle(.cyan)
                }
            } else if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: entry.kind == .image ? .fill : .fit)
            } else { Image(systemName: "doc").font(.title2).foregroundStyle(.secondary) }
        }.frame(width: 62, height: 54).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task(id: entry.path) {
                if entry.kind == .image, let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
                   let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 180,
                    kCGImageSourceCreateThumbnailWithTransform: true
                   ] as CFDictionary) {
                    image = NSImage(cgImage: cgImage, size: .zero)
                } else if entry.kind == .file { image = NSWorkspace.shared.icon(forFile: entry.path) }
            }
    }
}
