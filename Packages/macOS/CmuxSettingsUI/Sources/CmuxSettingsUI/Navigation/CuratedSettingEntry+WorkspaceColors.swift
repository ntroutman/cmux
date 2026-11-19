import Foundation

extension Array where Element == CuratedSettingEntry {
    /// `leading`, then ``workspaceColorsEntries``, then `trailing`. Like
    /// ``insertingBrowserMemorySaverEntries(between:and:)``, a call rather
    /// than `+` keeps the contextual type of ``cmuxDefault(catalog:)``'s large
    /// literals concrete.
    static func insertingWorkspaceColorsEntries(
        between leading: [CuratedSettingEntry],
        and trailing: [CuratedSettingEntry]
    ) -> [CuratedSettingEntry] {
        leading + workspaceColorsEntries + trailing
    }

    /// Search entries for the rows in Settings > Workspace Colors, in row order.
    static var workspaceColorsEntries: [CuratedSettingEntry] {
        [
            .init(section: .workspaceColors, id: "indicator", title: String(localized: "settings.workspaceColors.indicator", defaultValue: "Workspace Color Indicator"), synonyms: "Workspace Color Indicator workspaceColors.indicatorStyle tab indicator active workspace style color stripe dot"),
            .init(
                section: .workspaceColors,
                id: "auto-color",
                title: String(localized: "settings.workspaceColors.autoColor", defaultValue: "Automatic Colors"),
                detailText: String(localized: "settings.workspaceColors.autoColor.subtitle", defaultValue: "Workspaces without a chosen color take one from their git worktree. A chosen color always wins, and workspaces outside a git repository stay uncolored."),
                paths: ["workspaceColors.autoColor"],
                synonyms: "workspaceColors.autoColor auto color automatic colors automatic workspace color worktree color git repository repo hash distinct by worktree"
            ),
            .init(section: .workspaceColors, id: "subtle-selection", title: String(localized: "settings.workspaceColors.subtleSelection", defaultValue: "Subtle Selection Highlight"), synonyms: "Subtle Selection Highlight workspaceColors.subtleSelection subtle calm quiet selection highlight tint hairline edge selected workspace accent"),
            .init(section: .workspaceColors, id: "brighten-dark-mode", title: String(localized: "settings.workspaceColors.brightenInDarkMode", defaultValue: "Brighten Colors in Dark Mode"), synonyms: "Brighten Colors in Dark Mode workspaceColors.brightenInDarkMode brighten lighten dark mode workspace colors fill dim muted exact color"),
            .init(section: .workspaceColors, id: "unselected-fill-opacity", title: String(localized: "settings.workspaceColors.unselectedFillOpacity", defaultValue: "Unselected Fill Opacity"), synonyms: "Unselected Fill Opacity workspaceColors.unselectedFillOpacity opacity transparency alpha solid fill unselected inactive workspace row color dull faded strength"),
            .init(section: .workspaceColors, id: "selection", title: String(localized: "settings.workspaceColors.selectionColor", defaultValue: "Selection Highlight"), synonyms: "Selection Highlight workspaceColors.selectionColor selected workspace color highlight background active tab"),
            .init(section: .workspaceColors, id: "badge", title: String(localized: "settings.workspaceColors.notificationBadgeColor", defaultValue: "Notification Badge"), synonyms: "Notification Badge workspaceColors.notificationBadgeColor unread notification badge color dot count"),
            .init(
                section: .workspaceColors,
                id: "pane-flash-color",
                title: String(localized: "settings.workspaceColors.paneFlashColor", defaultValue: "Pane Flash"),
                detailText: String(localized: "settings.workspaceColors.paneFlashColor.subtitle", defaultValue: "Color of the attention ring and pane flash when a pane needs input."),
                paths: ["notifications.paneFlashColor"],
                synonyms: "notifications.paneFlashColor attention ring pane flash color unread needs input"
            ),
            .init(section: .workspaceColors, id: "palette", title: String(localized: "settings.workspaceColors.resetPalette", defaultValue: "Reset Palette"), synonyms: "Reset Palette reset palette named colors restore built-in custom remove default")
        ]
    }
}
