import Foundation

/// One scale for the panel, settings and saved-layout migration.
public enum IslandLayout {
    public static let minimumWidth: Double = 520
    public static let defaultWidth: Double = 560
    public static let maximumWidth: Double = 680
    public static let bodyHeight: Double = 360
    public static let revision = 1
    public static func width(_ requested: Double) -> Double {
        requested.isFinite ? min(maximumWidth, max(minimumWidth, requested)) : defaultWidth
    }
}
