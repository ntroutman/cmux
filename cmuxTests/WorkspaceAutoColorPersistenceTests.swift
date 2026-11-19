import AppKit
import CmuxNotifications
import CmuxSettings
import CmuxSettingsUI
import CmuxUpdater
import CmuxWorkspaces
import Foundation
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// An automatic workspace color is paint-time only: the row shows it, but the
/// workspace, its customization journal, its captured definition, its session
/// snapshot and the socket payload all keep reporting no color.
///
/// The settings runtime, app storage and customization journal share one
/// private defaults suite. The test host runs the app, whose live store
/// re-applies `~/.config/cmux/cmux.json` on every `.standard` defaults change.
@MainActor
@Suite("Workspace auto color persistence", .serialized)
struct WorkspaceAutoColorPersistenceTests {
    @Test
    func automaticColorPaintsTheRowWithoutJournalingAColor() async throws {
        let worktrees = try PersistenceWorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try JournaledSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.root)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })

        #expect(workspace.customColor == nil)
        #expect(sidebar.cache.value(for: workspace.id)?.hasManualCustomColor == false)
        #expect(sidebar.journaledColor(of: workspace) == nil)
        #expect(sidebar.journalData() == nil)
    }

    @Test
    func capturedDefinitionAndSessionSnapshotCarryNoAutomaticColor() async throws {
        let worktrees = try PersistenceWorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try JournaledSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.root)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })

        let definition = try workspace.captureLayoutDefinition().workspace
        #expect(definition.color == nil)
        #expect(workspace.sessionSnapshot(includeScrollback: false).customColor == nil)
    }

    @Test
    func clearingAManualColorJournalsAClearAndRevealsTheAutomaticColor() async throws {
        let worktrees = try PersistenceWorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try JournaledSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.root)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })

        sidebar.manager.setTabColor(tabId: workspace.id, color: "#FF945A")
        #expect(sidebar.journaledColor(of: workspace) == .value("#FF945A"))
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == "#FF945A" })

        sidebar.manager.setTabColor(tabId: workspace.id, color: nil)
        // A tombstone, never the automatic hex: restore must not resurrect a color.
        #expect(sidebar.journaledColor(of: workspace) == .cleared)
        #expect(workspace.customColor == nil)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })
        #expect(sidebar.journaledColor(of: workspace) == .cleared)
    }

    @Test
    func togglingTheSettingWritesNothingToTheJournal() async throws {
        let worktrees = try PersistenceWorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try JournaledSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.root)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })
        // A seeded record makes the byte comparison meaningful: an empty journal
        // would also compare equal if the store were a no-op.
        #expect(sidebar.manager.setCustomTitle(tabId: workspace.id, title: "Seeded", propagateToCloud: false))
        let before = try #require(sidebar.journalData())
        #expect(sidebar.journaledColor(of: workspace) == .absent)

        await sidebar.setAutoColor(.off)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == nil })
        #expect(sidebar.journalData() == before)

        await sidebar.setAutoColor(.worktree)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })
        #expect(sidebar.journalData() == before)
        #expect(sidebar.journaledColor(of: workspace) == .absent)
        #expect(workspace.customColor == nil)
    }

    /// Every socket workspace read (`workspace.list`, sidebar and system
    /// context, the mobile list) projects `Workspace.customColor`; the mobile
    /// payload is the one reachable without routing through the live app.
    @Test
    func socketPayloadReportsNoColorForAnAutomaticallyColoredWorkspace() async throws {
        let worktrees = try PersistenceWorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try JournaledSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.root)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.rootHex })

        let payload = TerminalController.shared.mobileWorkspacePayload(
            workspace: workspace,
            isSelected: false,
            requestedTerminalID: nil
        )
        #expect(payload["custom_color"] is NSNull)
    }
}

// MARK: Fixtures

/// A main checkout holding one linked worktree, the root the automatic color hashes.
private struct PersistenceWorktreeFixture {
    let mainCheckout: URL
    let root: URL
    let rootHex: String

    init() throws {
        let fileManager = FileManager.default
        mainCheckout = fileManager.temporaryDirectory
            .appendingPathComponent("auto-color-persistence-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        root = mainCheckout.appendingPathComponent(".claude/worktrees/persisted", isDirectory: true)
        let gitDir = mainCheckout.appendingPathComponent(".git/worktrees/persisted", isDirectory: true)
        try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("gitdir: \(gitDir.path)\n".utf8).write(to: root.appendingPathComponent(".git"))
        rootHex = try #require(HashedPaletteAssigner().colorHex(forKey: root.path))
    }

    func remove() {
        try? FileManager.default.removeItem(at: mainCheckout)
    }
}

/// A `VerticalTabsSidebar` hosted off-screen over a `TabManager` whose
/// customization journal, settings runtime and app storage all live in one
/// private defaults suite, so the journal's bytes can be inspected directly.
@MainActor
private struct JournaledSidebar {
    let suiteName = "WorkspaceAutoColorPersistenceTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let runtime: SettingsRuntime
    let cache = SidebarRowSnapshotCache()
    let journal: WorkspaceCustomizationStore
    let manager: TabManager
    let window: NSWindow

    init(autoColor: WorkspaceAutoColorMode) throws {
        _ = NSApplication.shared
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(autoColor.rawValue, forKey: SettingCatalog().workspaceColors.autoColor.userDefaultsKey)
        defaults.set(CmuxExtensionSidebarSelection.defaultProviderId, forKey: CmuxExtensionSidebarSelection.defaultsKey)
        journal = WorkspaceCustomizationStore(defaults: defaults)
        manager = TabManager(autoWelcomeIfNeeded: false, workspaceCustomizationStore: journal)
        // Separate handles on one suite: the store actor takes its own, since
        // `UserDefaults` is not Sendable.
        runtime = SettingsRuntime(
            catalog: SettingCatalog(),
            userDefaultsStore: UserDefaultsSettingsStore(defaults: try #require(UserDefaults(suiteName: suiteName))),
            jsonStore: JSONConfigStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
            ),
            secretStore: SecretFileStore(
                baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            errorLog: SettingsErrorLog()
        )
        let root = VerticalTabsSidebar(
            updateViewModel: UpdateStateModel(),
            fileExplorerState: FileExplorerState(),
            sessionIndexStore: SessionIndexStore(),
            featureFlags: CmuxFeatureFlags(defaults: defaults, remoteFlagValueProvider: { _ in nil }),
            sidebarUnread: SidebarUnreadModel(),
            titlebarControlsLayoutModel: TitlebarControlsLayoutModel(),
            windowId: UUID(),
            onSendFeedback: {}, onToggleSidebar: {}, onNewTab: {},
            observedWindowReference: WeakWindowReference(),
            chromeBackgroundColor: .black,
            selection: .constant(.tabs),
            selectedTabIds: .constant([]),
            lastSidebarSelectionIndex: .constant(nil),
            sidebarRenderWorkerClient: .constant(nil),
            workspaceSnapshotCache: cache
        )
        .environmentObject(manager)
        .environmentObject(CmuxConfigStore())
        .environmentObject(TerminalNotificationStore.shared)
        .environmentObject(SidebarState())
        .environmentObject(SidebarSelectionState())
        .settingsRuntime(runtime)
        .defaultAppStorage(defaults)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
    }

    func tearDown() {
        window.contentView = nil
        window.close()
        defaults.removePersistentDomain(forName: suiteName)
    }

    func addLocalWorkspace(in directory: URL) -> Workspace {
        manager.addWorkspace(
            workingDirectory: directory.path,
            select: false,
            autoWelcomeIfNeeded: false,
            autoRefreshMetadata: false
        )
    }

    func colorHex(of workspace: Workspace) -> String? {
        cache.value(for: workspace.id)?.customColorHex
    }

    func journaledColor(of workspace: Workspace) -> WorkspaceCustomizationField? {
        journal.customization(for: workspace.stableId)?.customColor
    }

    /// The journal's encoded bytes, so a write of any field is caught.
    func journalData() -> Data? {
        defaults.data(forKey: WorkspaceCustomizationStore.defaultStorageKey)
    }

    func setAutoColor(_ mode: WorkspaceAutoColorMode) async {
        await runtime.userDefaultsStore.set(mode, for: SettingCatalog().workspaceColors.autoColor)
    }

    func converge(until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            SidebarLazyLayoutScaleTests.turnMainRunLoopOnce(layingOut: window)
            await Task.yield()
            if condition() { return true }
        } while .now < deadline
        return false
    }
}
