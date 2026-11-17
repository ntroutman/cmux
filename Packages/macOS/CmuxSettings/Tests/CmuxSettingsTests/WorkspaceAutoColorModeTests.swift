import Foundation
import Testing
@testable import CmuxSettings

@Suite("WorkspaceAutoColorMode")
struct WorkspaceAutoColorModeTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "cmux-auto-color-mode-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func stringsDecodeByRawValue() {
        #expect(WorkspaceAutoColorMode.decodeFromUserDefaults("off") == .off)
        #expect(WorkspaceAutoColorMode.decodeFromUserDefaults("worktree") == .worktree)
        #expect(WorkspaceAutoColorMode.decodeFromJSON("off") == .off)
        #expect(WorkspaceAutoColorMode.decodeFromJSON("worktree") == .worktree)
        for mode in WorkspaceAutoColorMode.allCases {
            #expect(mode.encodeForUserDefaults() as? String == mode.rawValue)
            #expect(mode.encodeForJSON() as? String == mode.rawValue)
        }
    }

    @Test func unknownValuesDecodeAsNil() {
        #expect(WorkspaceAutoColorMode.decodeFromUserDefaults("branch") == nil)
        #expect(WorkspaceAutoColorMode.decodeFromJSON("branch") == nil)
        #expect(WorkspaceAutoColorMode.decodeFromJSON(NSNumber(value: true)) == nil)
    }

    @Test func keyDefaultsToOffAndIgnoresUnknownStoredValues() throws {
        let defaults = try makeDefaults()
        let client = UserDefaultsSettingsClient(defaults: defaults)
        let key = SettingCatalog().workspaceColors.autoColor

        #expect(key.id == "workspaceColors.autoColor")
        #expect(key.userDefaultsKey == "workspaceColorsAutoColor")
        #expect(client.value(for: key) == .off)

        defaults.set("worktree", forKey: key.userDefaultsKey)
        #expect(client.value(for: key) == .worktree)

        defaults.set("rainbow", forKey: key.userDefaultsKey)
        #expect(client.value(for: key) == .off)

        client.set(.worktree, for: key)
        #expect(defaults.string(forKey: key.userDefaultsKey) == "worktree")
    }
}
