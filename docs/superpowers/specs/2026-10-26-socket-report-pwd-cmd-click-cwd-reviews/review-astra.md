==> model: anthropic-gpt-6-astra
==> cmux: launching via wrapper shim so cmux hooks load
{
  "verdict": "reject",
  "summary": "The stale-snapshot diagnosis is supported. Approach A is the right starting point, but its claimed ordering guarantee is false, and the brief omits the model's acceptance/normalization contract. Recommend D: A with ingress ordering and accepted-directory propagation, without changing reader precedence.",
  "findings": [
    {
      "id": "R1",
      "severity": "reject",
      "summary": "A lock does not make socket and OSC reports follow arrival order.",
      "document_lines": "61-67",
      "evidence": [
        "Sources/TerminalController+ControlSidebarContextSupport.swift:292-314 queues explicitly scoped reports and performs the directory mutation later.",
        "Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/Sidebar/ControlCommandCoordinator+SidebarReportsV1.swift:294-300 returns OK after enqueueing, before applying the report.",
        "Sources/GhosttyCurrentDirectoryActionDispatcher.swift:61-82 writes the snapshot immediately, then queues delivery.",
        "Sources/GhosttyCurrentDirectoryActionDispatcher.swift:91-107 later applies that action to the workspace without checking whether another source has superseded it.",
        "Sources/TerminalNotificationQueue.swift:344-373,394-403 orders socket mutations on its own queue, not against the dispatcher's AsyncStreams."
      ],
      "failure_scenario": "A scoped socket report for /agent is acknowledged but remains queued. A later OSC report for /shell immediately updates the snapshot. The socket mutation then drains and A overwrites the snapshot with /agent. The later shell cd loses. Conversely, an older OSC action can deliver after a newer applied socket report and overwrite the workspace record while leaving the snapshot unchanged.",
      "required_change": "Define arrival at a specific app admission boundary and preserve that ordering across deferred work. Do not claim that locking assignments alone synchronizes the two stores. Cover both interleavings, including a newer v2 report overtaking an older queued legacy report."
    },
    {
      "id": "R2",
      "severity": "needs_work",
      "summary": "The proposed helper cannot infer an accepted local directory from the current update API.",
      "document_lines": "64-66",
      "evidence": [
        "Sources/TabManager+SidebarGitHosting.swift:114-123 returns Void after selecting the cloud, remote or local route.",
        "Sources/TabManager.swift:2603-2609 and Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Service/SidebarGitMetadataServing.swift:22-28 also expose Void directory updates.",
        "Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Service/SidebarGitMetadataService+SurfaceEvents.swift:56-64 normalizes the input and can stop when the model rejects it.",
        "Sources/Workspace.swift:6336-6353 can reject a report; its accepted value can differ from the input.",
        "Sources/Workspace+RestoredWorkingDirectoryGuard.swift:23-38,41-60 preserves restored logical spelling or rejects fallback reports.",
        "Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Model/String+DirectoryNormalization.swift:8-16 converts file URLs into filesystem paths."
      ],
      "failure_scenario": "Choosing the local branch does not establish that a write occurred. A restored-directory guard can reject the report, yet a helper that copies the raw socket argument would still change cmd-click. A file URL or symlink-equivalent report can also produce different model and snapshot values.",
      "required_change": "Specify an explicit accepted-local result carrying the accepted filesystem path, distinct from rejected/remote/cloud outcomes. Propagate it through the actual update chain, or document another acceptance-aware seam. Do not call the workspace mutator twice to discover acceptance: the restore guard changes state. Same-directory accepted reports must still refresh a stale snapshot."
    },
    {
      "id": "R3",
      "severity": "needs_work",
      "summary": "The claim that OPEN_URL necessarily reads on the serialized PTY thread is not established by this code.",
      "document_lines": "28-29,45-48",
      "evidence": [
        "Sources/GhosttyCurrentDirectoryActionDispatcher.swift:4-6 documents intended PTY confinement, but provides no synchronization.",
        "Sources/GhosttyTerminalView.swift:3131-3137 explicitly supports callbacks already running on main.",
        "Sources/GhosttyTerminalView.swift:8615-8619,8740-8764 drives the native mouse release from AppKit and scopes link authorization around that synchronous call.",
        "Sources/GhosttyTerminalView.swift:7871-7879 calls ghostty_surface_mouse_button directly.",
        "Sources/GhosttyTerminalView.swift:3691-3708 snapshots before performOnMain, which does not itself establish the calling thread."
      ],
      "required_change": "Distinguish PTY-originated actions from pointer-originated callbacks. Treat the snapshot as shared across callback and main-actor access. The checked-out Ghostty source directory is empty, so the native serialization guarantee could not be independently verified here."
    },
    {
      "id": "R4",
      "severity": "needs_work",
      "summary": "The downstream plan omits existing Claude cwd reporting and its deliberately narrower semantics.",
      "document_lines": "39-41",
      "evidence": [
        "CLI/CMUXCLI+ClaudeHookPaneDirectory.swift:21-39,124-137 already sends scoped legacy report_pwd commands.",
        "CLI/cmux.swift:31492-31499,31617-31623,31904-31909 invokes that helper from existing hook handling.",
        "CLI/CMUXCLI+ClaudeHookPaneDirectory.swift:72-92 reports another checkout's root, otherwise the launch directory; it does not follow every hook cwd.",
        "CLI/cmux.swift:32405-32415 restores the launch directory at SessionEnd except for clear.",
        "CLI/CMUXCLI+ClaudeHookSettings.swift:11-24 and Resources/bin/cmux-claude-wrapper:2065-2076 define the existing hook sets without CwdChanged."
      ],
      "required_change": "Rebase the downstream work on the existing reporter. Explicitly choose exact session cwd versus the current checkout-root policy, preserve session-ownership and exit cleanup, and avoid adding a duplicate SessionStart writer. Verify CwdChanged availability separately; this repository does not establish that external event contract."
    }
  ],
  "thread_confinement": {
    "confirmed": [
      "The PWD handler reaches enqueue without a main-actor hop: Sources/GhosttyTerminalView.swift:3548-3560 and Sources/GhosttyNotificationScrollRuntimeBridge.swift:12-26.",
      "The socket mutation bodies are main-actor work: Sources/TerminalController.swift:129-130 and Sources/TerminalController+ControlSidebarContextSupport.swift:292-314.",
      "The dispatcher-reference replacement is performed before runtime attachment in the inspected production construction path: Sources/Panels/TerminalPanel.swift:234; Sources/Panels/TerminalPanel+NotificationScroll.swift:6-21; Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Surface/TerminalSurface.swift:770-799."
    ],
    "consequence": "Protect every access to mutable snapshot/order state with one lock. Keep the critical section limited to scalar/value-state access; never hold it across model mutation, filesystem normalization, delivery callbacks or a main-thread hop. nonisolated(unsafe) on the dispatcher reference is not synchronization. No additional main-thread hop is needed on the Ghostty path."
  },
  "recommendation": {
    "choice": "D: acceptance-aware, ordered A",
    "status": "Design recommendation, not an implemented or tested fix.",
    "mechanism": [
      "Keep the surface-owned snapshot and the current TerminalLinkOpenCoordinator precedence.",
      "Use one shared socket-report application path for legacy fallback, legacy queued reports and v2.",
      "Assign an internal per-surface ordering token before deferred socket application and when OSC reports enter the dispatcher. Publication must reject an older report when a newer accepted report has superseded it.",
      "Carry ordering through ordinary OSC delivery so a delayed action cannot roll the workspace back. Keep replay-boundary delivery independent of ordinary stale-update filtering.",
      "Publish only the accepted local filesystem path identified in R2. Preserve cloud rejection, remote routing, pending remote reports and nonterminal-panel behavior.",
      "Keep ordering internal: no new socket parameter, database schema, remote service or deploy sequence is required."
    ],
    "notification_decision": "Recommendation: let accepted local socket reports also update desktop-notification project-hook cwd, so both consumers use the reported effective directory. This is a product-policy choice, not an existing invariant. State it explicitly and test it: the directory selects project hooks, not just notification text.",
    "notification_evidence": [
      "Sources/GhosttyTerminalView.swift:3569-3575",
      "Sources/GhosttyDesktopNotificationIngress.swift:58-68",
      "Sources/TerminalNotificationStore+HookResolution.swift:51-56"
    ],
    "alternatives": {
      "A": "Smallest structural starting point, but incorrect as written because lock acquisition order at delayed application is not report arrival order, and accepted model values are not exposed.",
      "B": "Reject. The workspace is neither a synchronous union nor exclusively a record of live reports. OSC delivery is asynchronous and coalesced; restore, probes and transfer also write metadata. Reversing precedence additionally overrides callback-time context supplied by other TerminalLinkOpenRequest producers. Evidence: Sources/GhosttyCurrentDirectoryActionDispatcher.swift:23-52,91-107; Sources/Workspace.swift:2487-2491,11783-11785; Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Service/SidebarGitMetadataService+Probe.swift:349-375.",
      "C": "Not correct merely by adding timestamps. Stamps must share an ordering domain and be captured before asynchronous work, with rejection and replay semantics defined. Stamping every workspace metadata writer and arbitrating at the reader is broader than necessary. D versions live report propagation while retaining one snapshot-first reader."
    }
  },
  "impact_inventory": [
    {
      "area": "Dispatcher payload and tests",
      "impact": "Ordering crosses GhosttyCurrentDirectoryAction, not just the dispatcher field. Its only construction site is enqueue. Preserve the custom-delivery test seam and both bounded streams.",
      "evidence": [
        "Sources/GhosttyCurrentDirectoryAction.swift:3-25",
        "Sources/GhosttyCurrentDirectoryActionDispatcher.swift:23-52,71-82",
        "cmuxTests/GhosttyCurrentDirectoryActionDispatcherTests.swift:13-65"
      ]
    },
    {
      "area": "Replay",
      "impact": "Boundary actions must still reach the scrollback replay state machine even when ordinary cwd delivery is stale. Currently enqueue also puts boundary strings in latestDirectory before deliver filters them; the brief should explicitly preserve or separately address that existing behavior.",
      "evidence": [
        "Sources/GhosttyCurrentDirectoryActionDispatcher.swift:67-81,94-99",
        "Sources/GhosttySurfaceScrollView+NotificationScroll.swift:331-369"
      ]
    },
    {
      "area": "Acceptance-result interface",
      "impact": "If acceptance is returned through the existing chain, include TabManager, SidebarGitMetadataServing, SidebarGitMetadataService and SidebarGitHosting/Workspace in the change. Preserve metadata refresh behavior rather than bypassing the service.",
      "evidence": [
        "Sources/TabManager.swift:2603-2609",
        "Sources/TabManager+SidebarGitHosting.swift:99-128",
        "Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Service/SidebarGitMetadataServing.swift:22-28",
        "Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Service/SidebarGitMetadataService+SurfaceEvents.swift:56-108"
      ]
    },
    {
      "area": "Other model writers",
      "impact": "Do not make every panelDirectories assignment publish a fresh live snapshot. Git-probe reaffirmation, session restore, agent-panel initialization, detached-panel attachment and the surfaceDirectories setter are not new socket/OSC observations.",
      "evidence": [
        "Packages/macOS/CmuxSidebarGit/Sources/CmuxSidebarGit/Service/SidebarGitMetadataService+Probe.swift:349-375",
        "Sources/Workspace.swift:2482-2494,3735-3738,11086-11096,11783-11785"
      ]
    },
    {
      "area": "Remote/cloud and target resolution",
      "impact": "Use per-panel provenance rather than isRemoteWorkspace as the local eligibility test: mixed workspaces can contain local terminals. Retain v2's pending-remote path. Keep Dock exclusion and existing membership checks; terminalPanel(for:) is only a direct TerminalPanel cast.",
      "evidence": [
        "Sources/Workspace+SidebarDirectories.swift:63-78,109-119",
        "Sources/TerminalController+ControlSurfaceContext4.swift:108-134,269-290",
        "Sources/Workspace.swift:5622-5624,8331-8350",
        "Sources/TerminalController+ControlSidebarContextSupport.swift:300-306"
      ]
    },
    {
      "area": "Other click routes and request producers",
      "impact": "There are no additional production readers of this dispatcher's directorySnapshot beyond OPEN_URL and desktop notifications in the searched tree. However, word-path fallback and hover use workspace cwd directly; context-menu opening supplies its own captured cwd; GitHub-reference and cloud-guest requests supply nil. Keep these paths unchanged and cover fallback consistency.",
      "evidence": [
        "Sources/GhosttyTerminalView.swift:3572-3573,3691-3695,8958-8965,9361-9367",
        "Sources/GhosttyNSView+LinkContextMenu.swift:119-136",
        "Sources/Cloud/CloudGuestURLService.swift:110-117"
      ]
    }
  ],
  "behavioral_test_plan": {
    "primary_regression": [
      "Copy the serialized AppDelegate/window/TabManager fixture from cmuxTests/AppDelegateIssue2907RoutingTests.swift:100-145 and its JSON socket helpers at :28-60.",
      "Create separate old and new temporary directories, each containing the same relative filename with no line suffix. Use an ordinary file, not a folder or HTML file, to avoid unrelated open branches.",
      "Seed the actual panel.hostedView.surfaceView.currentDirectoryActionDispatcher through enqueue with the old directory. Borrow the enqueue arguments from cmuxTests/DockWorkingDirectoryInheritanceTests.swift:138-148, but do not leave the seeded dispatcher as an unattached local variable.",
      "Send scoped report_pwd through handleSocketLine and drain TerminalMutationBus. Construct TerminalLinkOpenRequest with the actual view dispatcher's snapshot, exactly as Sources/GhosttyTerminalView.swift:3691-3695 does.",
      "Pass that request through TerminalLinkOpenCoordinator.open with a recording local container or FileOpening collaborator. Assert the resulting absolute file path is in the new directory. Reuse the recording seams in cmuxTests/TerminalLinkOpenCoordinatorTests.swift:867-893.",
      "Parameterize legacy scoped, legacy fallback and v2 surface.report_pwd. Include a legacy display label plus --path and assert that the label never becomes the resolution directory."
    ],
    "ordering_regressions": [
      "Suspend bus drains, submit and acknowledge a legacy report, enqueue a later OSC directory, then drain the bus. Opening the relative file must use the later OSC directory. The deterministic controls exist at Sources/TerminalNotificationQueue.swift:406-439.",
      "Exercise an older OSC action delivered after an accepted socket report and verify both final workspace cwd and actual resolved file path.",
      "Exercise an older queued legacy report followed by a newer v2 report before draining; the newer report must win.",
      "Exercise a later OSC report after an already applied socket report, with no wait for OSC model delivery before reading the snapshot."
    ],
    "additional_coverage": [
      "Accepted same-directory reports; rejected restore-guard reports; accepted logical-path normalization; file-URL normalization.",
      "Cloud and remote reports do not gain local snapshot publication; a local pane inside a remote workspace still does. Existing mixed-workspace fixture: cmuxTests/WorkspaceRemoteDirectoryProvenanceTests.swift:13-50.",
      "Replay boundaries still deliver under ordinary-report flooding; extend cmuxTests/GhosttyCurrentDirectoryActionDispatcherTests.swift:13-65.",
      "Desktop notifications capture the deliberately selected effective cwd, while remote hook-directory suppression remains unchanged."
    ],
    "proof_boundary": "The coordinator's recorded absolute output proves the snapshot drives real local file resolution, rather than merely proving that a dictionary changed. It does not prove native hit-testing or pointer authorization. Keep that distinction explicit. Avoid a test that supplies workingDirectory: newDirectory directly: it bypasses the defect.",
    "red_first": "Commit the failing behavioral test before the implementation and run the same focused selection on both revisions. The supported focused execution wrapper is documented at skills/cmux-testing/references/local-vs-ci-validation.md:63-85. A new test file also requires test wiring. No tests were executed during this read-only review."
  },
  "downstream_wrapper_requirements": [
    {
      "requirement": "Reuse the existing cwd reporter and decide whether exact cwd should replace its checkout-root policy.",
      "evidence": "CLI/CMUXCLI+ClaudeHookPaneDirectory.swift:72-92"
    },
    {
      "requirement": "Preserve explicit workspace/surface targeting and stale or nested-session suppression. Never fall back to whichever pane is focused.",
      "evidence": "CLI/CMUXCLI+ClaudeHookPaneDirectory.swift:124-137; CLI/cmux.swift:31460-31477,31595-31623"
    },
    {
      "requirement": "Preserve SessionEnd restoration. Shell reporting is deduplicated, so it cannot be assumed to repair the directory after every agent exit.",
      "evidence": "CLI/cmux.swift:32405-32415; Resources/shell-integration/cmux-zsh-integration.zsh:2301-2306"
    },
    {
      "requirement": "Keep generated hook settings and the wrapper's exact-byte fast path in agreement if adding an event.",
      "evidence": "CLI/CMUXCLI+ClaudeHookSettings.swift:11-31; Resources/bin/cmux-claude-wrapper:2039-2043,2065-2090"
    },
    {
      "requirement": "Document that legacy OK means queued, not applied. An immediately subsequent click is not guaranteed to observe the report merely because the hook received OK.",
      "evidence": "Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/Sidebar/ControlCommandCoordinator+SidebarReportsV1.swift:294-300"
    },
    {
      "requirement": "Keep new ordering tokens internal. If remote wrappers use v2, use reviewed path/directory parameters; the local handler's cwd alias is not in the relay schema.",
      "evidence": "Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/Surface/ControlCommandCoordinator+Surface3.swift:385-394; Packages/macOS/CmuxRemoteWorkspace/Sources/CmuxRemoteWorkspace/Relay/RemoteRelayRoutingSchema.swift:22-24"
    }
  ],
  "verification_limits": [
    "Read-only repository inspection; no files edited, builds launched or git write commands run.",
    "The reported tagged-build reproduction and the two historical commit descriptions were not independently verified.",
    "Native Ghostty threading could not be fully verified because its source directory is unpopulated.",
    "External Claude Code hook-event support was not verified."
  ]
}