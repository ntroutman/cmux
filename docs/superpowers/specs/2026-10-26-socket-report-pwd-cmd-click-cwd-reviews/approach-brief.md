# Approach review: make socket `report_pwd` reach the cwd that cmd-click resolves against

Repository: cmux (macOS app, Swift). Review from the repository root; all paths below are relative to it.
This is a design brief, not a spec. The question is WHICH mechanism to build. Verify every claim against the code.

## The bug

cmux keeps two per-surface current-directory stores and the cmd-click handler reads the one that socket reports never write.

1. **OSC 7 snapshot** — `GhosttyCurrentDirectoryActionDispatcher.latestDirectory`
   (`Sources/GhosttyCurrentDirectoryActionDispatcher.swift:14`, written in `enqueue` at ~:67, read by `directorySnapshot()` at ~:87).
   Written only when Ghostty parses an OSC 7 sequence from the pty: `GHOSTTY_ACTION_PWD` in `Sources/GhosttyTerminalView.swift` ~:3548
   → `GhosttyApp.handleCurrentDirectoryAction` (`Sources/GhosttyNotificationScrollRuntimeBridge.swift` ~:12) → `enqueue`.
   `enqueue` then yields an action onto an AsyncStream whose main-actor consumer (`deliver`, ~:91) calls
   `TabManager.updateReportedSurfaceDirectory` (so OSC 7 ALSO writes store 2, asynchronously) and, for right-sidebar-dock surfaces only,
   `TerminalSurface.recordReportedWorkingDirectory`.

2. **Workspace record** — `Workspace.panelDirectories[panelId]`, written via `TabManager.updateReportedSurfaceDirectory`
   (`Sources/TabManager+SidebarGitHosting.swift` ~:114) which gates: returns early for cloud-provenance surfaces
   (`cloudDirectoryProvenanceRequired`), routes to `updateRemoteSurfaceDirectory` when `!allowsLocalDirectoryFallback`, else `updateSurfaceDirectory`.
   Both socket entrypoints end here:
   - legacy `report_pwd <path|label> [--path=] [--tab=] [--panel=]`: `Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/Sidebar/ControlCommandCoordinator+SidebarReportsV1.swift` ~:262 `sidebarReportPwd`
     → `controlSidebarScheduleScopedDirectoryUpdate` (explicit scope; enqueued on `TerminalMutationBus`) or `controlSidebarUpdateDirectory` (fallback)
     → `controlSidebarApplyDirectoryReport` in `Sources/TerminalController+ControlSidebarContextSupport.swift` ~:338.
   - v2 `surface.report_pwd`: `Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/Surface/ControlCommandCoordinator+Surface3.swift` ~:377 `surfaceReportPWD`
     → `controlSurfaceReportPWD` in `Sources/TerminalController+ControlSurfaceContext4.swift` ~:103.

**The reader.** `GHOSTTY_ACTION_OPEN_URL` (`Sources/GhosttyTerminalView.swift` ~:3681) builds `TerminalLinkOpenRequest` with
`workingDirectory: surfaceView.currentDirectoryActionDispatcher.directorySnapshot()` BEFORE `performOnMain`, i.e. on the Ghostty action-callback thread.
`TerminalLinkOpenCoordinator.resolvedWorkingDirectory` (`Sources/TerminalLinkOpenCoordinator.swift` ~:363) returns the request's snapshot when
non-empty and consults `container.terminalLinkWorkingDirectory(for:)` (→ `panelDirectories` via `CommandClickFileOpenRouter.resolveWorkingDirectory`,
`Sources/CommandClickFileOpenRouter.swift` ~:47; dock → `DockSplitStore.terminalWorkingDirectory`) only when the snapshot is empty.

So once a surface has ever received OSC 7, a later socket `report_pwd` changes the sidebar/title directory but not what cmd-click resolves against.
Reproduced 2026-10-24 in a tagged build; writing the OSC 7 escape directly to the surface tty fixes the same click.

## Why it matters

The socket is the only channel a non-shell process (a Claude Code hook, an agent launcher, cmux's own `Resources/bin/cmux-claude-wrapper` hooks) can use.
Claude Code changes its own cwd (worktrees, `/cd`) without the shell moving, so OSC 7 goes stale. The downstream epic will have the wrapper's hooks send
`report_pwd` on SessionStart / CwdChanged; that only helps if `report_pwd` reaches the cwd cmd-click uses.

## Constraints

- **Thread confinement.** The dispatcher's doc comment says `latestDirectory` is confined to Ghostty's serialized PTY/action callback. The OSC 7 write and the
  OPEN_URL read both happen on that thread (the `_scrollbarLock` comment near `Sources/GhosttyTerminalView.swift:3957` says the action callback fires on
  Ghostty's I/O thread). The socket handlers run on the main actor. `currentDirectoryActionDispatcher` is `nonisolated(unsafe) var` on `GhosttyNSView` (~:3953)
  with a SAFETY note that replay setup replaces it before runtime attachment and callbacks only read it. Verify this; it decides whether approach A needs a lock.
- **OSC 7 must stay authoritative when both arrive**: a shell `cd` after a socket report must still win.
- **Both socket entrypoints** (legacy and v2) must behave identically (cmux-shared-behavior rule: one mutation path for a behavior with several entrypoints).
- **Out of scope**: right-sidebar dock terminals (neither socket handler can target them today: both check `tab.panels.keys`); remote/cloud semantics
  beyond "don't regress them"; the Ghostty submodule is not to be modified.
- App-linked code must stay Swift 6.0 compatible. Keep the typing/rendering hot path free of new main-thread work.
- Must be covered by a behavioral test in `cmuxTests/` that fails on the base. Existing patterns: `cmuxTests/AppDelegateIssue2907RoutingTests.swift` ~:135 drives
  `TerminalController.shared.handleSocketLine("report_pwd ...")` then `TerminalMutationBus.shared.drainForTesting()`;
  `cmuxTests/DockWorkingDirectoryInheritanceTests.swift` ~:138 constructs a dispatcher with a custom delivery closure and calls `enqueue` with
  `sourcePanel.hostedView.surfaceView` / `sourcePanel.surface`; `cmuxTests/TerminalLinkOpenCoordinatorTests.swift` constructs `TerminalLinkOpenRequest` directly.

## Candidate approaches

### A. Socket report also writes the snapshot (two stores stay, kept in sync)
Add a method on `GhosttyCurrentDirectoryActionDispatcher`, e.g. `recordExternallyReportedDirectory(_:)`, that sets `latestDirectory` WITHOUT enqueuing an action
(so `deliver` does not re-run `updateReportedSurfaceDirectory`). Guard `latestDirectory` with an `NSLock` (or `OSAllocatedUnfairLock`) taken by `enqueue`,
`directorySnapshot()` and the new method. Add ONE shared helper in TerminalController (e.g. next to `controlSidebarApplyDirectoryReport`) that applies the
workspace-record update and then, when the write went to the local store, locates `tab.terminalPanel(for: surfaceId)?.hostedView.surfaceView` and calls the new method.
Make `controlSurfaceReportPWD` and `controlSidebarApplyDirectoryReport` both go through that helper. OSC 7 wins by wall-clock arrival order because both write the same field.
- Pros: smallest blast radius; cmd-click precedence unchanged for every existing path; OSC 7 ordering preserved for free.
- Cons: introduces a lock on a field that was lock-free by design; `directorySnapshot()` has a second consumer (`hookDirectory` for desktop notifications,
  `GhosttyTerminalView.swift` ~:3572) which would now also see socket reports — decide whether that is desired; needs the GhosttyNSView lookup from the controller.

### B. Reverse the reader's precedence (one store becomes authoritative for cmd-click)
Keep both writers as they are. Change `resolvedWorkingDirectory` (or the OPEN_URL request construction) to prefer `container.terminalLinkWorkingDirectory(for:)`
and fall back to the snapshot. Rationale: OSC 7 already writes `panelDirectories` via `deliver`, so the workspace record is the union of both sources in arrival order.
- Pros: no cross-thread write, no lock, no new dispatcher API; a single reader change.
- Cons: changes cmd-click semantics for every surface, not just socket-reported ones: `updateReportedSurfaceDirectory` skips cloud-provenance surfaces and routes
  remote ones elsewhere, and `deliver` skips replay-boundary actions, so the record can lag or differ from the snapshot; the OSC 7 → record write is asynchronous
  (main-actor hop) so a cd immediately followed by a click could observe the previous directory; `CommandClickFileOpenRouter.resolveWorkingDirectory` falls through to
  `requestedWorkingDirectory` and `workspace.currentDirectory`, which can shadow a legitimately empty snapshot; the two July 2026 commits
  (`063957bfdd` "make terminal cwd independent of container", `39c5cbe10e` "keep dock cwd cache authoritative") deliberately moved toward surface-owned cwd.
  Also check who else consumes `TerminalLinkOpenRequest.workingDirectory`.

### C. Sequence-stamped stores; reader picks the newest
Give both stores a monotonic sequence (or timestamp) per surface and have the reader take the newer. Correct by construction but the most code and the most new surface area.
Only worth it if A and B both have a blocker.

## What I want from this review

1. Verify or refute the thread-confinement claim with file:line evidence, and state what approach A needs because of it.
2. Pick A, B or C (or propose D) for the smallest correct change that satisfies the constraints, and say what the losing options get wrong about this code.
3. Name every caller/consumer the chosen approach touches that this brief does not mention (e.g. other `directorySnapshot()` readers, other writers of
   `panelDirectories`, remote/cloud gating, session restore replay boundaries).
4. Say how to write the red-first behavioral test for the chosen approach: which seam to observe, which existing test fixture to copy, and whether the observation
   actually proves cmd-click would resolve against the new directory (not just that a store changed).
5. Anything the downstream wrapper-hook work needs from this change that is not stated here.
