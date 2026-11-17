import Foundation
import Testing
import CmuxControlSocket
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The group color has three writers (the sidebar menu, the CLI and the
/// config) that must store the same spelling, so the checkmark in the menu can
/// match whatever any of them stored.
@MainActor
@Suite("Workspace group color normalization", .serialized)
struct WorkspaceGroupColorNormalizationTests {

    private func makeTabManager() -> TabManager {
        let suiteName = "cmux.workspace-group-color-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = TabManager(
            autoWelcomeIfNeeded: false,
            settings: UserDefaultsSettingsClient(defaults: defaults),
            closeTabWarningDefaults: defaults
        )
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        return manager
    }

    private func storedColor(_ manager: TabManager, _ groupId: UUID) -> String? {
        manager.workspaceGroups.first(where: { $0.id == groupId })?.customColor
    }

    @Test(arguments: [
        ("c0392b", "#C0392B"),
        ("#C0392B", "#C0392B"),
        (" #c0392b ", "#C0392B"),
    ])
    func tabManagerStoresUppercaseHashForm(input: String, expected: String) throws {
        let manager = makeTabManager()
        let groupId = try #require(manager.createWorkspaceGroup(name: "Color"))

        manager.setWorkspaceGroupColor(groupId: groupId, hex: input)

        #expect(storedColor(manager, groupId) == expected)
    }

    @Test(arguments: [String?.none, "", "nope", "+12345", "-12345"])
    func tabManagerClearsExistingColorOnEmptyOrInvalidInput(input: String?) throws {
        let manager = makeTabManager()
        let groupId = try #require(manager.createWorkspaceGroup(name: "Color"))
        manager.setWorkspaceGroupColor(groupId: groupId, hex: "#123456")
        #expect(storedColor(manager, groupId) == "#123456")

        manager.setWorkspaceGroupColor(groupId: groupId, hex: input)

        #expect(storedColor(manager, groupId) == nil)
    }

    @Test func sharedValidatorRejectsSignedHex() {
        #expect(WorkspaceTabColorSettings.normalizedHex("+12345") == nil)
        #expect(WorkspaceTabColorSettings.normalizedHex("-12345") == nil)
        #expect(WorkspaceTabColorSettings.normalizedHex("#+12345") == nil)
    }

    @Test func sharedValidatorNormalizesValidHex() {
        #expect(WorkspaceTabColorSettings.normalizedHex("c0392b") == "#C0392B")
        #expect(WorkspaceTabColorSettings.normalizedHex(" #c0392b ") == "#C0392B")
    }

    @Test func socketSetColorStoresSameValueAsTabManagerPath() throws {
        let socketManager = makeTabManager()
        let socketGroupId = try #require(socketManager.createWorkspaceGroup(name: "Socket"))
        let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
        TerminalController.shared.setActiveTabManager(socketManager)
        defer { TerminalController.shared.setActiveTabManager(previousManager) }

        let result = ControlCommandCoordinator(context: TerminalController.shared).handle(ControlRequest(
            id: .int(1),
            method: "workspace.group.set_color",
            params: [
                "group_id": .string(socketGroupId.uuidString),
                "hex": .string("c0392b"),
            ]
        ))
        guard case .ok = result else {
            return #expect(Bool(false), "set_color should succeed")
        }

        let directManager = makeTabManager()
        let directGroupId = try #require(directManager.createWorkspaceGroup(name: "Direct"))
        directManager.setWorkspaceGroupColor(groupId: directGroupId, hex: "c0392b")

        let socketStored = storedColor(socketManager, socketGroupId)
        #expect(socketStored == "#C0392B")
        #expect(socketStored == storedColor(directManager, directGroupId))
    }
}
