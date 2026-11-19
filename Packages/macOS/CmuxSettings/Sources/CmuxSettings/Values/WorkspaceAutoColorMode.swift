import Foundation

/// Which workspace attribute, if any, derives an automatic color for a
/// workspace the user has not colored by hand. Later key strategies
/// (`workspace`, `branch`, `group`) would join as new cases; they are not
/// declared until they exist, so an unknown stored string falls back to the
/// key default instead of naming a strategy nothing implements.
public enum WorkspaceAutoColorMode: String, CaseIterable, Sendable, SettingCodable {
    case off, worktree

    /// Unknown strings return `nil` so the key default applies.
    public static func decodeFromUserDefaults(_ raw: Any?) -> WorkspaceAutoColorMode? {
        (raw as? String).flatMap(WorkspaceAutoColorMode.init(rawValue:))
    }

    public func encodeForUserDefaults() -> Any { rawValue }

    public static func decodeFromJSON(_ raw: Any?) -> WorkspaceAutoColorMode? {
        (raw as? String).flatMap(WorkspaceAutoColorMode.init(rawValue:))
    }

    public func encodeForJSON() -> Any { rawValue }
}
