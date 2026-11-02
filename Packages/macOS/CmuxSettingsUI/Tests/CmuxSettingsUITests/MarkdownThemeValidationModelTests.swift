import Foundation
import Testing
@testable import CmuxSettingsUI

/// The Markdown Viewer Theme row reaches the host resolver, and the
/// protocol-extension default reports validation unavailable rather than
/// silently valid (spec `docs/superpowers/specs/2026-10-23-markdown-viewer-theme-design.md`,
/// "Validation rules").
@MainActor
@Suite("Markdown theme validation")
struct MarkdownThemeValidationModelTests {
    /// Returns whatever outcome it is handed, so a test can prove the row model
    /// reaches the host rather than the protocol default.
    final class StubHostActions: SettingsHostActions {
        var outcome: MarkdownThemeValidation
        private(set) var validatedValues: [String] = []

        init(outcome: MarkdownThemeValidation) {
            self.outcome = outcome
        }

        func validateMarkdownThemeName(_ rawValue: String) -> MarkdownThemeValidation {
            validatedValues.append(rawValue)
            return outcome
        }

        // Only the stubs the tests exercise; the rest come from the protocol
        // extension defaults.
        func clearBrowserHistory() {}
        func openConfigInExternalEditor() {}
        func sendFeedback() {}
        func sendTestNotification() {}
        func openSystemNotificationSettings() {}
        func restartApp() {}
        func openBrowserImportFlow() {}
        func requestNotificationAuthorization() {}
        func openTerminalConfigWindow() {}
        func previewNotificationSound(value: String, customFilePath: String) {}
    }

    /// A host that does not override validation: the method must come from the
    /// protocol extension and report unavailable.
    final class DefaultHostActions: SettingsHostActions {
        func clearBrowserHistory() {}
        func openConfigInExternalEditor() {}
        func sendFeedback() {}
        func sendTestNotification() {}
        func openSystemNotificationSettings() {}
        func restartApp() {}
        func openBrowserImportFlow() {}
        func requestNotificationAuthorization() {}
        func openTerminalConfigWindow() {}
        func previewNotificationSound(value: String, customFilePath: String) {}
    }

    @Test func protocolDefaultReportsUnavailable() {
        let host = DefaultHostActions()
        #expect(host.validateMarkdownThemeName("Catppuccin Latte") == .unavailable)
    }

    @Test func invalidOutcomeSurfacesMessageOnRowModel() {
        let host = StubHostActions(outcome: .invalid(message: "Unknown theme “NoSuchTheme”"))
        let model = MarkdownThemeValidationModel(hostActions: host, invalidTemplate: "Invalid: %@")

        model.validate("NoSuchTheme")

        #expect(host.validatedValues == ["NoSuchTheme"])
        #expect(model.validationMessage == "Invalid: Unknown theme “NoSuchTheme”")
    }

    @Test func validOutcomeClearsMessage() {
        let host = StubHostActions(outcome: .invalid(message: "boom"))
        let model = MarkdownThemeValidationModel(hostActions: host, invalidTemplate: "Invalid: %@")
        model.validate("bad")
        #expect(model.validationMessage != nil)

        host.outcome = .valid
        model.validate("Catppuccin Latte")
        #expect(model.validationMessage == nil)
    }

    @Test func unavailableOutcomeShowsNoMessage() {
        let host = StubHostActions(outcome: .unavailable)
        let model = MarkdownThemeValidationModel(hostActions: host, invalidTemplate: "Invalid: %@")
        model.validate("anything")
        #expect(model.validationMessage == nil)
    }
}
