import Foundation

/// Keys a workspace by its project root, so every workspace in one worktree
/// shares a color however deep its cwd sits.
struct WorktreeDirectoryKeyProvider: WorkspaceAutoColorKeyProviding {
    func key(for input: WorkspaceAutoColorInput) -> String? {
        // A remote workspace can keep a root that was published while it was
        // still local (a remote-tmux mirror is flagged after creation), and that
        // root names a directory on this Mac, not the one the workspace shows.
        guard input.isLocal else { return nil }
        return input.projectRootPath
    }
}
