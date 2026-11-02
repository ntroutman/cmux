import CmuxFoundation
import Foundation
import Observation

/// Drives the inline validity message under the Markdown Viewer Theme field.
///
/// The field commits (Return / focus loss), not every keystroke, so the model
/// runs one synchronous host resolution per commit and keeps the message the
/// field shows. A `.valid`, empty, or `.unavailable` outcome shows no message:
/// an unavailable resolver (previews, package-only hosts) must not read as an
/// error, and an unverifiable name should not block the user.
@MainActor
@Observable
final class MarkdownThemeValidationModel {
    private let hostActions: SettingsHostActions
    /// Localized template with a single `%@` for the resolver's reason.
    private let invalidTemplate: String

    private(set) var validationMessage: String?

    init(hostActions: SettingsHostActions, invalidTemplate: String) {
        self.hostActions = hostActions
        self.invalidTemplate = invalidTemplate
    }

    /// Resolves `rawValue` on the host and updates ``validationMessage``.
    func validate(_ rawValue: String) {
        switch hostActions.validateMarkdownThemeName(rawValue) {
        case .valid, .unavailable:
            validationMessage = nil
        case let .invalid(message):
            validationMessage = String(format: invalidTemplate, message)
        }
    }

    /// Clears the message without running the resolver (used when the field is
    /// cleared to follow the terminal).
    func clear() {
        validationMessage = nil
    }
}
