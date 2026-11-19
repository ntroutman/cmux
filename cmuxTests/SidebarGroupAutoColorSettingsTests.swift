import CmuxFoundation
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// cmux.json plumbing and snapshot projection for `sidebar.groupAutoColor`.
/// The real settings file store must import it into the
/// `sidebarGroupAutoColor` defaults the app reads, and the row settings
/// snapshot must carry the automatic palette itself: the sidebar republishes
/// only when the rebuilt snapshot differs, so a palette edit has to change it.
/// Models `SidebarGroupDividersSettingsTests`.
///
/// Each case uses a private defaults suite. The test host runs the app, whose
/// live store re-applies `~/.config/cmux/cmux.json` on every defaults change
/// and removes from `.standard` the managed keys it doesn't own.
@Suite("Sidebar group automatic colors settings", .serialized)
struct SidebarGroupAutoColorSettingsTests {
    private static let groupAutoColorKey = "sidebarGroupAutoColor"

    // MARK: - Settings file

    @Test
    func turnsGroupAutoColorOff() throws {
        try loadSettingsFile(
            """
            {
              "sidebar": {
                "groupAutoColor": false
              }
            }
            """
        ) { defaults in
            #expect(defaults.object(forKey: Self.groupAutoColorKey) as? Bool == false)
            #expect(!SidebarTabItemSettingsSnapshot(defaults: defaults).autoColorsGroups)
        }
    }

    @Test
    func turnsGroupAutoColorOn() throws {
        try loadSettingsFile(
            """
            {
              "sidebar": {
                "groupAutoColor": true
              }
            }
            """
        ) { defaults in
            #expect(defaults.object(forKey: Self.groupAutoColorKey) as? Bool == true)
            #expect(SidebarTabItemSettingsSnapshot(defaults: defaults).autoColorsGroups)
        }
    }

    @Test
    func staysOnWhenTheFileDoesNotMentionIt() throws {
        try loadSettingsFile("{}") { defaults in
            #expect(defaults.object(forKey: Self.groupAutoColorKey) == nil)
            #expect(SidebarTabItemSettingsSnapshot(defaults: defaults).autoColorsGroups)
        }
    }

    @Test
    func jsonKeyMapsToTheDefaultsKey() {
        let mapping = SidebarSettingsFileMapping.booleanSettings.first { $0.jsonKey == "groupAutoColor" }
        #expect(mapping?.defaultsKey == Self.groupAutoColorKey)
        #expect(SidebarWorkspaceDetailDefaults.groupAutoColorKey == Self.groupAutoColorKey)
    }

    @Test
    func embeddedSchemaDeclaresThePathWithDefaultOn() {
        let lookup = CmuxConfigSchemaPathLookup()
        #expect(lookup.isDeclared(["sidebar", "groupAutoColor"]))
        #expect((lookup.defaultValue(at: ["sidebar", "groupAutoColor"]) as? NSNumber)?.boolValue == true)
    }

    // MARK: - Automatic palette

    @Test
    func paletteIsTheStockColorsInBuiltInOrder() throws {
        try withDefaults { defaults in
            let palette = SidebarTabItemSettingsSnapshot(defaults: defaults).groupAutoColorPalette
            #expect(palette == WorkspaceTabColorSettings.defaultPalette.map(\.hex))
        }
    }

    @Test
    func customEntriesStayOutOfThePalette() throws {
        try withDefaults { defaults in
            let before = SidebarTabItemSettingsSnapshot(defaults: defaults).groupAutoColorPalette
            let added = try #require(WorkspaceTabColorSettings.addCustomColor("#123456", defaults: defaults))
            #expect(WorkspaceTabColorSettings.customPaletteEntries(defaults: defaults).map(\.hex) == [added])
            #expect(SidebarTabItemSettingsSnapshot(defaults: defaults).groupAutoColorPalette == before)
        }
    }

    @Test
    func builtInsRecoloredToOneHexCollapseToOneSlot() throws {
        try withDefaults { defaults in
            WorkspaceTabColorSettings.setColor(named: "Red", hex: "#1565C0", defaults: defaults)
            let palette = SidebarTabItemSettingsSnapshot(defaults: defaults).groupAutoColorPalette
            #expect(palette.count == WorkspaceTabColorSettings.defaultPalette.count - 1)
            #expect(palette.first == "#1565C0")
            #expect(palette.filter { $0 == "#1565C0" }.count == 1)
            #expect(Set(palette).count == palette.count)
        }
    }

    @Test
    func removedBuiltInShrinksThePalette() throws {
        try withDefaults { defaults in
            WorkspaceTabColorSettings.removeColor(named: "Teal", defaults: defaults)
            let palette = SidebarTabItemSettingsSnapshot(defaults: defaults).groupAutoColorPalette
            #expect(palette.count == WorkspaceTabColorSettings.defaultPalette.count - 1)
            #expect(!palette.contains("#006B6B"))
        }
    }

    @Test
    func paletteIsEmptyWhenTheSettingIsOff() throws {
        try withDefaults { defaults in
            defaults.set(false, forKey: Self.groupAutoColorKey)
            #expect(SidebarTabItemSettingsSnapshot(defaults: defaults).groupAutoColorPalette.isEmpty)
        }
    }

    // MARK: - Invalidation

    @Test
    func paletteEditChangesTheSnapshotOnlyWhileTheSettingIsOn() throws {
        try withDefaults { defaults in
            let onBefore = SidebarTabItemSettingsSnapshot(defaults: defaults)
            WorkspaceTabColorSettings.setColor(named: "Blue", hex: "#2E86DE", defaults: defaults)
            #expect(SidebarTabItemSettingsSnapshot(defaults: defaults) != onBefore)

            defaults.set(false, forKey: Self.groupAutoColorKey)
            let offBefore = SidebarTabItemSettingsSnapshot(defaults: defaults)
            WorkspaceTabColorSettings.setColor(named: "Blue", hex: "#1565C0", defaults: defaults)
            #expect(SidebarTabItemSettingsSnapshot(defaults: defaults) == offBefore)
        }
    }

    // MARK: - Helpers

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "cmux-group-auto-color-palette-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func loadSettingsFile(_ contents: String, verify: (UserDefaults) -> Void) throws {
        let suite = "cmux-group-auto-color-settings-\(UUID().uuidString)"
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

        _ = KeyboardShortcutSettingsFileStore(
            primaryPath: settingsFileURL.path,
            fallbackPath: nil,
            additionalFallbackPaths: [],
            notificationCenter: NotificationCenter(),
            userDefaults: defaults,
            startWatching: false
        )

        verify(defaults)
    }
}
