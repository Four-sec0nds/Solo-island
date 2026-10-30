/// Tracks actual hover edges while allowing the first entry after a Space/display
/// change to reveal immediately, even when the cursor has not moved.
public struct NotchHoverTracker: Sendable {
    public enum Change: Equatable, Sendable {
        case entered(immediately: Bool)
        case exited
    }
    private var inside: Bool? = false
    private var immediateNextEntry = false

    public init() {}

    public mutating func screenDidChange() {
        inside = nil
        immediateNextEntry = true
    }

    public mutating func update(isInside next: Bool) -> Change? {
        guard inside != next else { return nil }
        inside = next
        guard next else { return .exited }
        let immediate = immediateNextEntry
        immediateNextEntry = false
        return .entered(immediately: immediate)
    }
}
