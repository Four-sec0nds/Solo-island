import Foundation

public enum ContentPages {
    public static func count(items: Int, capacity: Int) -> Int { max(1, (max(0, items) + max(1, capacity) - 1) / max(1, capacity)) }
    public static func range(items: Int, capacity: Int, page: Int) -> Range<Int> {
        let capacity = max(1, capacity), total = max(0, items)
        let selected = min(count(items: total, capacity: capacity) - 1, max(0, page))
        let lower = min(total, selected * capacity)
        return lower..<min(total, lower + capacity)
    }
}
