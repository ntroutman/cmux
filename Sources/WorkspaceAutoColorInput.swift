import Foundation

/// The workspace facts an automatic color strategy may read, as plain values so
/// strategies stay pure and never reach into `Workspace`.
struct WorkspaceAutoColorInput: Equatable, Sendable {
    var stableId: UUID
    var currentDirectory: String
    /// The nearest enclosing directory holding a `.git` entry, which for a linked
    /// worktree is the worktree itself; nil until discovery finishes or when none exists.
    var projectRootPath: String?
    var groupId: UUID?
    /// False for SSH, remote-tmux-mirror and Cloud workspaces, whose directories
    /// describe another machine.
    var isLocal: Bool
}
