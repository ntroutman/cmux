import Foundation

/// Turns an automatic-color key into a color.
protocol WorkspaceAutoColorAssigning: Sendable {
    /// Must be pure: the same key yields the same hex in every process, so a
    /// workspace keeps its color across launches. Nil means no color.
    func colorHex(forKey key: String) -> String?
}
