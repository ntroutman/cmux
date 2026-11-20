import AppKit
import CmuxNotifications
import CmuxSettings
import CmuxSettingsUI
import CmuxUpdater
import Foundation
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The automatic workspace color reaching sidebar rows: the snapshot factory's
/// manual-else-fallback chain, and a mounted sidebar whose keyed and full
/// refreshes both carry the color the `workspaceColors.autoColor` setting picks.
///
/// Mounted cases read the setting from a private defaults suite. The test host
/// runs the app, whose live store re-applies `~/.config/cmux/cmux.json` on
/// every `.standard` defaults change, so the shared domain is never touched.
@MainActor
@Suite("Sidebar auto color", .serialized)
struct SidebarAutoColorTests {
    // MARK: Snapshot factory

    @Test
    func manualColorWinsOverTheFallbackColor() throws {
        let defaults = try PrivateDefaults()
        defer { defaults.remove() }
        let workspace = Workspace(title: "Manual", initialSurface: .cloudVMLoading)
        defer { workspace.teardownAllPanels() }
        workspace.customColor = "#FF945A"
        let snapshot = SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: defaults.handle),
            showsAgentActivity: false,
            fallbackColorHex: "#B1A2FA"
        ).makeSnapshot()
        #expect(snapshot.customColorHex == "#FF945A")
        #expect(snapshot.hasManualCustomColor)
    }

    @Test
    func fallbackColorPaintsARowWithoutAManualColor() throws {
        let defaults = try PrivateDefaults()
        defer { defaults.remove() }
        let workspace = Workspace(title: "Fallback", initialSurface: .cloudVMLoading)
        defer { workspace.teardownAllPanels() }
        let snapshot = SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: defaults.handle),
            showsAgentActivity: false,
            fallbackColorHex: "#B1A2FA"
        ).makeSnapshot()
        #expect(snapshot.customColorHex == "#B1A2FA")
        #expect(!snapshot.hasManualCustomColor)
    }

    @Test
    func modeOffWithoutAnOriginColorLeavesTheRowUncolored() async throws {
        let defaults = try PrivateDefaults()
        defer { defaults.remove() }
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let workspace = Workspace(workingDirectory: worktrees.first.path)
        try await waitUntil { workspace.extensionSidebarProjectRootPath == worktrees.first.path }
        let snapshot = SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: defaults.handle),
            showsAgentActivity: false,
            fallbackColorHex: WorkspaceAutoColorResolver.make(mode: .off)
                .colorHex(for: WorkspaceAutoColorInput(workspace: workspace))
        ).makeSnapshot()
        #expect(snapshot.customColorHex == nil)
        #expect(!snapshot.hasManualCustomColor)
    }

    // MARK: Mounted sidebar

    /// A `cd` reaches the row only through the per-workspace observation, the
    /// coalescer and the keyed refresh, which never consults the presentation key.
    @Test
    func keyedRefreshRecolorsARowThatMovesToAnotherWorktree() async throws {
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try MountedSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.first)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.firstHex })

        workspace.currentDirectory = worktrees.second.path

        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.secondHex })
        #expect(sidebar.cache.value(for: workspace.id)?.hasManualCustomColor == false)
    }

    @Test
    func unrelatedKeyedUpdateKeepsTheAutomaticColor() async throws {
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try MountedSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.first)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.firstHex })

        workspace.setCustomTitle("Renamed while auto colored")

        #expect(await sidebar.converge { sidebar.cache.value(for: workspace.id)?.title == "Renamed while auto colored" })
        #expect(sidebar.colorHex(of: workspace) == worktrees.firstHex)
    }

    @Test
    func manualColorOverridesAndClearingRevealsTheAutomaticColor() async throws {
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try MountedSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.first)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.firstHex })

        workspace.customColor = "#FF945A"
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == "#FF945A" })
        #expect(sidebar.cache.value(for: workspace.id)?.hasManualCustomColor == true)

        workspace.customColor = nil
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.firstHex })
        #expect(sidebar.cache.value(for: workspace.id)?.hasManualCustomColor == false)
    }

    @Test
    func turningTheSettingOffClearsEveryAutomaticColor() async throws {
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try MountedSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let first = sidebar.addLocalWorkspace(in: worktrees.first)
        let second = sidebar.addLocalWorkspace(in: worktrees.second)
        #expect(await sidebar.converge {
            sidebar.colorHex(of: first) == worktrees.firstHex && sidebar.colorHex(of: second) == worktrees.secondHex
        })

        await sidebar.setAutoColor(.off)

        #expect(await sidebar.converge { sidebar.colorHex(of: first) == nil && sidebar.colorHex(of: second) == nil })
    }

    /// `currentDirectory` follows the most recently focused pane that reported
    /// a directory, so the color does too.
    @Test
    func focusingAPaneInAnotherWorktreeRecolorsTheRow() async throws {
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try MountedSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let workspace = sidebar.addLocalWorkspace(in: worktrees.first)
        let firstPanelId = try #require(workspace.focusedPanelId)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.firstHex })
        let secondPanel = try #require(workspace.newTerminalSplit(from: firstPanelId, orientation: .horizontal, focus: false))
        #expect(workspace.updatePanelDirectory(panelId: secondPanel.id, directory: worktrees.second.path))
        let silentPanel = try #require(workspace.newTerminalSplit(from: secondPanel.id, orientation: .vertical, focus: false))
        // The silent pane must have no reported directory for its focus case to mean anything.
        try #require(workspace.panelDirectories[silentPanel.id] == nil)
        #expect(sidebar.colorHex(of: workspace) == worktrees.firstHex)

        workspace.focusPanel(secondPanel.id)
        #expect(await sidebar.converge { sidebar.colorHex(of: workspace) == worktrees.secondHex })

        workspace.focusPanel(silentPanel.id)
        await sidebar.drain()
        #expect(workspace.currentDirectory == worktrees.second.path)
        #expect(sidebar.colorHex(of: workspace) == worktrees.secondHex)
    }

    /// Header coloring belongs to the group header's own resolution; a member's
    /// automatic color must not leak into it.
    @Test
    func groupedMemberIsAutoColoredWhileTheUncoloredHeaderStaysNil() async throws {
        let worktrees = try WorktreeFixture()
        defer { worktrees.remove() }
        let sidebar = try MountedSidebar(autoColor: .worktree)
        defer { sidebar.tearDown() }
        let member = sidebar.addLocalWorkspace(in: worktrees.first)
        let groupId = try #require(sidebar.manager.createWorkspaceGroup(
            name: "Auto colored members",
            childWorkspaceIds: [member.id],
            anchorWorkingDirectory: worktrees.first.path,
            selectAnchor: false
        ))
        let group = try #require(sidebar.manager.workspaceGroups.first { $0.id == groupId })
        let anchor = try #require(group.liveAnchorWorkspaceId.flatMap { id in sidebar.manager.tabs.first { $0.id == id } })
        try await waitUntil { anchor.extensionSidebarProjectRootPath == worktrees.first.path }
        #expect(await sidebar.converge { sidebar.colorHex(of: member) == worktrees.firstHex })

        let configStore = CmuxConfigStore()
        // Automatic group colors are off here (empty palette), so a nil header
        // color proves the automatic workspace color alone never reaches the header.
        let headerColors = VerticalTabsSidebar.groupColorHexByGroupId(
            groups: sidebar.manager.workspaceGroups,
            configColor: { _ in configStore.resolveWorkspaceGroupConfig(forCwd: anchor.currentDirectory)?.color },
            autoPalette: []
        )
        #expect(group.customColor == nil)
        #expect(headerColors[groupId] == nil)
    }
}

// MARK: Fixtures

/// A private defaults suite, so no case writes to the host app's `.standard`.
@MainActor
private struct PrivateDefaults {
    let suiteName = "SidebarAutoColorTests.\(UUID().uuidString)"
    let handle: UserDefaults

    init() throws {
        handle = try #require(UserDefaults(suiteName: suiteName))
    }

    func remove() {
        handle.removePersistentDomain(forName: suiteName)
    }
}

/// A main checkout holding two linked worktrees whose roots hash to different
/// palette colors, so a move between them must visibly change the row.
private struct WorktreeFixture {
    let mainCheckout: URL
    let first: URL
    let second: URL
    let firstHex: String
    let secondHex: String

    init() throws {
        let fileManager = FileManager.default
        mainCheckout = fileManager.temporaryDirectory
            .appendingPathComponent("sidebar-auto-color-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: mainCheckout.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let assigner = HashedPaletteAssigner()
        first = try Self.makeWorktree(named: "first", in: mainCheckout)
        firstHex = try #require(assigner.colorHex(forKey: first.path))
        // Sixteen colors make a collision likely enough to rule out by search.
        var candidate = 0
        var second = try Self.makeWorktree(named: "second-\(candidate)", in: mainCheckout)
        while assigner.colorHex(forKey: second.path) == firstHex {
            candidate += 1
            second = try Self.makeWorktree(named: "second-\(candidate)", in: mainCheckout)
        }
        self.second = second
        secondHex = try #require(assigner.colorHex(forKey: second.path))
    }

    func remove() {
        try? FileManager.default.removeItem(at: mainCheckout)
    }

    private static func makeWorktree(named name: String, in mainCheckout: URL) throws -> URL {
        let fileManager = FileManager.default
        let worktree = mainCheckout.appendingPathComponent(".claude/worktrees/\(name)", isDirectory: true)
        let gitDir = mainCheckout.appendingPathComponent(".git/worktrees/\(name)", isDirectory: true)
        try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: \(gitDir.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        return worktree
    }
}

/// A `VerticalTabsSidebar` hosted in an off-screen window, with its settings
/// runtime and app storage both backed by one private defaults suite.
@MainActor
private struct MountedSidebar {
    let defaults: PrivateDefaults
    let runtime: SettingsRuntime
    let cache = SidebarRowSnapshotCache()
    let manager = TabManager(autoWelcomeIfNeeded: false)
    let window: NSWindow

    init(autoColor: WorkspaceAutoColorMode) throws {
        _ = NSApplication.shared
        defaults = try PrivateDefaults()
        let autoColorKey = SettingCatalog().workspaceColors.autoColor
        defaults.handle.set(autoColor.rawValue, forKey: autoColorKey.userDefaultsKey)
        defaults.handle.set(CmuxExtensionSidebarSelection.defaultProviderId, forKey: CmuxExtensionSidebarSelection.defaultsKey)
        // Separate handles on one suite: the store actor takes its own, since
        // `UserDefaults` is not Sendable.
        runtime = SettingsRuntime(
            catalog: SettingCatalog(),
            userDefaultsStore: UserDefaultsSettingsStore(defaults: try #require(UserDefaults(suiteName: defaults.suiteName))),
            jsonStore: JSONConfigStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
            ),
            secretStore: SecretFileStore(
                baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            errorLog: SettingsErrorLog()
        )
        let flags = CmuxFeatureFlags(defaults: defaults.handle, remoteFlagValueProvider: { _ in nil })
        let root = VerticalTabsSidebar(
            updateViewModel: UpdateStateModel(),
            fileExplorerState: FileExplorerState(),
            sessionIndexStore: SessionIndexStore(),
            featureFlags: flags,
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
        .defaultAppStorage(defaults.handle)
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
        defaults.remove()
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

    /// Lets the observation debounce and coalescer run out, for cases that
    /// assert nothing changed.
    func drain() async {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while .now < deadline {
            SidebarLazyLayoutScaleTests.turnMainRunLoopOnce(layingOut: window)
            await Task.yield()
        }
    }
}

/// Root discovery runs on a detached task, so poll its published value with a
/// bound instead of awaiting the publisher, which would hang on a miss.
@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<500 where !condition() {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try #require(condition())
}
