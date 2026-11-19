import CmuxSettings
import CmuxSurfaceCatalogModel
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The automatic workspace color's seams: the worktree key strategy, the hashed
/// palette assigner, the mode-gated resolver, and the adapter that reads a real
/// `Workspace` into the plain input the strategies see.
@Suite("Workspace auto color")
struct WorkspaceAutoColorTests {
    private let worktreeRoot = "/Users/alice/src/cmux/.claude/worktrees/feature"

    // MARK: Key provider

    @Test
    func worktreeKeyIsTheRootWhateverTheCwdDepth() {
        let provider = WorktreeDirectoryKeyProvider()
        #expect(provider.key(for: input(cwd: worktreeRoot, root: worktreeRoot)) == worktreeRoot)
        #expect(provider.key(for: input(cwd: worktreeRoot + "/Sources/Deep/Nested", root: worktreeRoot)) == worktreeRoot)
    }

    @Test
    func worktreeKeyIsNilWithoutARoot() {
        #expect(WorktreeDirectoryKeyProvider().key(for: input(cwd: "/tmp/scratch", root: nil)) == nil)
    }

    @Test
    func worktreeKeyIsNilForANonLocalWorkspaceEvenWithARoot() {
        #expect(WorktreeDirectoryKeyProvider().key(for: input(cwd: worktreeRoot, root: worktreeRoot, isLocal: false)) == nil)
    }

    // MARK: Assigner

    @Test
    func sameKeyGetsTheSameHexFromTwoAssigners() {
        #expect(HashedPaletteAssigner().colorHex(forKey: worktreeRoot) == HashedPaletteAssigner().colorHex(forKey: worktreeRoot))
        #expect(HashedPaletteAssigner().colorHex(forKey: worktreeRoot) != nil)
    }

    @Test
    func everyHexComesFromTheSharedPalette() {
        let assigner = HashedPaletteAssigner()
        for index in 0..<64 {
            let hex = assigner.colorHex(forKey: "/work/tree-\(index)")
            #expect(hex.map(WorkspaceDistinguishingPalette.colors.contains) == true)
        }
    }

    @Test
    func sixteenDistinctKeysDoNotAllLandOnOneColor() {
        let assigner = HashedPaletteAssigner()
        let hexes = Set((0..<16).compactMap { assigner.colorHex(forKey: "/work/tree-\($0)") })
        #expect(hexes.count > 1)
    }

    @Test
    func emptyPaletteGivesNil() {
        #expect(HashedPaletteAssigner(palette: []).colorHex(forKey: worktreeRoot) == nil)
    }

    // MARK: Resolver

    @Test
    func offModeGivesNilForAnyInput() {
        let resolver = WorkspaceAutoColorResolver.make(mode: .off)
        #expect(resolver.colorHex(for: input(cwd: worktreeRoot, root: worktreeRoot)) == nil)
        #expect(resolver.colorHex(for: input(cwd: "/tmp", root: nil)) == nil)
        #expect(resolver.colorHex(for: input(cwd: worktreeRoot, root: worktreeRoot, isLocal: false)) == nil)
    }

    @Test
    func worktreeModeComposesProviderAndAssigner() {
        let resolver = WorkspaceAutoColorResolver.make(mode: .worktree)
        let expected = HashedPaletteAssigner().colorHex(forKey: worktreeRoot)
        #expect(expected != nil)
        #expect(resolver.colorHex(for: input(cwd: worktreeRoot + "/Sources", root: worktreeRoot)) == expected)
        #expect(resolver.colorHex(for: input(cwd: "/tmp", root: nil)) == nil)
        #expect(resolver.colorHex(for: input(cwd: worktreeRoot, root: worktreeRoot, isLocal: false)) == nil)
    }

    @Test
    func resolverHandsTheProviderKeyToTheAssigner() {
        let resolver = WorkspaceAutoColorResolver(
            mode: .worktree,
            keyProvider: FixedKeyProvider(key: "fixed"),
            assigner: EchoAssigner()
        )
        #expect(resolver.colorHex(for: input(cwd: "/tmp", root: nil)) == "echo:fixed")
    }

    // MARK: Workspace adapter

    @MainActor
    @Test
    func plainLocalWorkspaceIsLocal() {
        let workspace = Workspace(workingDirectory: "/Users/alice/development")
        let adapted = WorkspaceAutoColorInput(workspace: workspace)
        #expect(adapted.isLocal)
        #expect(adapted.stableId == workspace.stableId)
        #expect(adapted.currentDirectory == workspace.currentDirectory)
        #expect(adapted.groupId == workspace.groupId)
    }

    @MainActor
    @Test
    func sshRemoteWorkspaceIsNotLocal() {
        let workspace = Workspace(workingDirectory: "/Users/alice/development")
        workspace.configureRemoteConnection(sshRemoteConfiguration(), autoConnect: false)
        #expect(!WorkspaceAutoColorInput(workspace: workspace).isLocal)
    }

    @MainActor
    @Test
    func remoteTmuxMirrorIsNotLocal() {
        let workspace = Workspace(workingDirectory: "/Users/alice/development")
        workspace.isRemoteTmuxMirror = true
        #expect(!WorkspaceAutoColorInput(workspace: workspace).isLocal)
    }

    @MainActor
    @Test
    func cloudBoundWorkspaceIsNotLocal() {
        let workspace = Workspace(workingDirectory: "/Users/alice/development")
        workspace.cloudVMBinding = WorkspaceCloudVMBinding(vmID: "auto-color-vm", isBase: false, remoteWorkspaceID: "ws_1")
        #expect(!WorkspaceAutoColorInput(workspace: workspace).isLocal)
    }

    @MainActor
    @Test
    func localWorkspaceWithOneCloudProjectedPaneIsNotLocal() throws {
        let workspace = Workspace(workingDirectory: "/Users/alice/development")
        let paneId = try #require(workspace.bonsplitController.focusedPaneId)
        let projectedPanel = try #require(workspace.newTerminalSurface(inPane: paneId, focus: false))
        #expect(WorkspaceAutoColorInput(workspace: workspace).isLocal)
        let resource = SurfaceResource(
            id: SurfaceResourceID(machine: .cloud("auto-color-\(UUID())"), kind: .terminal, key: "term_1"),
            title: "terminal", detail: nil, lifecycle: .running,
            agent: nil, remoteWorkspace: nil, port: nil, url: nil
        )
        let catalog = SurfaceCatalog.shared
        catalog.upsert(resource)
        catalog.record(SurfaceProjection(resource: resource.id, workspaceID: workspace.id, panelID: projectedPanel.id))
        defer {
            catalog.endProjections(panelID: projectedPanel.id)
            catalog.remove(resource.id)
        }
        #expect(workspace.cloudVMBinding == nil)
        #expect(!WorkspaceAutoColorInput(workspace: workspace).isLocal)
    }

    /// RemoteTmuxController creates a plain workspace and only then flags it a
    /// mirror, so a root resolved while it was local is still published.
    @MainActor
    @Test
    func rootResolvedBeforeTheMirrorFlagYieldsNoColor() async throws {
        let fixture = try LinkedWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(workingDirectory: fixture.worktree.path)
        try await waitForProjectRoot(of: workspace, toBe: fixture.worktree.path)
        let resolver = WorkspaceAutoColorResolver.make(mode: .worktree)
        #expect(resolver.colorHex(for: WorkspaceAutoColorInput(workspace: workspace)) != nil)

        workspace.isRemoteTmuxMirror = true

        #expect(workspace.extensionSidebarProjectRootPath == fixture.worktree.path)
        #expect(resolver.colorHex(for: WorkspaceAutoColorInput(workspace: workspace)) == nil)
    }

    /// Characterization of the premise the worktree key rests on: the root walk
    /// stops at the first `.git`, and a linked worktree's `.git` is a file.
    @MainActor
    @Test
    func nestedDirectoryInALinkedWorktreeResolvesToTheWorktree() async throws {
        let fixture = try LinkedWorktreeFixture()
        defer { fixture.remove() }
        let nested = fixture.worktree.appendingPathComponent("Sources/Deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let workspace = Workspace(workingDirectory: nested.path)
        try await waitForProjectRoot(of: workspace, toBe: fixture.worktree.path)
        #expect(workspace.extensionSidebarProjectRootPath == fixture.worktree.path)
        #expect(workspace.extensionSidebarProjectRootPath != fixture.mainCheckout.path)
        #expect(WorkspaceAutoColorInput(workspace: workspace).projectRootPath == fixture.worktree.path)
    }

    // MARK: Helpers

    private func input(cwd: String, root: String?, isLocal: Bool = true) -> WorkspaceAutoColorInput {
        WorkspaceAutoColorInput(stableId: UUID(), currentDirectory: cwd, projectRootPath: root, groupId: nil, isLocal: isLocal)
    }

    /// Root discovery runs on a detached task, so poll its published value with
    /// a bound instead of awaiting the publisher, which would hang on a miss.
    @MainActor
    private func waitForProjectRoot(of workspace: Workspace, toBe path: String) async throws {
        for _ in 0..<500 where workspace.extensionSidebarProjectRootPath != path {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try #require(workspace.extensionSidebarProjectRootPath == path)
    }

    private func sshRemoteConfiguration() -> WorkspaceRemoteConfiguration {
        WorkspaceRemoteConfiguration(
            destination: "alice@192.168.5.20",
            port: nil,
            identityFile: nil,
            sshOptions: [],
            localProxyPort: nil,
            relayPort: 64008,
            relayID: "relay-\(UUID().uuidString)",
            relayToken: String(repeating: "a", count: 64),
            localSocketPath: "/tmp/cmux-auto-color-\(UUID().uuidString).sock",
            terminalStartupCommand: "ssh alice@192.168.5.20"
        )
    }
}

/// A main checkout with a `.git` directory and, inside it, a linked worktree
/// whose `.git` is a file, laid out the way `git worktree add` leaves them.
private struct LinkedWorktreeFixture {
    let mainCheckout: URL
    let worktree: URL

    init() throws {
        let fileManager = FileManager.default
        mainCheckout = fileManager.temporaryDirectory
            .appendingPathComponent("auto-color-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        worktree = mainCheckout.appendingPathComponent(".claude/worktrees/feature", isDirectory: true)
        try fileManager.createDirectory(
            at: mainCheckout.appendingPathComponent(".git/worktrees/feature", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: \(mainCheckout.path)/.git/worktrees/feature\n".utf8)
            .write(to: worktree.appendingPathComponent(".git"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: mainCheckout)
    }
}

private struct FixedKeyProvider: WorkspaceAutoColorKeyProviding {
    let key: String
    func key(for input: WorkspaceAutoColorInput) -> String? { key }
}

private struct EchoAssigner: WorkspaceAutoColorAssigning {
    func colorHex(forKey key: String) -> String? { "echo:\(key)" }
}
