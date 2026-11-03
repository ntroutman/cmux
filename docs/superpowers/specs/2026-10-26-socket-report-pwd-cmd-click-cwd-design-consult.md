# Design Deliberation: Socket `report_pwd` reaches the directory cmd-click resolves against

- **Source:** `docs/superpowers/specs/2026-10-26-socket-report-pwd-cmd-click-cwd-design.md`
- **Date:** 2026-10-26
- **Rounds:** 4 (max)
- **Mode:** converge
- **Personas:** devils-advocate, pragmatist, simplifier, user, astra (GPT-6, repo-grounded), sol (GPT-5.6, repo-grounded)
- **Final verdict:** Needs Work — substantively converged; every architectural/correctness objection was resolved and both repo-grounded reviewers explicitly marked them resolved. The two standing rejects at the final (max) round were narrow factual corrections to the relay prose and test plan; the Design Lead verified and applied them to the on-disk spec post-round-4. A quick confirmatory re-review of the relay/test section is recommended before implementation, since the correctness reviewers did not sign off on the exact final text.

The design describes a small cmux change: make a socket `report_pwd` publish to the terminal surface's OSC-7 directory snapshot (read by Ghostty `GHOSTTY_ACTION_OPEN_URL` cmd-click) through one shared, lock-guarded app-side helper, so an agent that moves its own cwd fixes the directory cmd-click resolves against.

---

## Round 1 (original document)

**devils-advocate — needs_work (0.85)**
- Assumes the cross-thread snapshot read becomes safe with a lock; verify via testing.
- Does not address the performance impact of adding a lock to a lock-free field.
- Says the display label is never published but not why / the implications.
- Needs a more detailed rollback plan.
- Needs a fuller A-vs-B/C trade-off discussion.

**pragmatist — approve (1.0)**
- Correctly identifies root cause (two unsynchronized stores); minimal targeted fix.
- Synchronous update before ack correctly addresses the race with later shell events.
- Lock correctly framed as a pre-existing-race fix, not new risk.
- Red-first test strategy over all entrypoints/ordering/provenance gives confidence.
- Wisely scopes to local surfaces, avoids remote/cloud logic.
- Detail (paths, fixtures) makes the "small change" sizing credible.

**simplifier — approve (0.95)**
- Maintains existing cmd-click precedence; adds lock-guarded snapshot update.
- Publishes before ack, preserving operation order.
- Modular separation (dispatcher / helper / call sites).
- Extensive testing; avoids unnecessary complexity.

**user — approve (0.9)**
- Fixes a frustrating cmd-click bug; no learning curve; consistent, trustworthy resolution; last-writer-wins prevents misdirection.

**astra — reject (0.96)**
- **Missing second reader:** cmd-click also resolves through the word-under-cursor fallback (`handleCommandClickRelease` → `CommandClickFileOpenRouter.resolveWorkingDirectory` → `workspace.panelDirectories`), not `directorySnapshot()`. For the scoped legacy path this reads the old record while OPEN_URL uses the new snapshot. Scope the guarantee or cover the fallback.
- **Ordering not wall-clock:** publishing before ack orders only against OSC 7 received *after* ack. The legacy hop can wait on `DispatchQueue.main.sync`; an OSC 7 arriving during the wait can be overwritten by the older report. Define ordering at publication, narrow it, or preserve ingress order and test it.
- **Normalizer:** `normalizedGitProbeDirectory` returns the original for whitespace-only input, so it won't clear the snapshot; use `nonEmptyNormalizedGitProbeDirectory`.

**sol — reject (0.98)**
- **Ordering race (same as astra):** `v2MainSync` blocks on `DispatchQueue.main.sync`; a newer OSC 7 can be overwritten by an older report that was waiting on main. Needs a shared admission token or a narrower definition.
- **Ordering test can't detect it:** the `@MainActor` inline AppDelegate fixture runs `handleSocketLine` inline and can't reproduce a worker report waiting while OSC 7 arrives.
- **Regression oracle underspecified:** default fixture enables supported-file routing, so a file goes to the container's deferred path, not `RecordingFileOpener`; disable it or assert `deferredFilePaths`.
- **Stale follow-on premise:** SessionStart already calls `reportClaudeHookPaneDirectory`, which already sends a scoped `report_pwd`; the remaining follow-on is `CwdChanged` + policy.

### Design Lead revision after Round 1
Verified every astra/sol claim against the repo (all confirmed). Key changes: added a monotonic **arrival stamp** captured at admission on the snapshot + external-record seam to honor wall-clock ordering across the `main.sync` wait; documented the **second cmd-click reader** and scoped the snapshot guarantee to OPEN_URL; switched to **`nonEmptyNormalizedGitProbeDirectory`**; rewrote the ordering test to a **deterministic dispatcher-level** test; specified the **regression oracle** (disable supported-file routing or assert deferred path); **corrected the Intent** (session-start reporting already ships); added **lock-cost, rollback, label-rationale** notes.

---

## Round 2 (revised round 1)

**devils-advocate — needs_work (0.85)** — repeated its five Round-1 points verbatim (all now addressed in-doc: a Lock cost/rollback section, label rationale, expanded A/B/C discussion, and a dispatcher unit test exist). Treated as non-engaging.

**pragmatist — approve (1.0)** — praised the arrival stamp as the correct race fix, the diligence on the `main.sync` wait, deterministic unit tests, and acknowledging the second reader.

**simplifier — approve (0.95)** — accepted the arrival stamp as "necessary complexity"; praised modular separation and focus.

**user — approve (0.95)** — reliable cmd-click; last-writer-wins with the stamp; honest about transient inconsistency.

**astra — reject (0.97)** — *Changed from Round 1:* reader + normalization + regression-oracle + OPEN_URL scoping now resolved. New: **v2 stamp capture is after the hop** (the whole v2 command runs inside `v2MainSync`), so capturing in `controlSurfaceReportPWD` doesn't fix the race; the stamp must be threaded through the v2 seam and the legacy-fallback `controlSidebarUpdateDirectory`. The dispatcher stamp tests prove compare-and-set, not admission-before-hop. And: **convergence overstated** — the record is written by unordered async paths, so the two readers can diverge permanently.

**sol — reject (0.99)** — *Changed from Round 1:* stamp/convergence objections acknowledged; new: **v2 stamp must be carried pre-hop** through `v2MainActorResponse` / `surfaceReportPWD` / `ControlSurfaceContext` + stubs; the **convergence claim conflicts** with async OSC delivery (OPEN_URL reads the newer snapshot while word-fallback reads a stale record indefinitely); the **deterministic test needs `enqueue` to accept an injected stamp**, which its signature lacks.

### Design Lead revision after Round 2
Verified the v2-wrap and the unordered-record claims (confirmed). Decisive call: the arrival stamp cannot be honored cheaply (cross-package plumbing through three hops) and — critically — **protects nothing real**: in the motivating workflow the shell is a stopped background job while the agent is foreground, so it emits no OSC 7 to race. **Removed the stamp**, kept the required lock, **narrowed the ordering goal** to last-writer-by-execution, and **dropped the convergence claim**; simplified the tests accordingly.

---

## Round 3 (revised round 2)

**devils-advocate — needs_work (0.85)** — identical boilerplate again; points remain addressed in-doc.

**pragmatist — approve (1.0)** — endorsed removing the stamp as a justified trade-off; narrowed guarantee realistic; lock is a net correctness win; side effects understood not surprising.

**simplifier — approve (0.9)** — removing the stamp simplifies without losing function; lock-only last-writer-wins sufficient; clear and focused.

**user — approve (0.9)** — core OPEN_URL fix delivered for the real workflow; honest about pre-existing divergence; pragmatic de-prioritization of a sub-ms edge case.

**astra — reject (0.97)** — *Changed:* the v2/convergence objections are **resolved**. New: the **"foreground shell can't race" rationale is wrong** — SessionEnd restores the launch dir via `report_pwd` (can land after the shell's newer OSC 7), and the shell's own cd reports via a detached `_cmux_send_bg report_pwd`; both can make a stale report overwrite the OPEN_URL snapshot within the real workflow, and an arrival stamp would not fix a late-emitted stale report. Remove the unsupported "sub-millisecond" bound (`v2MainSync` wait is unbounded). Revise the anti-goal/accepted-effects to acknowledge this.

**sol — reject (0.98)** — *Changed:* stamp/convergence **resolved**. New: **clearing the snapshot to nil doesn't clear the effective directory** — `updatePanelDirectory` rejects blank and the reader falls back to store 2; choose no-op or define clearing both stores. **Relay consumer omitted** — `surface.report_pwd` is relay-exposed; AGENTS.md requires local-content/ownership/state-exposure + relay-policy analysis for changed v2 methods. **Dock test fixture uses a detached dispatcher**, not the panel's real one that OPEN_URL reads.

### Design Lead revision after Round 3
Verified all five claims (confirmed). Changes: **removed the false safety rationale** and documented the stale-report effect honestly as accepted/self-correcting (Ghostty re-emits OSC 7 at the next prompt); made a **blank report a no-op** (matching `updatePanelDirectory`); added a **"Relay and remote exposure" analysis** per cmux-socket-policy; retargeted tests to the **panel's own dispatcher**; removed the "sub-millisecond" bound.

---

## Round 4 (revised round 3) — final/max round

**devils-advocate — needs_work (0.9)** — identical five points; all addressed in-doc.

**pragmatist — approve (1.0)** — accepting the transient side effect is a pragmatic trade-off; blank no-op improves consistency; the relay analysis is mature; the test-targeting fix makes verification meaningful; contained and low-risk.

**simplifier — approve (0.95)** — honest documentation + no-op + relay analysis + test fix add clarity without new mechanism; design stays lean.

**user — approve (0.8)** — core fix welcome, but uneasy that cmd-click can be "transiently wrong"; even self-correcting staleness can erode trust if noticeable. (Approve, reduced confidence.)

**astra — reject (0.98)** — *Changed:* all prior ordering objections **resolved** ("I no longer require arrival stamps, reader convergence, or delayed-hop ordering tests"). New factual corrections: (1) **`.recorded` ≠ local** — a live remote terminal returns `.recorded`; the safety boundary is the provenance predicates, not the result enum; the `.pending` test can't observe a dispatcher. (2) **Legacy whitespace is reachable** — `report_pwd "   " --tab= --panel=` acknowledges OK (tokenizer preserves quoted whitespace); describe the no-op as protecting a reachable input and add a command-level assertion.

**sol — reject (0.99)** — *Changed:* blank-clear and dispatcher-identity **resolved**. Standing: (1) **relay misclassification** — `.pending` only when a remote workspace has no surface; a live remote surface returns `.recorded`; test a live authenticated remote surface. (2) **legacy whitespace reachable** — add an end-to-end legacy whitespace test. (3) **`CmuxSidebarGit` import** — neither implementation file imports the module that owns the normalizer; state the dependency.

### Design Lead corrections after Round 4 (applied to the on-disk spec)
Round 4 is the max round, so no further review round runs. The standing rejects were narrow factual corrections that would otherwise leave a wrong claim in the spec; all three were verified against the repo and applied:
- `Sources/TerminalController+ControlSurfaceContext4.swift:103-134`: `controlSurfaceReportPWD` returns `.recorded(surfaceID:)` for any resolved surface **including a live remote terminal**; `.pending` only when `tab.isRemoteWorkspace && validSurfaceIds.isEmpty`. Corrected the Call-sites and Relay sections to attribute remote/cloud exclusion to the **provenance predicates**, and retargeted the relay test to a live remote surface.
- Legacy whitespace reachability: reworded the no-op from "defensive floor" to "protects a reachable input," and added an end-to-end legacy whitespace no-op test.
- `Sources/TerminalController+ControlSidebarContextSupport.swift` does not import `CmuxSidebarGit`: noted the required import and placed normalization in the helper so the dispatcher gains no `CmuxSidebarGit` dependency; moved `file://`-normalization testing to the helper level.

---

## Convergence Trace

| Round | devils-advocate | pragmatist | simplifier | user | astra | sol | Consensus? |
|---|---|---|---|---|---|---|---|
| 1 | needs_work (0.85) | approve (1.0) | approve (0.95) | approve (0.9) | reject (0.96) | reject (0.98) | No |
| 2 | needs_work (0.85) | approve (1.0) | approve (0.95) | approve (0.95) | reject (0.97) | reject (0.99) | No |
| 3 | needs_work (0.85) | approve (1.0) | approve (0.9) | approve (0.9) | reject (0.97) | reject (0.98) | No |
| 4 | needs_work (0.9) | approve (1.0) | approve (0.95) | approve (0.8) | reject (0.98) | reject (0.99) | No |

Verdict counts were stable (3 approve / 1 needs_work / 2 reject every round), but the *content* converged sharply: the agent reviewers' reject reasons moved from fundamental design flaws (Round 1) to refined mechanism gaps (Round 2) to rationale/scope corrections (Round 3) to two narrow factual-text/test corrections (Round 4), explicitly marking each prior tier resolved as it was addressed.

## Final Synthesis

### Issues That Converged (agreed and fixed)
- **Ordering semantics.** Original wall-clock claim was false (the socket hop is an unbounded `main.sync` wait); an arrival stamp cannot be captured at admission across the v2 seam without wide plumbing, and does not fix late-emitted stale reports anyway. Resolved to **last-writer-by-execution** with the stale-report effect accepted and documented. Both reviewers explicitly accepted this.
- **Two cmd-click readers.** OPEN_URL reads the snapshot (store 1); the word-fallback reads the workspace record (store 2). Guarantee scoped to OPEN_URL; readers are not forced to converge (store 2's async writes make convergence impossible without re-architecting).
- **Normalization & blank handling.** Use `nonEmptyNormalizedGitProbeDirectory`; a blank/whitespace report is a **no-op** (matching `updatePanelDirectory`), protecting a reachable legacy input.
- **Lock.** Required regardless; guards a single reference; closes a pre-existing data race.

### Issues That Were Resolved During Deliberation
- Stale Intent premise (session-start reporting already ships) — corrected.
- Regression test oracle (supported-file routing) — specified.
- Ordering/dispatcher tests must target the **panel's own dispatcher** — corrected.
- Relay exposure analysis for the changed v2 method — added per cmux-socket-policy.
- `.recorded` vs `.pending` classification and the `CmuxSidebarGit` import — corrected post-round-4.

### Remaining Contentious Points
- **Transient staleness UX (user, 0.8).** A delayed/stale socket report can briefly make cmd-click resolve against an older directory until the next OSC 7. Accepted as self-correcting and symmetric with existing store-2 behavior; the user persona remains mildly uneasy. Not a blocker, but worth a dogfood check on how often it is observable.
- **No clean sign-off from the correctness reviewers on the exact final text.** astra/sol's final rejects were on corrections now applied without a confirming re-review.
- **devils-advocate (needs_work).** Non-engaging across all four rounds (verbatim points already answered in the doc). Low signal; its concrete asks (lock cost, rollback, label rationale, trade-offs) are all in the document.

### Recommended Actions
1. Implement as specified (small change: lock + `recordExternallyReportedDirectory`, one `@MainActor` sidebar requirement, helper called from all three entrypoints, no re-publish at scoped drain).
2. Add `import CmuxSidebarGit` to the helper file; keep normalization in the helper so the dispatcher stays independent of that module.
3. Include the relay-exposure analysis in the PR body and the **live remote surface** relay test (asserts the dispatcher is untouched via provenance), plus the end-to-end **legacy whitespace no-op** test.
4. Write the red-first regression test against the **panel's own dispatcher**, disabling supported-file routing (or asserting `deferredFilePaths`).
5. Optional confirmatory re-review of the relay/test section by one repo-grounded reviewer before merge.
6. Dogfood the stale-report window (SessionEnd restore after a shell `cd`) to confirm it is not noticeably disruptive.

### Deferred
- The `CwdChanged` hook and any CLI cwd-reporting policy broadening (follow-on; unblocked by this change).
- Arrival-ordered store 2 / reader convergence (explicit non-goal; would be approach-B-like re-architecture).
- Right-sidebar Dock terminals (neither socket handler targets them today).

---

## Appendix: Final Revised Document

The full converged spec (with the Round-4 factual corrections applied) was written back to
`docs/superpowers/specs/2026-10-26-socket-report-pwd-cmd-click-cwd-design.md`. Its full text follows.

# Socket `report_pwd` reaches the directory cmd-click resolves against

Date: 2026-10-26. Size: a small, contained change. Status: draft for approval.

## Intent

A socket `report_pwd` (legacy line protocol or v2 `surface.report_pwd`) updates the
sidebar and title directory of a terminal surface but not the directory that
cmd-click uses to resolve a relative file path when the click goes through
Ghostty's `OPEN_URL` action. Once a surface has ever received an OSC 7 sequence from
its shell, every later `OPEN_URL` cmd-click resolves against that last OSC 7 value,
however many socket reports arrive afterwards. Reproduced 2026-10-24 in a tagged
build; writing the OSC 7 escape to the surface's tty fixes the same click.

The socket is the only cwd channel for a process that is not the shell. Claude Code
moves its own cwd (worktrees, `/cd`) without the shell moving, so the shell's OSC 7
goes stale. Session-start cwd reporting already ships: the Claude SessionStart hook
calls `reportClaudeHookPaneDirectory` (`CLI/cmux.swift`), which sends a scoped legacy
`report_pwd <dir> --tab=… --panel=…` (`CLI/CMUXCLI+ClaudeHookPaneDirectory.swift`),
and the wrapper installs that hook (`Resources/bin/cmux-claude-wrapper`). That report
reaches the sidebar today but not the `OPEN_URL` cmd-click directory, so the feature
is half-wired. The remaining follow-on work — a `CwdChanged` hook that reports on
every cwd move, and any CLI cwd-reporting policy change — is blocked on this: a report
only helps cmd-click if it reaches the directory cmd-click reads.

## Why the two stores disagree

Each terminal surface has two current-directory stores and **two** cmd-click readers.

1. **OSC 7 snapshot.** `GhosttyCurrentDirectoryActionDispatcher.latestDirectory`
   (`Sources/GhosttyCurrentDirectoryActionDispatcher.swift`), written in `enqueue`
   from Ghostty's `GHOSTTY_ACTION_PWD` callback and read by `directorySnapshot()`.
   The dispatcher then yields the action to an async main-actor consumer (`deliver`),
   which also writes store 2 for the surface.
2. **Workspace record.** `Workspace.panelDirectories[panelId]`, written through
   `TabManager.updateReportedSurfaceDirectory`
   (`Sources/TabManager+SidebarGitHosting.swift`) and ultimately
   `Workspace.updatePanelDirectory`, which **rejects a blank report** (returns without
   writing). It is provenance gated (cloud surfaces are skipped, remote surfaces route
   elsewhere), coalesced, and also written by session restore, git probes and surface
   transfers. Both socket entrypoints end here and only here today.

A shell `cd` reaches both stores by two independent channels: Ghostty's own shell
integration emits OSC 7 (→ store 1), and the cmux zsh integration sends a detached,
fire-and-forget socket `report_pwd` through `_cmux_send_bg`
(`Resources/shell-integration/cmux-zsh-integration.zsh`) (→ store 2). For a single `cd`
both carry the same path; across rapid `cd`s the detached sender can reorder relative to
OSC 7. A non-shell reporter (Claude hooks) uses only the socket channel.

cmd-click resolves its working directory through **two** code paths:

- **`OPEN_URL` reader.** `GHOSTTY_ACTION_OPEN_URL` in `Sources/GhosttyTerminalView.swift`
  builds its `TerminalLinkOpenRequest` with `workingDirectory` taken from
  `directorySnapshot()` (store 1). `TerminalLinkOpenCoordinator.resolvedWorkingDirectory`
  uses that snapshot whenever it is non-empty and **falls back to the container
  directory (store 2) when it is empty or nil** (`terminalLinkWorkingDirectory` →
  `CommandClickFileOpenRouter.resolveWorkingDirectory`). Socket reports never write the
  snapshot, so they never reach this reader via store 1 — this is the reproduced bug.
- **Word-under-cursor fallback reader.** When Ghostty does not consume the release as a
  URL, `handleCommandClickRelease` → `resolveWordUnderCursorPath` →
  `resolvedWordPathWorkingDirectory` → `CommandClickFileOpenRouter.resolveWorkingDirectory`
  reads `workspace.panelDirectories[surfaceId]` (store 2), then the panel's
  requested directory, then the workspace directory
  (`Sources/CommandClickFileOpenRouter.swift`). Socket reports **do** write store 2, so
  this reader already follows them — subject to store 2's existing, unordered write
  timing (see Accepted side effects).

So OSC 7 writes both stores and reaches both readers; a socket report today writes only
store 2 and reaches only the word-fallback reader. The fix makes socket reports also
publish the snapshot so the `OPEN_URL` reader follows them too. This closes the
reproduced bug for the `OPEN_URL` reader; the word-fallback reader already follows socket
reports through store 2 with its pre-existing semantics (the two readers are not made to
converge — see Accepted side effects).

## Goals

- A socket `report_pwd` for a local terminal surface changes the directory that the
  next **`OPEN_URL`** cmd-click in that surface resolves against, through both the
  legacy and the v2 entrypoints, with one shared mutation path.
- The snapshot publish happens inside the socket command's existing main-actor hop,
  before the command acknowledges. Snapshot writes (from OSC 7 `enqueue` and from the new
  socket helper) are serialized by a lock; the last writer to execute wins. The snapshot
  is **not** arrival-ordered — see Constraints and Accepted side effects for the stale-
  report effect this admits, which is accepted rather than engineered against.
- The existing cross-thread read of the snapshot becomes safe.

## Non-goals

- Right-sidebar Dock terminals. Neither socket handler can target them today (both
  resolve against `tab.panels.keys`).
- Changing remote or cloud directory semantics beyond not regressing them.
- Changing what the sidebar, title, or git probe do with a socket report.
- Making the workspace record (store 2) arrival-ordered, or making the two cmd-click
  readers converge. Store 2 keeps its existing unordered write behavior.
- Clearing a directory store from a socket report. A blank/whitespace report is a no-op,
  matching `updatePanelDirectory`'s existing blank rejection (see Design).
- Adding the `CwdChanged` hook or changing the CLI's cwd-reporting policy. That is the
  follow-on work (session-start reporting already ships; see Intent).
- Modifying the Ghostty submodule.

## Anti-goals

- A new main-thread hop on the typing or rendering path.
- Inferring whether the sidebar accepted a path and gating cmd-click on it. The OSC 7
  snapshot already bypasses the restored-directory guard; cmd-click keeps that
  behavior for socket reports too.
- A *clearing* socket report. Routing a blank path to the snapshot would diverge from
  store 2 (which rejects blank) and could leave the two cmd-click readers inconsistent;
  the helper no-ops instead.

Note on ordering (previously an anti-goal, now an accepted effect). This design does
**not** promise that a socket report never overrides a newer shell `cd`. Because socket
`report_pwd` can be delayed in delivery (the Claude hook spool/queue, the shell's detached
`_cmux_send_bg` child) or logically stale (SessionEnd restoring the launch directory after
the shell has already moved), and because routing it to the snapshot puts it on equal
footing with OSC 7 ordered by execution, a stale socket report can transiently set the
`OPEN_URL` snapshot to a directory older than a newer OSC 7. An admission/arrival stamp
would not prevent this (a stale report is genuinely emitted later), so no stamp is used.
The effect is bounded by Ghostty re-emitting OSC 7 at the next prompt or `cd`, which
restores the snapshot. This is the accepted symmetric cost of letting socket reports reach
the `OPEN_URL` directory at all (see Accepted side effects).

## Constraints

- `Sources/` stays Swift 6.0 compatible.
- The `GHOSTTY_ACTION_PWD` write and the `GHOSTTY_ACTION_OPEN_URL` read happen on
  Ghostty's action-callback thread. The socket handlers run on the main actor. The
  cmd-click release path (`dispatchCommandClickRelease` → `sendGhosttyMouseButton` →
  `ghostty_surface_mouse_button`) runs the Ghostty callback synchronously on the main
  thread, so the snapshot is already read from main while OSC 7 writes it from the I/O
  thread. The field needs a lock regardless of this change.
- The socket main-actor hop is a `DispatchQueue.main.sync` when the handler runs off the
  main thread (`TerminalController.v2MainSync`, reached through `controlSidebarOnMain`
  for the legacy path and through `socketWorkerV2Response`'s `v2MainSync` wrap for v2).
  That wait is unbounded — `v2MainSync` measures the queue wait, it does not cap it — so a
  socket report can sit on main while a newer OSC 7 updates the snapshot from the I/O
  thread. The lock serializes the two writes but does not order them by arrival. The
  guarantee is therefore last-writer-by-execution, not wall-clock arrival.
- The legacy explicit-scope path (`--tab=`/`--panel=`) acknowledges `OK` after
  enqueueing a replaceable mutation on `TerminalMutationBus`; the record write happens
  later at drain. The snapshot publish must run inside the command's hop (before `OK`),
  not at drain time.
- `surface.report_pwd` is a relay-exposed v2 method; see "Relay and remote exposure".
- One behavior with several entrypoints gets one mutation path
  (`skills/cmux-shared-behavior`).
- A behavioral test in `cmuxTests/` must fail on the base before the fix.

## Approaches considered

Two repo-grounded reviewers (GPT-6 Astra via claudex, GPT-5.6 Sol via cursor-agent)
reviewed this design across multiple rounds. Round 1 rejected the brief's "publish before
acknowledge ⇒ wall-clock ordering" claim because the socket hop is a `main.sync` wait. A
first revision added an admission-captured arrival stamp. Round 2 showed that stamp could
not be captured at admission for v2/legacy-fallback without threading it through several
protocol seams, and that it protects only a window the motivating workflow was thought not
to produce. Round 3 showed the ordering problem is broader than that window — delayed and
logically-stale socket reports (SessionEnd, detached shell sends) can override a newer
OSC 7 on the snapshot, and an arrival stamp would not fix late-emitted stale reports. So
the stamp stays removed and the stale-report effect is accepted and documented instead.
The brief and all transcripts are in
`2026-10-26-socket-report-pwd-cmd-click-cwd-reviews/`.

**A, revised (chosen).** Keep both stores and the current cmd-click precedence. Add a
lock-guarded external-record method to the dispatcher. Each socket entrypoint calls one
shared app-side helper that publishes the normalized path to the surface's snapshot
inside the command's existing main-actor hop, before `OK` is returned. The lock serializes
snapshot writes; the last writer to execute wins. A blank report is a no-op. The workspace
record keeps its existing (queued, for the scoped legacy path) write. Trades: a lock on a
field that was lock-free by design (already needed); one new main-actor requirement on the
sidebar control seam plus two test stubs; last-writer-by-execution ordering, which admits
a transient stale-report effect (accepted).

**B, reverse the reader's precedence.** Prefer the workspace record for cmd-click and
fall back to the snapshot. Rejected: the record is asynchronous, coalesced, provenance
gated, and written by restore, probes and transfers; preferring it changes cmd-click for
every surface, not just socket-reported ones, and a `cd` immediately followed by a click
could observe the previous directory. Two July 2026 commits ("make terminal cwd
independent of container", "keep dock cwd cache authoritative") deliberately moved
toward surface-owned cwd.

**C, sequence-stamped snapshot.** Stamp the snapshot with an arrival time and apply writes
only when newer. Considered and prototyped in the first revision; removed. To capture *at
admission* it must be threaded through the v2 worker→main hop (`socketWorkerV2Response` →
`v2MainActorResponse` → `surfaceReportPWD` → `controlSurfaceReportPWD`) and the
legacy-fallback seam (`controlSidebarUpdateDirectory`), because the v2 witness and the
fallback run *after* the `main.sync` wait. Beyond that cost, a stamp does not solve the
actual ordering problem: the damaging reports (SessionEnd launch-dir restore, reordered
detached shell sends) are *stale but later-emitted*, so arrival order would still let them
win. The broader form (stamping store 2 and changing reader precedence) is additionally
rejected as approach B.

## Design

### Dispatcher (`Sources/GhosttyCurrentDirectoryActionDispatcher.swift`)

- Guard `latestDirectory` with an `NSLock`. `enqueue` takes the lock only to assign;
  `directorySnapshot()` takes it only to read. Do not hold it across hashing, the
  AsyncStream yield, or any main-actor work.
- Add `recordExternallyReportedDirectory(_ directory: String)`. It receives the
  **already-normalized** directory from the helper; when it is non-empty it takes the lock
  and assigns; when it is empty it is a **no-op** (it does not clear the snapshot). It
  never yields an action, so `deliver` does not re-run `updateReportedSurfaceDirectory` for
  a socket report. Normalization lives in the helper (not the dispatcher), so this file
  does not gain a `CmuxSidebarGit` dependency.
- Rewrite the type's doc comment and the `SAFETY` comment on
  `GhosttyNSView.currentDirectoryActionDispatcher` (`Sources/GhosttyTerminalView.swift`):
  the dispatcher *object* is still replaced only before runtime attachment, but its
  snapshot is now mutated cross-thread under its own lock.

### One app-side helper (`Sources/TerminalController+ControlSidebarContextSupport.swift`)

A `@MainActor` helper, named by the builder, taking the resolved `Workspace`,
`surfaceId` and raw `directory`. Its file (`TerminalController+ControlSidebarContextSupport.swift`)
gains `import CmuxSidebarGit` for the normalizer below (it currently imports
`CmuxControlSocket`, `CmuxSidebar`, `CmuxTerminal`, `CmuxWorkspaces`, `Foundation`).

1. Admission follows local provenance using the same `Workspace` predicates the
   sidebar write uses: return without publishing when
   `cloudDirectoryProvenanceRequired(panelId:)` is true or
   `allowsLocalDirectoryFallback(panelId:)` is false
   (`Sources/Workspace+SidebarDirectories.swift`). Remote and cloud surfaces are left
   exactly as today.
2. Normalize like the sidebar does: `String.nonEmptyNormalizedGitProbeDirectory`
   (`Packages/macOS/CmuxSidebarGit/.../Model/String+DirectoryNormalization.swift`), which
   trims, turns `file://` URLs into paths, and returns `nil` when the normalized value is
   effectively empty. **A `nil` result is a no-op** — the helper returns without touching
   the snapshot, matching `updatePanelDirectory`'s blank rejection so the two stores stay
   consistent. This protects a *reachable* input: a legacy `report_pwd "   " --tab=<id>
   --panel=<id>` acknowledges `OK` (the legacy positional check only requires a non-empty
   token, and the tokenizer preserves quoted whitespace) and `Workspace.updatePanelDirectory`
   rejects the blank later, so the helper must no-op to match. (The v2 entrypoint already
   filters whitespace-only candidates before the witness.)
3. Resolve `tab.terminalPanel(for: surfaceId)?.hostedView.surfaceView` and call
   `currentDirectoryActionDispatcher.recordExternallyReportedDirectory(_:)` on **that
   panel's own dispatcher** (the one `GHOSTTY_ACTION_OPEN_URL` reads). A missing panel is
   a no-op (the surface is not a workspace terminal).

The display label from `report_pwd <label> --path=<path>` is never published; only the
filesystem path is. The label is a human-readable sidebar caption, not a resolvable
path, so publishing it would make cmd-click resolve against a non-path string.

### Call sites

Each entrypoint publishes the snapshot inside its existing main-actor hop, before the
command acknowledges. No arrival stamp is captured or threaded (see Approaches, "C").

- **Legacy `report_pwd`, explicit scope** (`sidebarReportPwd` in
  `Packages/macOS/CmuxControlSocket/.../ControlCommandCoordinator+SidebarReportsV1.swift`).
  Inside the existing `controlSidebarOnMain` closure, before
  `controlSidebarScheduleScopedDirectoryUpdate` and before returning `OK`, call a new
  `@MainActor` requirement on `ControlSidebarContext` (name the builder's; it takes the
  `ControlSidebarPanelScope` and `directory`). Its witness resolves the workspace and
  panel, prunes nothing, and calls the helper. The scheduled record write is unchanged.
- **Legacy `report_pwd`, fallback** (`controlSidebarUpdateDirectory` →
  `controlSidebarApplyDirectoryReport`). Already synchronous on main; call the helper
  from `controlSidebarApplyDirectoryReport` after the record write. No signature change.
- **v2 `surface.report_pwd`** (`controlSurfaceReportPWD` in
  `Sources/TerminalController+ControlSurfaceContext4.swift`). Runs on main inside the
  command's `v2MainSync` wrap; call the helper on the `.recorded(surfaceID:)` path. Note
  that `.recorded` does **not** mean "local": a live remote terminal surface also resolves
  and returns `.recorded` (only a remote workspace with no panels returns `.pending`). The
  exclusion of remote/cloud surfaces is therefore enforced by the helper's provenance
  predicates (`cloudDirectoryProvenanceRequired` / `allowsLocalDirectoryFallback`,
  `Sources/Workspace+SidebarDirectories.swift`), not by the result enum. The `.pending`
  path remains unchanged.
- The scoped legacy drain path (`controlSidebarApplyDirectoryReport` called from the
  bus mutation) must **not** publish again; the in-hop publish already happened, and a
  second publish at drain could overwrite a newer OSC 7. The builder decides whether to
  add a flag or split the helper so the fallback path publishes and the drain path does
  not.

### Relay and remote exposure

`surface.report_pwd` is exposed to the remote relay (`RemoteRelayRoutingSchema` lists its
reviewed params as `surface_id`, `path`, `directory`; `RemoteRelayAuthorizationPolicy`
requires workspace+surface scope), so this change is analyzed under
`skills/cmux-socket-policy/references/remote-relay-authorization.md`:

- **No new parameters or scope.** The method's relay param contract is unchanged; no
  command-bearing param is added. Scope stays workspace+surface.
- **No new local command/content execution.** The helper only normalizes a string and
  stores it in the surface's dispatcher; it runs no shell, spawns no process, opens no
  file. cmd-click execution is unchanged; only the directory it resolves against moves.
- **No access to unowned objects.** The helper resolves only the targeted surface's panel
  and dispatcher, under the same `Workspace` provenance predicates the sidebar write uses.
- **No new local-state exposure.** The directory was already stored in store 2 for the
  same report; store 1 now mirrors it for local surfaces. No value is read back to the
  caller.
- **Relay-origin reports to remote/cloud surfaces do not publish a local snapshot.** The
  exclusion is the helper's provenance gate, not the result enum: a live remote terminal
  returns `.recorded` just like a local one, so the helper must (and does) short-circuit on
  `cloudDirectoryProvenanceRequired` / `allowsLocalDirectoryFallback` before resolving any
  dispatcher. Relay authorization already scopes `surface.report_pwd` to a live remote
  terminal id (`Sources/TerminalController+RemoteRelayAuthorization.swift`); the test
  (see Tests) drives an authorized report to such a surface and asserts its dispatcher
  snapshot is unchanged.

### Accepted side effects

- Desktop-notification project-hook lookup (`hookDirectory` in
  `Sources/GhosttyTerminalView.swift`, the other `directorySnapshot()` reader) now
  also follows socket reports. Both reviewers recommended accepting this; it makes hook
  resolution agree with cmd-click.
- **A stale socket report can transiently override a newer OSC 7 on the `OPEN_URL`
  snapshot.** Today the snapshot is OSC-7-only, so `OPEN_URL` always reflects the shell's
  latest `cd`. After this change, a delayed socket report (the Claude SessionEnd
  launch-directory restore after the shell has moved; the shell's own detached
  `_cmux_send_bg report_pwd` reordered across rapid `cd`s) can set the snapshot to an
  older directory than a newer OSC 7, making the next `OPEN_URL` cmd-click resolve against
  the stale directory until Ghostty re-emits OSC 7 at the next prompt or `cd`. This is the
  accepted, self-correcting cost of routing socket reports to `OPEN_URL`; it is the same
  staleness store 2 (and therefore the sidebar and the word-fallback reader) already has.
  An arrival/admission stamp would not prevent it, because the stale report is emitted
  later than the directory it clobbers.
- The two cmd-click readers are not made to converge. The `OPEN_URL` reader reads the
  lock-ordered snapshot (store 1); the word-fallback reader reads the workspace record
  (store 2). Store 2 is written by two unordered, asynchronous paths — the OSC 7
  `deliver` consumer and the scoped legacy drain (`updateReportedSurfaceDirectory`). A
  valid interleaving — queue scoped `report_pwd /b`, receive newer OSC `/c` (snapshot
  `/c`, record `/c` at deliver), then drain `/b` (record `/b`) — leaves the snapshot at
  `/c` and the record at `/b` indefinitely, so the two readers disagree. This is
  pre-existing store-2 behavior; the fix neither introduces nor widens it.
- A surface later moved into the Dock keeps its dispatcher snapshot (placement changes
  clear `TerminalSurface.reportedWorkingDirectory`, not the dispatcher). Pre-existing
  behavior; unchanged.

### Lock cost and rollback

- The lock guards only a pointer-sized directory reference; each critical section is a
  single assign (write) or read, with no hashing, yielding, or main-actor work inside it.
  It is uncontended on the common path and replaces an existing data race, not a correct
  lock-free design.
- The change is additive and reverts cleanly: removing the three helper calls and the new
  protocol requirement restores the prior behavior; the dispatcher's lock can stay (it
  fixes the pre-existing race independently).

## Tests (red first, `cmuxTests/`)

New file(s) need `scripts/sync-test-wiring`. Fixtures to copy:
`AppDelegateIssue2907RoutingTests.swift` (builds AppDelegate, window and TabManager,
drives `TerminalController.shared.handleSocketLine`, drains `TerminalMutationBus`;
has v2 envelope helpers), `TerminalLinkOpenCoordinatorTests.swift`
(`LocalLinkContainer`, `RecordingFileOpener`, `makeDefaults`), and
`DockWorkingDirectoryInheritanceTests.swift` (shows how to build a real panel and call
`enqueue` — but note it enqueues on a *detached* dispatcher; the tests below must instead
seed the panel's own `hostedView.surfaceView.currentDirectoryActionDispatcher`, the
instance `GHOSTTY_ACTION_OPEN_URL` reads).

1. **Regression, three entrypoints.** Seed a stale OSC 7 snapshot on the **panel's own**
   dispatcher with `enqueue`. Send `report_pwd` with explicit scope, `report_pwd`
   fallback (focused panel), and v2 `surface.report_pwd`, each for a fresh directory
   that contains a file the stale directory does not. Build a `TerminalLinkOpenRequest`
   from that dispatcher's `directorySnapshot()` exactly as `OPEN_URL` does, run
   `TerminalLinkOpenCoordinator` with a `RecordingFileOpener` and a local container,
   and assert the file is opened under the **new** directory. Because the default
   fixture settings enable supported-file routing (`openSupportedFilesInCmux = true`),
   an ordinary file is handed to the container's deferred path, not `RecordingFileOpener`;
   the test must either disable supported-file routing
   (`defaults.set(false, forKey: AppCatalogSection().openSupportedFilesInCmux.userDefaultsKey)`,
   as `localFileExternalOpenRoutesThroughFileOpeningSeam` does) so the file routes through
   `RecordingFileOpener`, or assert `container.deferredFilePaths` holds the file under the
   new directory. Fails on the base because the request keeps the stale OSC directory.
   Drain the bus only for the scoped legacy case, and assert the open result before the
   drain to prove the publish happened inside the hop.
2. **Ordering, last-writer-by-execution.** Suspend bus drains
   (`TerminalMutationBus.setDrainsSuspendedForTesting`), send scoped legacy
   `report_pwd /b` (snapshot publishes in-hop), then `enqueue` a newer OSC directory
   `/c` on the panel's dispatcher, drain, and assert the `OPEN_URL` cmd-click resolves
   against `/c` (the later execution). Assert the reverse at the dispatcher: after
   `enqueue /c`, a later `recordExternallyReportedDirectory("/b")` makes the snapshot
   `/b`. This verifies the lock-serialized last-writer-wins behavior for non-overlapping
   events; the unbounded `main.sync`-wait interleaving and the stale-report effect are
   explicitly out of scope (Accepted side effects) and are not tested.
3. **Label never leaks.** `report_pwd <label> --path=/x` resolves against `/x`, never the
   label.
4. **Provenance and relay.** A cloud-provenance or remote-trust-required surface leaves
   the local snapshot untouched. Separately, an authorized relay report to a **live remote
   terminal** surface (which returns `.recorded`, not `.pending`) leaves that surface's
   dispatcher snapshot unchanged, proving the provenance gate — not the result enum — is
   the exclusion.
5. **Blank no-op, two layers.** At the dispatcher: `recordExternallyReportedDirectory("")`
   is a no-op that leaves the snapshot unchanged (not a clear), and a non-empty value sets
   it without delivering an action (extend `GhosttyCurrentDirectoryActionDispatcherTests.swift`).
   End-to-end: a legacy `report_pwd "   " --tab=<id> --panel=<id>` acknowledges `OK` but
   leaves the snapshot unchanged (the reachable whitespace input). Normalization, including
   `file://` → path, is tested at the helper level (where the normalizer is called), not in
   the dispatcher.

## Verification

- `python3 scripts/verify-local.py` scoped per `skills/cmux-testing`.
- Dogfood in a tagged build (`CMUX_TAG=<tag> scripts/cmux-debug-cli.sh`): after a shell
  `cd /a`, send `report_pwd /b` to the pane, cmd-click a relative file that exists only
  under `/b`, then `cd /c` in the shell and confirm the next click resolves under `/c`.
  Exercise both cmd-click routes where possible (an OSC 8 hyperlink target for the
  `OPEN_URL` reader and a bare relative path for the word-fallback reader; the latter
  reads store 2 and is expected to follow the report once the record write lands).
- PR body records the focused test command's red on the base and green on the head,
  per the repo's bug-fix policy, and includes the relay-exposure analysis above.

## Left to the builder

- Names of the dispatcher method, the helper and the protocol requirement.
- Whether the helper is split or flagged so the scoped drain path does not re-publish.
- Lock type (`NSLock` matches the neighbouring `_scrollbarLock`; `OSAllocatedUnfairLock`
  is acceptable if the deployment target allows).
- Whether the regression test disables supported-file routing or asserts the container's
  deferred path.
- Whether the tests live in one new file or extend the fixtures named above.
