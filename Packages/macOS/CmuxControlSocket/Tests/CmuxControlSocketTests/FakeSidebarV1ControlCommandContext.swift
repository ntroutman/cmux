import Foundation
@testable import CmuxControlSocket

@MainActor
final class FakeSidebarV1ControlCommandContext: ControlCommandContext {
    var workspaceLoadingResult: ControlSidebarWorkspaceLoadingState?
    var workspaceLoadingCall: (tabArg: String?, key: String, on: Bool)?
    // Test-only synchronous seam: calls and reads are serial within each test.
    var manualPullRequestAvailable = true
    nonisolated(unsafe) var manualPullRequestCall: (
        tabArg: String?, number: Int, label: String, url: URL, state: String, branch: String?
    )?
    nonisolated(unsafe) var manualPullRequestClearTab: String?
    nonisolated(unsafe) var statusClearCall: (
        target: ControlSidebarTabTarget,
        key: String,
        panelID: UUID?
    )?
    nonisolated(unsafe) var agentPIDClearCall: (
        target: ControlSidebarTabTarget,
        key: String,
        panelID: UUID?,
        clearStatus: Bool,
        requireOwnedKey: Bool
    )?
    nonisolated(unsafe) var shellStateCall: (
        scope: ControlSidebarPanelScope,
        stateRawValue: String
    )?
    nonisolated(unsafe) var scopedDirectoryPublishCall: (
        scope: ControlSidebarPanelScope,
        directory: String
    )?
    nonisolated(unsafe) var scopedDirectoryUpdateCall: (
        scope: ControlSidebarPanelScope,
        directory: String,
        displayLabel: String?
    )?
    nonisolated(unsafe) var directoryUpdateCall: (
        tabArg: String?,
        panelArg: String?,
        directory: String,
        displayLabel: String?
    )?
    /// Ordered record of the pwd seam calls so a test can assert the in-hop
    /// publish precedes the queued record write.
    nonisolated(unsafe) var directoryCallLog: [String] = []
    nonisolated(unsafe) var statusUpsertCall: (
        target: ControlSidebarTabTarget,
        key: String,
        value: String,
        icon: String?,
        panelID: UUID?,
        workState: ControlSidebarAgentWorkState?
    )?

    nonisolated func controlSurfaceParseShellActivityState(
        _ rawState: String
    ) -> String? {
        switch rawState {
        case "prompt": "promptIdle"
        case "running": "commandRunning"
        default: nil
        }
    }

    nonisolated func controlSidebarIsValidPullRequestState(_ raw: String) -> Bool {
        ["open", "merged", "closed"].contains(raw)
    }

    func controlSidebarAttachManualPullRequest(
        tabArg: String?,
        number: Int,
        label: String,
        url: URL,
        statusRawValue: String,
        branch: String?
    ) -> Bool {
        guard manualPullRequestAvailable else { return false }
        manualPullRequestCall = (tabArg, number, label, url, statusRawValue, branch)
        return true
    }

    func controlSidebarClearManualPullRequest(tabArg: String?) -> Bool {
        guard manualPullRequestAvailable else { return false }
        manualPullRequestClearTab = tabArg
        return true
    }

    nonisolated func controlSidebarScheduleStatusUpsert(
        target: ControlSidebarTabTarget,
        key: String,
        value: String,
        icon: String?,
        color: String?,
        url: URL?,
        priority: Int,
        format: ControlSidebarMetadataFormat,
        panelID: UUID?,
        pid: Int32?,
        workState: ControlSidebarAgentWorkState?
    ) {
        statusUpsertCall = (target, key, value, icon, panelID, workState)
    }

    nonisolated func controlSidebarScheduleStatusClear(
        target: ControlSidebarTabTarget,
        key: String,
        panelID: UUID?
    ) {
        statusClearCall = (target, key, panelID)
    }

    nonisolated func controlSidebarScheduleAgentPIDClear(
        target: ControlSidebarTabTarget,
        key: String,
        panelID: UUID?,
        clearStatus: Bool,
        requireOwnedKey: Bool
    ) {
        agentPIDClearCall = (target, key, panelID, clearStatus, requireOwnedKey)
    }

    nonisolated func controlSidebarScheduleScopedShellState(
        scope: ControlSidebarPanelScope,
        stateRawValue: String
    ) {
        shellStateCall = (scope, stateRawValue)
    }

    func controlSidebarTabManagerAvailable() -> Bool { true }

    func controlSidebarPublishScopedDirectorySnapshot(
        scope: ControlSidebarPanelScope,
        directory: String
    ) {
        scopedDirectoryPublishCall = (scope, directory)
        directoryCallLog.append("publish")
    }

    nonisolated func controlSidebarScheduleScopedDirectoryUpdate(
        scope: ControlSidebarPanelScope,
        directory: String,
        displayLabel: String?
    ) {
        scopedDirectoryUpdateCall = (scope, directory, displayLabel)
        directoryCallLog.append("schedule")
    }

    func controlSidebarUpdateDirectory(
        tabArg: String?,
        panelArg: String?,
        directory: String,
        displayLabel: String?
    ) -> ControlSidebarPanelWriteResolution {
        directoryUpdateCall = (tabArg, panelArg, directory, displayLabel)
        directoryCallLog.append("fallback")
        return .done
    }

    func controlSidebarSetWorkspaceLoading(
        tabArg: String?,
        key: String,
        on: Bool
    ) -> ControlSidebarWorkspaceLoadingState? {
        workspaceLoadingCall = (tabArg, key, on)
        return workspaceLoadingResult
    }
}
