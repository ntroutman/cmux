import CmuxSettings
import Foundation
import Testing

@testable import CmuxSettingsUI

/// A `DefaultsValueModel` subscribes only once `startObserving()` runs, so a
/// section model left out of `startObservingSettings()` silently ignores
/// cmux.json reloads and other external writes while Settings is open.
@MainActor
@Suite struct WorkspaceColorsSectionObservationTests {
    @Test func externalAutoColorWriteUpdatesTheOpenRow() async throws {
        let suiteName = "workspace-colors-section-observation-\(UUID().uuidString)"
        // A second handle on the same suite plays the external writer (a
        // cmux.json reload or `defaults write`), separate from the store's own.
        let externalDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { externalDefaults.removePersistentDomain(forName: suiteName) }
        let catalog = SettingCatalog()
        let section = WorkspaceColorsSection(
            defaultsStore: Self.makeDefaultsStore(suiteName: suiteName),
            jsonStore: JSONConfigStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("workspace-colors-section-\(UUID().uuidString).json")
            ),
            catalog: catalog,
            errorLog: SettingsErrorLog()
        )
        section.startObservingSettings()
        let model = section.autoColor
        #expect(model.current == .off)

        externalDefaults.set(WorkspaceAutoColorMode.worktree.rawValue, forKey: catalog.workspaceColors.autoColor.userDefaultsKey)

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.current != .worktree, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(model.current == .worktree)
    }

    private nonisolated static func makeDefaultsStore(suiteName: String) -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
    }
}
