import Foundation

/// Picks the string an automatic workspace color derives from. Workspaces that
/// share a key share a color.
protocol WorkspaceAutoColorKeyProviding: Sendable {
    /// Returns nil when the workspace should get no automatic color.
    func key(for input: WorkspaceAutoColorInput) -> String?
}
