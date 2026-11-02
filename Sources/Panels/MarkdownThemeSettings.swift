import Foundation

/// Ghostty theme name for the markdown viewer, chosen separately from the
/// terminal.
///
/// The stored value is a Ghostty theme name — a bare name, a conditional
/// `light:X,dark:Y`, or an absolute theme-file path — resolved through the same
/// loader a Ghostty `theme` directive uses. An empty or whitespace-only value
/// means "follow the terminal", which leaves the viewer byte-for-byte as it is
/// today. The name is accepted at parse time with no resolution; an
/// unresolvable name falls back to the terminal appearance at appearance-build
/// time rather than poisoning the settings snapshot.
enum MarkdownThemeSettings {
    /// UserDefaults / cmux.json key (`markdown.theme`).
    static let key = "markdown.theme"

    /// The persistent default theme name, honoring `markdown.theme` from
    /// UserDefaults / cmux.json. Returns `nil` for an unset, empty, or
    /// whitespace-only value (follow the terminal), the trimmed name otherwise.
    static func resolvedDefault(defaults: UserDefaults = .standard) -> String? {
        let trimmed = (defaults.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
