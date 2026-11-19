import CmuxSettings
import Foundation

/// Resolves a workspace's automatic color from the `workspaceColors.autoColor`
/// mode by composing a key strategy with a color assigner. Manual colors are the
/// caller's concern; this only answers what the automatic color would be.
struct WorkspaceAutoColorResolver: Sendable {
    let mode: WorkspaceAutoColorMode
    let keyProvider: any WorkspaceAutoColorKeyProviding
    let assigner: any WorkspaceAutoColorAssigning

    init(
        mode: WorkspaceAutoColorMode,
        keyProvider: any WorkspaceAutoColorKeyProviding,
        assigner: any WorkspaceAutoColorAssigning
    ) {
        self.mode = mode
        self.keyProvider = keyProvider
        self.assigner = assigner
    }

    /// The resolver for a mode with the shipped strategy and assigner. A new
    /// mode adds one case here and one key provider.
    static func make(mode: WorkspaceAutoColorMode) -> WorkspaceAutoColorResolver {
        let keyProvider: any WorkspaceAutoColorKeyProviding
        switch mode {
        // Off still needs a provider to hold, but `colorHex(for:)` returns before consulting it.
        case .off, .worktree:
            keyProvider = WorktreeDirectoryKeyProvider()
        }
        return WorkspaceAutoColorResolver(mode: mode, keyProvider: keyProvider, assigner: HashedPaletteAssigner())
    }

    func colorHex(for input: WorkspaceAutoColorInput) -> String? {
        guard mode != .off, let key = keyProvider.key(for: input) else { return nil }
        return assigner.colorHex(forKey: key)
    }
}
