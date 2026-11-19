import CmuxSettings
import Foundation

extension VerticalTabsSidebar {
    /// Color for a row with no manual color: the per-host origin color, else the
    /// automatic color. Both refresh paths read it here so they cannot drift: the
    /// keyed refresh replaces snapshots without consulting the presentation key,
    /// so a color computed only for the key would vanish on a routine update.
    func fallbackColorHex(for workspace: Workspace, mirrorDestinations: [UUID: String]?) -> String? {
        originColorHex(for: workspace, mirrorDestinations: mirrorDestinations)
            ?? WorkspaceAutoColorResolver.make(mode: workspaceAutoColorMode)
                .colorHex(for: WorkspaceAutoColorInput(workspace: workspace))
    }
}
