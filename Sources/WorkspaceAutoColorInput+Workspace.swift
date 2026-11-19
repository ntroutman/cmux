import Foundation

extension WorkspaceAutoColorInput {
    /// Reads only published workspace state, so building an input never touches
    /// the filesystem; the project root comes from the workspace's own discovery.
    @MainActor
    init(workspace: Workspace) {
        self.init(
            stableId: workspace.stableId,
            currentDirectory: workspace.currentDirectory,
            projectRootPath: workspace.extensionSidebarProjectRootPath,
            groupId: workspace.groupId,
            isLocal: !workspace.usesRemoteDirectoryProvenance
        )
    }
}
