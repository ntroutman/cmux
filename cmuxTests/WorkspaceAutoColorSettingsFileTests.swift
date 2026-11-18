import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// cmux.json plumbing for `workspaceColors.autoColor`: the real settings file
/// store must import a known mode into the defaults key the catalog reads,
/// reject an unknown mode with an issue naming the path, and the template must
/// carry the key with its default.
///
/// Each case loads into a private defaults suite. The test host runs the app,
/// whose live store re-applies `~/.config/cmux/cmux.json` on every defaults
/// change and removes from `.standard` the managed keys it doesn't own.
/// Main-actor isolated because building the template reads main-actor state.
@MainActor
@Suite("Workspace auto color settings file", .serialized)
struct WorkspaceAutoColorSettingsFileTests {
    private static let key = SettingCatalog().workspaceColors.autoColor

    @Test
    func worktreeModeResolvesFromTheFile() throws {
        try loadSettingsFile(
            """
            {
              "workspaceColors": {
                "autoColor": "worktree"
              }
            }
            """
        ) { defaults, store in
            #expect(defaults.string(forKey: Self.key.userDefaultsKey) == "worktree")
            #expect(UserDefaultsSettingsClient(defaults: defaults).value(for: Self.key) == .worktree)
            #expect(store.configurationIssues.isEmpty)
        }
    }

    @Test
    func unknownModeLeavesOffAndLogsTheInvalidPath() throws {
        try loadSettingsFile(
            """
            {
              "workspaceColors": {
                "autoColor": "rainbow",
                "notificationBadgeColor": "#ff0000"
              }
            }
            """
        ) { defaults, store in
            #expect(defaults.object(forKey: Self.key.userDefaultsKey) == nil)
            #expect(UserDefaultsSettingsClient(defaults: defaults).value(for: Self.key) == .off)
            #expect(store.configurationIssues.contains { $0.contains("invalid value for workspaceColors.autoColor") })
            // An invalid autoColor must not abandon the rest of the section, so
            // the probe is a key the parser reaches only after autoColor.
            let badgeColor = SettingCatalog().workspaceColors.notificationBadgeColorHex
            #expect(defaults.string(forKey: badgeColor.userDefaultsKey) == "#FF0000")
        }
    }

    @Test
    func templateWritesTheKeyWithItsDefault() throws {
        let templateLine = try #require(
            CmuxSettingsFileStore.defaultTemplate().split(separator: "\n").first {
                $0.contains("\"autoColor\"")
            }
        ).trimmingCharacters(in: .whitespaces)
        #expect(templateLine.hasPrefix("//"))
        var entryJSON = String(templateLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if entryJSON.hasSuffix(",") {
            entryJSON.removeLast()
        }
        let entry = try #require(
            JSONSerialization.jsonObject(with: Data("{\(entryJSON)}".utf8)) as? [String: Any]
        )
        #expect(entry["autoColor"] as? String == "off")
    }

    private func loadSettingsFile(
        _ contents: String,
        verify: (UserDefaults, KeyboardShortcutSettingsFileStore) -> Void
    ) throws {
        let suite = "cmux-auto-color-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            suite,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let settingsFileURL = directoryURL.appendingPathComponent("cmux.json", isDirectory: false)
        try contents.write(to: settingsFileURL, atomically: true, encoding: .utf8)

        let store = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            additionalFallbackPaths: [],
            notificationCenter: NotificationCenter(),
            userDefaults: defaults,
            startWatching: false
        )

        verify(defaults, store)
    }
}
