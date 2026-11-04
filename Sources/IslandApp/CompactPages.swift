import AppKit
import SwiftUI
import IslandCore

struct CompactPageBar: View {
    @Binding var page: Int
    var count: Int
    var id: String
    var body: some View {
        HStack(spacing: 10) {
            Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left").frame(width: 25, height: 20) }
                .disabled(page <= 0).accessibilityLabel("Предыдущая страница")
                .recordingTarget("Страница:" + id + ":назад")
            Text("\(min(page + 1, count)) / \(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(IslandPalette.secondary)
            Button { page = min(count - 1, page + 1) } label: { Image(systemName: "chevron.right").frame(width: 25, height: 20) }
                .disabled(page >= count - 1).accessibilityLabel("Следующая страница")
                .recordingTarget("Страница:" + id + ":вперёд")
        }.buttonStyle(IslandButtonStyle(.bare)).frame(maxWidth: .infinity).frame(height: 22)
    }
}

struct CompactList<Item: Identifiable, Row: View>: View {
    var items: [Item]
    var rowHeight: CGFloat
    var id: String
    @ViewBuilder var row: (Item) -> Row
    @State private var page = 0
    var body: some View {
        GeometryReader { geometry in
            let capacity = max(1, Int((geometry.size.height - 26) / (rowHeight + 5)))
            let count = ContentPages.count(items: items.count, capacity: capacity)
            let range = ContentPages.range(items: items.count, capacity: capacity, page: page)
            VStack(spacing: 5) {
                ForEach(Array(items[range])) { item in row(item).frame(height: rowHeight) }
                Spacer(minLength: 0)
                if count > 1 { CompactPageBar(page: $page, count: count, id: id) }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .onChange(of: count) { _, value in page = min(page, value - 1) }
                .onChange(of: items.map(\.id)) { _, _ in page = min(page, count - 1) }
        }
    }
}

@MainActor
struct CompactText: View {
    var text: String
    var id: String
    var monospaced = false
    @State private var page = 0
    @State private var pages: [String] = [""]
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 3) {
                Text(pages[min(page, pages.count - 1)]).font(.system(size: 11, design: monospaced ? .monospaced : .default))
                    .textSelection(.enabled).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if pages.count > 1 { CompactPageBar(page: $page, count: pages.count, id: id) }
            }.task(id: text + "|" + String(Int(geometry.size.width)) + ":" + String(Int(geometry.size.height))) {
                pages = Self.paginate(text, width: geometry.size.width, height: max(15, geometry.size.height - 28), monospaced: monospaced)
                page = min(page, pages.count - 1)
            }
        }
    }
    static func paginate(_ text: String, width: CGFloat, height: CGFloat, monospaced: Bool) -> [String] {
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 11)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        var result: [String] = [], remaining = text[...]
        while !remaining.isEmpty {
            var low = 1, high = min(remaining.count, max(32, Int(width / 4 * height / 10)))
            while low < high {
                let middle = (low + high + 1) / 2
                let sample = String(remaining.prefix(middle))
                let measured = NSAttributedString(string: sample, attributes: attributes).boundingRect(
                    with: NSSize(width: max(20, width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
                if measured <= height - 2 { low = middle } else { high = middle - 1 }
            }
            result.append(String(remaining.prefix(low))); remaining = remaining.dropFirst(low)
        }
        return result.isEmpty ? [""] : result
    }
}
