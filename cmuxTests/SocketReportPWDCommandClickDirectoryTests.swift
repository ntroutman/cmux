import AppKit
import CmuxTerminal
import Foundation
import Testing
import struct CmuxSettings.AppCatalogSection
import protocol CmuxWorkspaces.FileOpening

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A socket `report_pwd` for a local surface must reach the directory that an
/// `OPEN_URL` cmd-click resolves relative paths against (the dispatcher
/// snapshot), through all three socket entrypoints, while leaving remote/cloud
/// surfaces untouched. See
/// `docs/superpowers/specs/2026-10-26-socket-report-pwd-cmd-click-cwd-design.md`.
@MainActor
@Suite("Socket report_pwd cmd-click directory", .serialized)
struct SocketReportPWDCommandClickDirectoryTests {
    private let assertions = SwiftTestingAssertions()

    // MARK: - Test doubles

    /// Records URLs handed to the coordinator's file-opening seam.
    private final class RecordingFileOpener: FileOpening {
        private(set) var opened: [URL] = []
        func open(_ url: URL) { opened.append(url) }
    }

    /// A terminal that runs on this Mac; captures the file path the coordinator
    /// resolves so the test can assert which directory the click resolved
    /// against.
    private final class LocalLinkContainer: TerminalLinkOpenContainer {
        private(set) var deferredFilePaths: [String] = []
        var terminalLinkContainerDebugName: String { "report-pwd-local-test" }
        func terminalLinkWorkingDirectory(for sourcePanelId: UUID) -> String? { nil }
        func terminalLinkIsRemoteTerminal(_ sourcePanelId: UUID) -> Bool { false }
        func cloudTerminalLinkTarget(url: URL, sourcePanelId: UUID) -> CloudTerminalLinkTarget? { nil }
        func deferTerminalFileLinkOpen(
            sourcePanelId: UUID,
            filePath: String,
            fallback: @escaping @MainActor @Sendable () -> Void
        ) -> Bool {
            deferredFilePaths.append(filePath)
            return true
        }
        func openTerminalBrowserLink(url: URL, sourcePanelId: UUID, focus: Bool) -> Bool { false }
    }

    // MARK: - Fixtures

    private func makeMainWindow(id: UUID) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(id.uuidString)")
        return window
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "socket-report-pwd-cmd-click-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: BrowserAvailabilitySettings.disabledKey)
        defaults.set(true, forKey: BrowserLinkOpenSettings.openTerminalLinksInCmuxBrowserKey)
        // Supported-file routing keeps an ordinary file on the in-cmux route so
        // the resolved absolute path lands in the container's deferred path,
        // which is what the assertions read.
        defaults.set(true, forKey: AppCatalogSection().openSupportedFilesInCmux.userDefaultsKey)
        return defaults
    }

    private func makeDirectory(_ tag: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-report-pwd-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Registers a single-window `TabManager` whose selected workspace hosts a
    /// focused local terminal surface, then tears the registration down.
    private func withRegisteredWorkspace(
        configure: (Workspace) -> Void = { _ in },
        _ body: (Workspace, TerminalPanel) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let previousAppDelegate = AppDelegate.shared
        let app = AppDelegate()
        let windowId = UUID()
        let window = makeMainWindow(id: windowId)
        let manager = TabManager(autoWelcomeIfNeeded: false)
        app.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(),
            fileExplorerState: FileExplorerState()
        )
        TerminalController.shared.setActiveTabManager(manager)
        defer {
            TerminalController.shared.setActiveTabManager(nil)
            app.unregisterMainWindowContextForTesting(windowId: windowId)
            window.orderOut(nil)
            AppDelegate.shared = previousAppDelegate
        }

        let workspace = try assertions.require(manager.selectedWorkspace)
        configure(workspace)
        let panel = try assertions.require(workspace.focusedTerminalPanel)
        try body(workspace, panel)
    }

    private func dispatcher(for panel: TerminalPanel) -> GhosttyCurrentDirectoryActionDispatcher {
        panel.hostedView.surfaceView.currentDirectoryActionDispatcher
    }

    /// Seeds a stale OSC 7 directory on the panel's own dispatcher (the instance
    /// `GHOSTTY_ACTION_OPEN_URL` reads), as a shell would before a socket report.
    private func seedStaleOSC7(_ panel: TerminalPanel, directory: String) {
        dispatcher(for: panel).enqueue(
            directory: directory,
            authoritativeGeometry: nil,
            surfaceView: panel.hostedView.surfaceView,
            terminalSurface: panel.surface
        )
    }

    private func v2ReportPWD(workspaceID: UUID, surfaceID: UUID, path: String) -> String {
        let request: [String: Any] = [
            "id": "surface-report-pwd",
            "method": "surface.report_pwd",
            "params": [
                "workspace_id": workspaceID.uuidString,
                "surface_id": surfaceID.uuidString,
                "path": path,
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: request)
        return TerminalController.shared.handleSocketLine(String(data: data, encoding: .utf8)!)
    }

    /// Builds the exact request `GHOSTTY_ACTION_OPEN_URL` builds — a relative
    /// link resolved against the dispatcher snapshot — and asserts the
    /// coordinator opened the file under `expectedDirectory`.
    private func assertCmdClickResolves(
        workspace: Workspace,
        panel: TerminalPanel,
        relativeFile: String,
        expectedDirectory: URL
    ) {
        let container = LocalLinkContainer()
        let fileOpener = RecordingFileOpener()
        let coordinator = TerminalLinkOpenCoordinator(
            defaults: makeDefaults(),
            containerResolver: { _, _ in container },
            externalOpen: { url in
                Issue.record("cmd-click escaped to the external opener: \(url)")
                return false
            },
            fileOpen: fileOpener,
            deferOperation: { operation in operation() }
        )

        let opened = coordinator.open(TerminalLinkOpenRequest(
            rawValue: relativeFile,
            sourceWorkspaceId: workspace.id,
            sourcePanelId: panel.id,
            workingDirectory: dispatcher(for: panel).directorySnapshot()
        ))

        assertions.isTrue(opened, "coordinator should open the resolved file")
        assertions.equal(
            container.deferredFilePaths,
            [expectedDirectory.appendingPathComponent(relativeFile).path]
        )
        assertions.isTrue(fileOpener.opened.isEmpty)
    }

    // MARK: - Regression: three entrypoints redirect cmd-click (tests fail on base)

    @Test func scopedLegacyReportRedirectsCmdClick() throws {
        try withRegisteredWorkspace { workspace, panel in
            let stale = try makeDirectory("scoped-stale")
            let fresh = try makeDirectory("scoped-fresh")
            defer {
                try? FileManager.default.removeItem(at: stale)
                try? FileManager.default.removeItem(at: fresh)
            }
            let relativeFile = "notes.txt"
            try "hi\n".write(to: fresh.appendingPathComponent(relativeFile), atomically: true, encoding: .utf8)
            seedStaleOSC7(panel, directory: stale.path)

            let response = TerminalController.shared.handleSocketLine(
                "report_pwd \(fresh.path) --tab=\(workspace.id.uuidString) --panel=\(panel.id.uuidString)"
            )
            assertions.equal(response, "OK")

            // Asserted before draining the mutation bus: the scoped path must
            // publish the snapshot inside the command's hop, not at drain.
            assertCmdClickResolves(
                workspace: workspace,
                panel: panel,
                relativeFile: relativeFile,
                expectedDirectory: fresh
            )
            TerminalMutationBus.shared.drainForTesting()
        }
    }

    @Test func fallbackLegacyReportRedirectsCmdClick() throws {
        try withRegisteredWorkspace { workspace, panel in
            let stale = try makeDirectory("fallback-stale")
            let fresh = try makeDirectory("fallback-fresh")
            defer {
                try? FileManager.default.removeItem(at: stale)
                try? FileManager.default.removeItem(at: fresh)
            }
            let relativeFile = "report.txt"
            try "hi\n".write(to: fresh.appendingPathComponent(relativeFile), atomically: true, encoding: .utf8)
            seedStaleOSC7(panel, directory: stale.path)

            // No `--panel`: the fallback path resolves the focused surface.
            let response = TerminalController.shared.handleSocketLine(
                "report_pwd \(fresh.path) --tab=\(workspace.id.uuidString)"
            )
            assertions.equal(response, "OK")

            assertCmdClickResolves(
                workspace: workspace,
                panel: panel,
                relativeFile: relativeFile,
                expectedDirectory: fresh
            )
        }
    }

    @Test func v2SurfaceReportRedirectsCmdClick() throws {
        try withRegisteredWorkspace { workspace, panel in
            let stale = try makeDirectory("v2-stale")
            let fresh = try makeDirectory("v2-fresh")
            defer {
                try? FileManager.default.removeItem(at: stale)
                try? FileManager.default.removeItem(at: fresh)
            }
            let relativeFile = "doc.txt"
            try "hi\n".write(to: fresh.appendingPathComponent(relativeFile), atomically: true, encoding: .utf8)
            seedStaleOSC7(panel, directory: stale.path)

            let response = v2ReportPWD(workspaceID: workspace.id, surfaceID: panel.id, path: fresh.path)
            assertions.isTrue(response.contains("\"ok\":true"), response)

            assertCmdClickResolves(
                workspace: workspace,
                panel: panel,
                relativeFile: relativeFile,
                expectedDirectory: fresh
            )
        }
    }

    // MARK: - Ordering: last writer by execution wins

    @Test func laterOSC7OverridesSocketReportOnSnapshot() throws {
        try withRegisteredWorkspace { workspace, panel in
            TerminalMutationBus.shared.setDrainsSuspendedForTesting(true)
            defer { TerminalMutationBus.shared.setDrainsSuspendedForTesting(false) }

            seedStaleOSC7(panel, directory: "/a")
            let response = TerminalController.shared.handleSocketLine(
                "report_pwd /b --tab=\(workspace.id.uuidString) --panel=\(panel.id.uuidString)"
            )
            assertions.equal(response, "OK")
            // The in-hop publish happened even though the record write is still
            // pending on the suspended bus.
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/b")

            dispatcher(for: panel).enqueue(
                directory: "/c",
                authoritativeGeometry: nil,
                surfaceView: panel.hostedView.surfaceView,
                terminalSurface: panel.surface
            )
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/c")

            // Draining the queued scoped record write must NOT re-publish /b over
            // the newer /c.
            TerminalMutationBus.shared.drainForTesting()
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/c")

            // The reverse direction at the dispatcher: a socket record after a
            // newer OSC 7 wins by execution order.
            dispatcher(for: panel).enqueue(
                directory: "/c",
                authoritativeGeometry: nil,
                surfaceView: panel.hostedView.surfaceView,
                terminalSurface: panel.surface
            )
            dispatcher(for: panel).recordExternallyReportedDirectory("/b")
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/b")
        }
    }

    // MARK: - Label never leaks

    @Test func displayLabelNeverResolvesCmdClick() throws {
        try withRegisteredWorkspace { workspace, panel in
            let fresh = try makeDirectory("label-path")
            defer { try? FileManager.default.removeItem(at: fresh) }
            seedStaleOSC7(panel, directory: "/a")

            let response = TerminalController.shared.handleSocketLine(
                "report_pwd \"My Package\" --path=\(fresh.path) --tab=\(workspace.id.uuidString) --panel=\(panel.id.uuidString)"
            )
            assertions.equal(response, "OK")

            // Only the filesystem path reaches the snapshot; the display label
            // is never used as a resolution directory.
            assertions.equal(dispatcher(for: panel).directorySnapshot(), fresh.path)
            TerminalMutationBus.shared.drainForTesting()
        }
    }

    // MARK: - Provenance: remote/cloud surfaces untouched

    @Test func remoteProvenanceSurfaceLeavesSnapshotUnchanged() throws {
        // A remote-trust-required surface: `allowsLocalDirectoryFallback` is
        // false, so the helper's provenance gate (not the `.recorded` enum)
        // keeps the local dispatcher snapshot untouched.
        try withRegisteredWorkspace(configure: { $0.isRemoteTmuxMirror = true }) { workspace, panel in
            assertions.isFalse(workspace.allowsLocalDirectoryFallback(panelId: panel.id))
            seedStaleOSC7(panel, directory: "/a")

            let response = v2ReportPWD(workspaceID: workspace.id, surfaceID: panel.id, path: "/remote/new")
            assertions.isTrue(response.contains("\"ok\":true"), response)
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/a")
            TerminalMutationBus.shared.drainForTesting()
        }
    }

    // MARK: - Blank report is a no-op end to end

    @Test func whitespaceOnlyReportLeavesSnapshotUnchanged() throws {
        try withRegisteredWorkspace { workspace, panel in
            seedStaleOSC7(panel, directory: "/a")

            let response = TerminalController.shared.handleSocketLine(
                "report_pwd \"   \" --tab=\(workspace.id.uuidString) --panel=\(panel.id.uuidString)"
            )
            assertions.equal(response, "OK")
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/a")
            TerminalMutationBus.shared.drainForTesting()
            assertions.equal(dispatcher(for: panel).directorySnapshot(), "/a")
        }
    }

    // MARK: - Normalization: file:// and padded paths publish the plain path

    @Test func fileURLAndPaddedPathPublishPlainPath() throws {
        try withRegisteredWorkspace { workspace, panel in
            let target = try makeDirectory("normalize")
            defer { try? FileManager.default.removeItem(at: target) }
            seedStaleOSC7(panel, directory: "/a")

            let fileURLReport = v2ReportPWD(
                workspaceID: workspace.id,
                surfaceID: panel.id,
                path: "file://\(target.path)"
            )
            assertions.isTrue(fileURLReport.contains("\"ok\":true"), fileURLReport)
            assertions.equal(dispatcher(for: panel).directorySnapshot(), target.path)

            let paddedResponse = TerminalController.shared.handleSocketLine(
                "report_pwd \"  \(target.path)  \" --tab=\(workspace.id.uuidString) --panel=\(panel.id.uuidString)"
            )
            assertions.equal(paddedResponse, "OK")
            assertions.equal(dispatcher(for: panel).directorySnapshot(), target.path)
            TerminalMutationBus.shared.drainForTesting()
        }
    }
}
