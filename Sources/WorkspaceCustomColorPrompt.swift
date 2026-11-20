import AppKit

/// The one custom-color dialog, shared by the SwiftUI and AppKit sidebar rows
/// for workspaces ("Custom Workspace Color") and groups ("Custom Group Color").
/// A hex value has no inline or palette editor, so this stays an alert; an
/// invalid entry is explained in a follow-up alert.
@MainActor
enum WorkspaceCustomColorPrompt {
    /// Asks for a workspace's hex color and adds it to the custom palette.
    ///
    /// - Parameters:
    ///   - currentHex: The workspace's current color, used as the initial text.
    ///   - presentingWindow: The window the alert attaches to.
    /// - Returns: The normalized `#RRGGBB` value, or nil when the user cancels
    ///   or enters an invalid color.
    static func run(currentHex: String?, presentingWindow: NSWindow?) -> String? {
        run(
            title: String(localized: "alert.customColor.title", defaultValue: "Custom Workspace Color"),
            currentHex: currentHex,
            presentingWindow: presentingWindow
        )
    }

    /// Asks for a workspace group's hex color and adds it to the shared custom
    /// palette; identical to ``run(currentHex:presentingWindow:)`` apart from
    /// the title.
    ///
    /// - Parameters:
    ///   - currentHex: The group's manual color, used as the initial text.
    ///   - presentingWindow: The window the alert attaches to.
    /// - Returns: The normalized `#RRGGBB` value, or nil when the user cancels
    ///   or enters an invalid color.
    static func runForGroup(currentHex: String?, presentingWindow: NSWindow?) -> String? {
        run(
            title: String(localized: "alert.customGroupColor.title", defaultValue: "Custom Group Color"),
            currentHex: currentHex,
            presentingWindow: presentingWindow
        )
    }

    private static func run(title: String, currentHex: String?, presentingWindow: NSWindow?) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(localized: "alert.customColor.message", defaultValue: "Enter a hex color in the format #RRGGBB.")
        let seed = currentHex ?? WorkspaceTabColorSettings.customPaletteEntries().first?.hex ?? ""
        let input = NSTextField(string: seed)
        input.placeholderString = "#1565C0"
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = input
        alert.addButton(withTitle: String(localized: "alert.customColor.apply", defaultValue: "Apply"))
        alert.addButton(withTitle: String(localized: "alert.customColor.cancel", defaultValue: "Cancel"))
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = input
        let response = alert.runCmuxModal(presentingWindow: presentingWindow) { _ in
            alertWindow.makeFirstResponder(input)
            input.selectText(nil)
        }
        guard response == .alertFirstButtonReturn else { return nil }
        guard let normalized = WorkspaceTabColorSettings.addCustomColor(input.stringValue) else {
            showInvalidColorAlert(input.stringValue, presentingWindow: presentingWindow)
            return nil
        }
        return normalized
    }

    private static func showInvalidColorAlert(_ value: String, presentingWindow: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "alert.invalidColor.title", defaultValue: "Invalid Color")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            alert.informativeText = String(localized: "alert.invalidColor.emptyMessage", defaultValue: "Enter a hex color in the format #RRGGBB.")
        } else {
            alert.informativeText = String(
                format: String(localized: "alert.invalidColor.invalidMessage", defaultValue: "\"%@\" is not a valid hex color. Use #RRGGBB."),
                trimmed
            )
        }
        alert.addButton(withTitle: String(localized: "alert.invalidColor.ok", defaultValue: "OK"))
        _ = alert.runCmuxModal(presentingWindow: presentingWindow)
    }
}
