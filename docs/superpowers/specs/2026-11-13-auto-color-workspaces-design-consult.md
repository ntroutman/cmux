# Design Deliberation: Workspaces color themselves by worktree

**Source:** docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md
**Date:** 2026-11-13
**Rounds:** 4
**Mode:** converge
**Personas:** devils-advocate, pragmatist, simplifier, user, astra, sol
**Final verdict:** Ready (pending three doc corrections and four owner decisions)

## Round 1: Initial Critiques
### Devil's Advocate (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.75

The design is comprehensive but requires further consideration of potential issues and alternative approaches.

- The design assumes that the worktree directory is a suitable and reliable key for color assignment, but what if the worktree directory changes or is not unique enough?
- The design does not guarantee distinct colors for all workspaces, which could lead to confusion if multiple workspaces share the same color.
- The design could benefit from further exploration of alternative key strategies, such as using the workspace's stable ID or git branch.
- The design should consider the potential impact on performance, especially if the number of workspaces increases significantly.
- The design should ensure that the automatic color assignment does not interfere with existing manual color assignments or user preferences.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 0.95

This is a practical and low-risk design that leverages existing mechanisms effectively to deliver immediate value with minimal implementation cost.

- The decision to reuse the existing 'origin-color' implementation path and the cached `projectRootPath` property is highly pragmatic, significantly reducing risk and development effort.
- Choosing a stateless hash-based color assigner and explicitly accepting potential color collisions is the correct trade-off, avoiding the massive complexity of a stateful, persistent allocator.
- The proposed architecture with `KeyProviding` and `Assigning` protocols is simple, testable, and sufficiently extensible for the stated future goals without over-engineering the initial version.
- The dependency on the existing `projectRootPath` resolution is a key point of leverage, but its behavior (e.g., color changing with pane focus) must be explicitly verified during dogfooding to ensure it's not a jarring user experience.
- The plan is exceptionally thorough, covering not just the core logic but also settings integration, documentation, schema updates, and a detailed, multi-level testing strategy, which inspires high confidence in a smooth execution.
- The small refactoring to create a shared color palette is a necessary and well-contained task; the requirement to re-validate existing tests against it correctly mitigates the risk.

### Simplifier (simplifier)
**Verdict:** approve | **Confidence:** 0.9

The design for automatic workspace coloring is well-structured, modular, and aligns with the principles of simplicity and clarity.

- The design is modular, allowing for easy extension and modification of the key strategy and color assigner.
- The automatic coloring is a fallback, ensuring that manual colors always take precedence.
- The design avoids unnecessary complexity by not persisting automatic colors and by reusing existing components where possible.
- The use of a shared palette ensures consistency and reduces the risk of color collisions.
- The design is off by default, aligning with the repository's rule for opinionated user-visible behavior.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.75

This feature is overly specific to a niche workflow, offers limited value for most users without further strategy options, and introduces potential for visual clutter and color collision.

- The core problem this solves (45 workspaces, 9 groups, unable to distinguish at a glance) is highly specific to a power user and not relevant for the majority of users, making its general appeal low.
- The initial offering is limited to 'By Worktree' only, which means if my workflow isn't centered around Git worktrees, this feature provides no value, despite the architecture allowing for more flexible strategies later.
- The explicit 'non-goal' of 'Guaranteed distinctness' is a critical flaw, as the primary intent of coloring is to differentiate items at a glance, and color collisions undermine this completely for power users with many worktrees.
- Requiring a settings change (off by default) for a feature with such narrow initial utility and potential visual clutter (a 'loud sidebar' is an anti-goal, but automatic colors can easily become one) means many users won't bother enabling it.
- The potential for color to change based on the 'focused pane's directory' within a single workspace could be visually jarring or confusing, even if branch/directory lines already follow this behavior, as color adds a stronger visual cue.

### Astra (astra)
**Verdict:** reject | **Confidence:** 0.96

The paint-time fallback fits the existing snapshot architecture, but the document misstates multi-pane display behavior, omits an incremental refresh entrypoint and locality policy, and overpromises distinct colors.

- Missing refresh entrypoint: docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md:234-249 names only refreshWorkspaceSnapshots(), but workspace changes—including cwd and project-root updates—reach refreshWorkspaceSnapshots(workspaceIds:) through the observation callback and coalescer (Sources/ContentView.swift:12211-12218, 13274-13311). That path directly replaces snapshots through SidebarRowSnapshotCache.refresh; it does not check the presentation key (Sources/Sidebar/SidebarRowSnapshotCache.swift:55-66). Explicitly thread automatic-color resolution through both refresh overloads and their shared makeWorkspaceSnapshot helper (Sources/ContentView.swift:13351-13367). Updating only the documented full-refresh path can initially color rows and then lose their automatic color on an ordinary workspace update. Require an observation-to-cache test for cwd/root changes, not just presentation-key inequality.
- Unspecified locality policy: the proposed isLocal input is declared but its Workspace-to-input mapping is not defined (docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md:172-177, 234-237). isRemoteWorkspace checks only remoteConfiguration (Sources/Workspace.swift:7124-7129), while usesRemoteDirectoryProvenance also covers tmux mirrors, Cloud bindings and panel projections; canHostLocalTerminal deliberately treats mixed local/Cloud workspaces differently (Sources/Workspace+SidebarDirectories.swift:45-66). A nil project root cannot establish locality because the design also gives non-repository local workspaces a cwd fallback. Specify which predicate governs eligibility, explicitly settle mixed local/Cloud behavior, and test the real adapter with projected Cloud panels and unresolved tmux mirrors. Tests that merely supply isLocal=false cannot verify these exclusions.
- Incorrect multi-pane display premise: docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md:96-97 and 215-217 say the sidebar's branch and directory lines follow focus and therefore describe the proposed color key. The sidebar actually orders panels spatially (Sources/Workspace.swift:7046-7062), collects directories and branches across those panels (Sources/Workspace+SidebarDirectories.swift:243-280, 287-315), and renders combined summaries or multiple lines (Sources/SidebarWorkspaceSnapshotFactory.swift:387-420, 424-457). With two panes in different repositories, focusing the other pane can change the proposed color without changing the displayed directory/branch set. Correct the premise and explicitly retain or reconsider focus-following color as a separate product decision; test that multi-pane case.
- Conflicting distinctness contract: docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md:18 promises different colors for sibling worktrees, while lines 43-45 and 115-116 frame collisions around exceeding sixteen worktrees. The no-probing hash-modulo algorithm at lines 227-230 can collide with just two keys. Using the exact FNV-1a implementation in Sources/RemoteHostColorRegistry.swift:107-115 and its sixteen-entry palette at lines 48-65, /repo/.worktrees/feature-9 and /repo/.worktrees/feature-10 both select slot 4. Unlike that proposal, the existing host registry probes to avoid collisions until exhaustion (Sources/RemoteHostColorRegistry.swift:84-98). State that any two sibling worktrees may share a color even below palette capacity, or change the assignment contract if sibling distinctness is required.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.96

The design identifies the main rendering seam but contains factual errors and leaves critical refresh and provenance behavior underspecified.

- The claim that `currentDirectory` always follows the focused pane is false: focus only assigns it when `panelDirectories[panelId]` has a value, otherwise the previous directory remains (`Sources/Workspace.swift:14361-14369`). The displayed branch and directory data can also aggregate multiple panels rather than simply follow `currentDirectory` (`Sources/SidebarWorkspaceSnapshotFactory.swift:389-430`). The key-strategy behavior and tests must account for panes without reported directories.
- The design names only the full snapshot refresh, but workspace/root changes use the keyed partial path: workspace observation schedules `refreshWorkspaceSnapshots(workspaceIds:)` (`Sources/ContentView.swift:12210-12217`, `Sources/ContentView.swift:13274-13310`), while initial/settings refreshes use the separate full overload (`Sources/ContentView.swift:13314-13347`). Both paths must receive the same resolver and effective-color calculation, with an integration test proving a directory/root publication updates the cached row.
- The construction of `isLocal` is unspecified despite materially different predicates. `isManagedCloudVMWorkspace` only checks `cloudVMID` (`Sources/Workspace.swift:8041-8043`), whereas the repository's directory-provenance predicate also excludes remote tmux, cloud bindings, and cloud-projected panels (`Sources/Workspace+SidebarDirectories.swift:45-65`). The design must state which predicate is authoritative and decide how mixed local/cloud workspaces behave.
- The statement that the CLI already gates on `hasManualCustomColor` is factually wrong. That flag exists only in sidebar snapshot/menu plumbing (`Sources/TabItemView+WorkspaceContextMenu.swift:157-190`); the socket action unconditionally sets or clears `workspace.customColor` (`Sources/TerminalController.swift:5691-5719`). This does not necessarily require a CLI change, but the claimed construction guarantee must be corrected.
- The origin-color implementation is not a stateless hash-to-palette assigner: it maintains process-wide assignments, linear-probes collisions, and caches slots (`Sources/RemoteHostColorRegistry.swift:15-35`, `Sources/RemoteHostColorRegistry.swift:71-104`). Its tests explicitly require probing and distinct slots until exhaustion (`cmuxTests/RemoteHostColorRegistryTests.swift:30-84`). The design must distinguish sharing the FNV function and palette from preserving the registry's stateful behavior and update or preserve consumers of its moved static members.
- The promised immediate stability across reopen/restart is not supported by the existing root signal. `extensionSidebarProjectRootPath` starts optional and is populated by a detached task (`Sources/Workspace.swift:2937-2938`, `Sources/Workspace.swift:3587-3608`, `Sources/Workspace.swift:4624-4625`); the proposed provider therefore hashes the current subdirectory before the root resolves, so two rows in the same worktree can temporarily receive different colors. The design acknowledges only one asynchronous transition and needs to define this initial/pending state.
- The document contradicts itself by asserting sibling worktrees get different colors while explicitly disclaiming guaranteed distinctness (`docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md:15-19`, `docs/superpowers/specs/2026-11-13-auto-color-workspaces-design.md:42-44`). The repository palette has only sixteen entries (`Sources/RemoteHostColorRegistry.swift:38-65`), so collisions are unavoidable; the requirement must say colors are stable but not necessarily distinct.

## Design Lead Revision (after Round 1)
### Rationale
1. **astra, sol (two refresh paths).** Valid, and verified: `scheduleWorkspaceSnapshotRefresh` feeds the keyed `refreshWorkspaceSnapshots(workspaceIds:)`, which calls `SidebarRowSnapshotCache.refresh` and never consults the presentation key. Revised: the automatic color enters through one `ContentView` helper that both the shared `makeWorkspaceSnapshot` and the full refresh's presentation-key closure call. Added an end-to-end test (a root publication flows through observation, coalescer and keyed refresh to the cached row) and a test that an unrelated keyed update keeps the color.
2. **astra, sol (isLocal undefined).** Valid. Revised: one adapter maps `isLocal = !usesRemoteDirectoryProvenance`, the predicate the root walk already guards on. Mixed local/Cloud workspaces (any Cloud-projected pane) get no automatic color. The adapter is tested on real `Workspace` instances: an ssh remote, an unresolved tmux mirror, a Cloud-bound workspace, a mixed workspace and a plain local one.
3. **astra, sol (focus and display premise wrong).** Valid, and verified: `currentDirectory` changes only when the focused panel has a reported directory, and the branch/directory lines list every panel in spatial order. Revised the Constraints and Key strategy sections to say so. Focus-following color is kept as an explicit product decision, since Nathaniel runs one worktree per workspace, and listed under "Decisions for Nathaniel". Added a two-pane focus test.
4. **astra, sol, user, devils-advocate (distinctness contradiction).** Valid. Verified that `/repo/.worktrees/feature-9` and `feature-10` both hash to slot 4. Removed the "sibling worktrees get different colors" promise and stated plainly that collisions happen at any count, with roughly even odds at five worktrees. Kept the stateless hash: Nathaniel chose stability over distinctness, and his 45 rows exceed sixteen colors either way. Added live-set probing as a considered alternative that would trade stability for distinctness and fits behind the assigner seam. To **user**: this is a genuine trade-off. The color narrows the search and the title and group finish it.
5. **sol (CLI does not gate on hasManualCustomColor).** Valid, and verified in `TerminalController.swift` `set_color`/`clear_color`. Corrected: only the menu and prompt gate on it. The CLI writes `customColor` directly, so `clear_color` reveals the automatic color, which is the intended behavior.
6. **sol (registry is stateful, not a hash assigner).** Valid. Clarified that only `stableHash` and `hostPalette` move. The registry keeps its probing and slot cache, and only its tests reference the moved statics. Also noted that host and worktree colors can coincide because they share a palette but not a slot table.
7. **sol (initial nil root, so two rows in one worktree flash different colors).** Valid. Instead of documenting the flash, removed the `currentDirectory` fallback. The key is the project root or nothing. Rows are uncolored until the root resolves and then take their final color with no hue change. Cost: workspaces outside a repository get no automatic color. That fits the "By Worktree" name, and it is flagged for Nathaniel. This also simplifies the key provider.
8. **devils-advocate.** These points were generic. Key alternatives are already covered under Approaches. Performance: the resolver is a hash per row on a path that already runs per row, with no I/O. Manual precedence is already a goal and a test. No change beyond item 4.
9. **user (niche, off by default, only By Worktree).** Partly a trade-off. The feature is deliberately scoped to the requester's workflow and ships off by default per the repo rule. The enum seam exists so broader strategies can follow. Kept the scope. Added a dogfood check on how the sidebar reads across 45 rows. The focus-following concern is handled in item 3.
10. **pragmatist, simplifier (approve).** No change requested. Pragmatist's dogfood point on focus-following is now an explicit dogfood item and decision.

### Key Changes
- Removed the "sibling worktrees get different colors" promise; collisions stated at any count (verified feature-9/feature-10 both hash to slot 4).
- Dropped the `currentDirectory` fallback: key is the project root or nothing, so no startup hue change; non-repo workspaces stay uncolored.
- Defined `isLocal = !usesRemoteDirectoryProvenance` through a single adapter; mixed local/Cloud workspaces excluded.
- Routed the automatic color through one helper used by `makeWorkspaceSnapshot` (both refresh paths) and the full refresh's presentation key; added keyed-refresh end-to-end tests.
- Corrected the focus/display premise (currentDirectory changes only for panes with a reported directory; sidebar lines list every pane) and made focus-following an explicit decision.
- Corrected the CLI claim (CLI writes `customColor` directly) and clarified that only `stableHash` and `hostPalette` move; the registry keeps probing.
- Added "Decisions for Nathaniel at approval".

## Round 2: Deliberation
### Devil's Advocate (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.8
**Changed from Round 1:** needs_work -> needs_work (no change)

The design shows improvement but still has room for enhancement.

- The design adequately addresses the concern about the suitability and reliability of the worktree directory as a key for color assignment.
- The design still does not guarantee distinct colors for all workspaces, which could lead to confusion if multiple workspaces share the same color.
- The design could further explore alternative key strategies, such as using the workspace's stable ID or git branch.
- The design should continue to consider the potential impact on performance, especially if the number of workspaces increases significantly.
- The design adequately ensures that the automatic color assignment does not interfere with existing manual color assignments or user preferences.
- The design could benefit from a more detailed discussion on how to handle workspaces outside any git repository.
- The design could benefit from a more detailed discussion on how to handle workspaces with panes in different repositories.
- The design could benefit from a more detailed discussion on how to handle collisions at small counts.
- The design could benefit from a more detailed discussion on how to handle the focus-following color in a workspace with panes in different repositories.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 1.0
**Changed from Round 1:** approve -> approve (no change)

The revised design is exceptionally robust, having systematically addressed every identified implementation risk with pragmatic, low-cost solutions that increase feasibility and reduce the chance of execution surprises.

- The plan to centralize color resolution logic into a single helper correctly mitigates the risk of divergence between the full and keyed UI refresh paths.
- Basing the `isLocal` predicate on the existing `!usesRemoteDirectoryProvenance` logic is an excellent example of pragmatic reuse, minimizing new code and clearly defining the feature's boundaries.
- The decision to eliminate the `currentDirectory` fallback is a significant improvement; it prevents a jarring initial color flash and simplifies the logic, at the acceptable cost of not coloring non-repository workspaces.
- The explicit acceptance and clear documentation of hash collisions and the focus-following color behavior demonstrate a realistic understanding of the implementation's trade-offs, correctly prioritizing stability and simplicity over perfect distinctness.
- The clarification of how stateful and stateless color components will be refactored and shared demonstrates a safe, low-risk approach to code changes.
- The addition of specific integration and behavioral tests for the most complex interactions (keyed refreshes, focus changes, mixed workspaces) provides high confidence that the feature will work as specified in real-world use.

### Simplifier (simplifier)
**Verdict:** approve | **Confidence:** 0.95
**Changed from Round 1:** approve -> approve (no change)

The revised design adequately addresses previous concerns and maintains a focus on simplicity and clarity.

- The modular design allows for easy extension and modification.
- Automatic coloring is a fallback, ensuring manual colors always take precedence.
- The design avoids unnecessary complexity by not persisting automatic colors and reusing existing components.
- The use of a shared palette ensures consistency and reduces the risk of color collisions.
- The design is off by default, aligning with the repository's rule for opinionated user-visible behavior.
- The revision rationale adequately addresses previous concerns and maintains the focus on simplicity and clarity.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.8
**Changed from Round 1:** needs_work -> needs_work (no change)

While the revisions clarify design choices, they reinforce that the feature remains too niche, and fundamental usability compromises like color collisions severely limit its practical value for broad adoption.

- Explicitly allowing color collisions fundamentally undermines the purpose of using color for quick visual differentiation; 'narrows the search' is just extra work disguised as a feature.
- The feature is still rigidly tied to a specific 'By Worktree' workflow, offering zero value to users whose workflows don't align, making it a non-starter for most.
- The confirmed behavior of colors changing based on the focused pane within a single workspace will be visually distracting and confusing, especially when other textual identifiers remain static.
- Keeping this niche and compromised feature off by default ensures that the vast majority of users will never discover or bother enabling it, further limiting its impact.

### Astra (astra)
**Verdict:** approve | **Confidence:** 0.94
**Changed from Round 1:** reject -> approve

The revision adequately addresses my four prior objections and fits the repository’s existing snapshot, observation, locality and manual-color contracts; I found no additional blocking design defects.

- Refresh-path concern resolved: the shared fallback helper now explicitly feeds both makeWorkspaceSnapshot and the full refresh’s presentation key. This matches the actual entrypoints in Sources/ContentView.swift:13274-13367 and the distinction between reconciliation and unconditional snapshot rebuilding in Sources/Sidebar/SidebarRowSnapshotCache.swift:30-66. The added observation-to-cache and unrelated-keyed-update tests target the failure previously omitted.
- Locality concern resolved: the adapter now names !usesRemoteDirectoryProvenance and explicitly excludes mixed Cloud workspaces. Sources/Workspace+SidebarDirectories.swift:45-66 confirms that this predicate covers SSH, tmux mirrors, Cloud bindings and projected panels, unlike canHostLocalTerminal. Testing real Workspace instances rather than only constructed boolean inputs addresses the missing adapter contract.
- Focus/display concern resolved: the document now treats focus-following color as an explicit product choice, not a consequence of matching sidebar text. Directory reports update currentDirectory for the focused panel in Sources/Workspace.swift:6351-6355, and focus reconciliation leaves it unchanged when the target lacks a directory in Sources/Workspace.swift:12609-12613. The sidebar independently collects directories and branches across panels in Sources/Workspace+SidebarDirectories.swift:243-315.
- Distinctness concern resolved: collisions are now explicitly permitted below sixteen worktrees. Separating the stateless automatic assigner from the host registry preserves the latter’s cached linear probing in Sources/RemoteHostColorRegistry.swift:69-104 while reusing its deterministic hash at lines 107-115. Retaining the palette-distance tests in cmuxTests/RemoteHostColorRegistryTests.swift:116-155 protects the existing rendering assumptions.
- The revised root-only key and manual-color separation are supported by the code: the asynchronous root walk accepts a .git file or directory, fences stale results and retains the previous root while resolving in Sources/Workspace.swift:3587-3621; root changes already participate in sidebar observation in Sources/WorkspaceSidebarObservation.swift:326-398. Manual provenance is separate from effective color in Sources/SidebarWorkspaceSnapshotFactory.swift:169-172,226-254, and menu selection and clearing already respect it in Sources/TabItemView+WorkspaceContextMenu.swift:156-188. Approval is based on static repository tracing, not execution of the proposed tests.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.96
**Changed from Round 1:** reject -> reject (no change)

The revision resolves the prior major issues, but still contains a false project-root invariant and an internally inconsistent extensibility claim.

- The prior concerns about refresh paths, provenance, focus semantics, CLI behavior, registry state, startup color changes, and collisions are adequately addressed; the revised behavior now matches Sources/ContentView.swift:13274-13365, Sources/Workspace+SidebarDirectories.swift:45-50, Sources/Workspace.swift:14361-14369, Sources/TerminalController.swift:5691-5719, and Sources/RemoteHostColorRegistry.swift:71-115.
- The claim that extensionSidebarProjectRootPath is always nil for remote-provenance workspaces is false for remote-tmux mirrors. Workspace initialization schedules the root lookup before the mirror flag is assigned, the flag has no didSet invalidation, and lookup completion does not recheck provenance; a local root can therefore remain published after conversion to a mirror. The explicit isLocal guard still prevents automatic coloring, but the document must correct this invariant and preserve that guard (Sources/Workspace.swift:3587-3608, Sources/Workspace.swift:4624-4625, Sources/Workspace.swift:7124-7130, Sources/RemoteTmuxController.swift:509-515).
- The promised future branch strategy cannot be added using only a new enum case, provider, and factory line: WorkspaceAutoColorInput contains no branch value, while branch state is modeled and observed separately. Supporting it would require widening the input and adapter plus deciding which branch represents a multi-pane workspace; the document should either include that value and decision now or narrow its extensibility claim (/private/tmp/consult-deliberation.U9tPoa/round-2-input-sol.md:23-27, /private/tmp/consult-deliberation.U9tPoa/round-2-input-sol.md:205-240, Sources/WorkspaceSidebarObservation.swift:218-230, Sources/WorkspaceSidebarObservation.swift:329-388).
- The statement that remote rows are already distinguished by host suffixes is also inaccurate: origin colors and host-title suffixes have independent settings, and suffixes are absent when their separate flag is off (Sources/ContentView.swift:11557-11562, Sources/ContentView.swift:13370-13410).

## Design Lead Revision (after Round 2)
### Rationale
1. **sol (mirror root invariant false).** Valid, and verified: `RemoteTmuxController` calls `addWorkspaceIfActive`, which schedules a local root walk, and only then sets `isRemoteTmuxMirror = true` (Sources/RemoteTmuxController.swift around line 515). `isRemoteTmuxMirror` is a plain stored property with no observer, so a mirror can keep a local root. Revised the Constraints: a `nil` root no longer reads as "remote", and locality must be checked at paint time. The adapter re-reads `usesRemoteDirectoryProvenance` on every refresh, and the key provider's `isLocal` check is called out as load-bearing. Added a test that converts a workspace to a mirror after its root resolves and asserts no automatic color.
2. **sol (branch extensibility overclaimed).** Valid. Narrowed the Intent and Non-goals. "By workspace" and "by group" are one enum case plus one provider, because the input already carries the stable id and group id. "By branch" also needs a branch field and a multi-pane rule. Painting stays untouched in every case. I did not add a branch field now: no consumer exists, and the multi-pane decision belongs to that future strategy.
3. **sol (host-suffix claim inaccurate).** Valid, and verified: `remoteTmuxOriginColors` and `remoteTmuxOriginHostTitles` are independent live settings. Removed the claim and stated plainly that a remote origin color and a local automatic color can share a hue, which is accepted.
4. **devils-advocate.** It repeats the round-1 points (distinctness, key alternatives, performance) and asks for more discussion of non-repo workspaces, multi-repo panes and small-count collisions. The document already covers each of these explicitly (Non-goals on distinctness with the birthday odds, Key strategy on the dropped fallback and focus-following, and "Decisions for Nathaniel"). No further change; this persona raised no new concrete defect.
5. **user.** Its concerns are product trade-offs already decided by the requester: hash collisions, a worktree-only first strategy, focus-following color and off by default. I keep the approach. The document now states each trade-off plainly and puts focus-following and the non-repo behavior to Nathaniel as explicit approval decisions. The disagreement is recorded as contentious, not resolved.
6. **astra, pragmatist, simplifier (approve).** No change requested.

### Key Changes
- A `nil` root no longer implies remote: mirrors are created local and flagged afterwards, so locality is checked at paint time and the `isLocal` guard is load-bearing; added a convert-to-mirror test.
- Narrowed the extensibility claim: "by workspace"/"by group" need no input change; "by branch" needs a branch field and a multi-pane rule.
- Removed the inaccurate host-suffix claim; a remote origin color and a local automatic color may share a hue.

## Round 3: Deliberation
### Devil's Advocate (devils-advocate)
**Verdict:** approve | **Confidence:** 0.9
**Changed from Round 2:** needs_work -> approve

The revised design adequately addresses the concerns raised and provides a solid foundation for the implementation.

- The design adequately addresses the concern about the suitability and reliability of the worktree directory as a key for color assignment.
- The design still does not guarantee distinct colors for all workspaces, but this is an accepted trade-off and a follow-up approach is described.
- The design explores alternative key strategies, such as using the workspace's stable ID or git branch, and leaves room for future extensions.
- The design considers the potential impact on performance and ensures that the automatic color assignment does not interfere with existing manual color assignments or user preferences.
- The design provides a detailed discussion on how to handle workspaces outside any git repository, workspaces with panes in different repositories, and collisions at small counts.
- The design provides a detailed discussion on how to handle the focus-following color in a workspace with panes in different repositories.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 1.0
**Changed from Round 2:** approve -> approve (no change)

The revised design is even more robust and feasible, having addressed a critical race condition with a pragmatic solution while maintaining a clear and low-risk implementation path.

- The revised logic to check `!usesRemoteDirectoryProvenance` on every refresh is a crucial fix that eliminates a potential state-inconsistency bug with mirror workspaces, making the implementation significantly more robust.
- The explicit 'Decisions for Nathaniel' section is an excellent pragmatic tool, ensuring stakeholder buy-in on known trade-offs like hash collisions and focus-following behavior, which minimizes post-delivery surprises.
- The plan remains grounded in reusing existing mechanisms (`extensionSidebarProjectRootPath`, snapshot refresh paths, and the shared palette), which correctly contains implementation complexity and cost.
- The detailed and updated test plan, particularly the new case for a workspace becoming a mirror after its root resolves, provides high confidence in a successful and correct execution.
- The clarifications on future work (like the 'by branch' strategy) correctly separate the current, well-scoped effort from more complex future enhancements, keeping this change focused and achievable.

### Simplifier (simplifier)
**Verdict:** approve | **Confidence:** 0.95
**Changed from Round 2:** approve -> approve (no change)

The revised design maintains simplicity, clarity, and addresses previous concerns effectively.

- The modular design allows for easy extension and modification.
- Automatic coloring is a fallback, ensuring manual colors always take precedence.
- The design avoids unnecessary complexity by not persisting automatic colors and reusing existing components.
- The use of a shared palette ensures consistency and reduces the risk of color collisions.
- The design is off by default, aligning with the repository's rule for opinionated user-visible behavior.
- The revision rationale adequately addresses previous concerns and maintains the focus on simplicity and clarity.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.9
**Changed from Round 2:** needs_work -> needs_work (no change)

This design acknowledges critical usability flaws but proceeds with them, ensuring the feature remains a niche tool riddled with user friction and destined for low adoption.

- The fundamental issue of color collisions, explicitly noted as a 'trade-off,' means the core promise of quick visual differentiation is broken from the start, making it more of a nuisance than a help.
- The confirmed decision to allow colors to shift dynamically based on pane focus within a single workspace creates visual instability and will actively confuse users expecting consistent visual cues, especially when other identifiers remain static.
- The feature remains strictly 'By Worktree' for its initial release, leaving out common user workflows and cementing its status as a highly specialized tool for a tiny subset of users (like Nathaniel, specifically).
- By accepting these major usability compromises, the feature's 'off by default' state effectively guarantees it will be ignored by the vast majority of users, becoming technical debt without significant adoption.
- The design team explicitly noting that user concerns like collisions and focus-following are 'contentious, not resolved' but still proceeding reinforces that user experience is being deprioritized for specific workflow accommodations.

### Astra (astra)
**Verdict:** approve | **Confidence:** 0.95
**Changed from Round 2:** approve -> approve (no change)

My verdict remains approve: the revisions address the earlier concerns, and repository tracing revealed no new blocking interface omissions or implementation conflicts.

- The mirror-root correction is justified. RemoteTmuxController creates the workspace before setting isRemoteTmuxMirror (Sources/RemoteTmuxController.swift:509-515), while the root-walk completion checks only its refresh ID, not current provenance (Sources/Workspace.swift:3587-3608). Checking !usesRemoteDirectoryProvenance in the adapter therefore closes the identified hole without changing root resolution; that predicate also covers Cloud bindings and projected panes (Sources/Workspace+SidebarDirectories.swift:45-66).
- The shared fallback helper addresses both snapshot refresh paths. Full reconciliation calculates a per-row presentation key, while keyed refresh calls makeWorkspaceSnapshot directly (Sources/ContentView.swift:13281-13367); the cache correspondingly reuses matching presentation keys only during reconciliation and rebuilds requested rows during keyed refresh (Sources/Sidebar/SidebarRowSnapshotCache.swift:30-66). Root publication already participates in sidebar observation (Sources/WorkspaceSidebarObservation.swift:326-398), so the proposed observation-to-cache and unrelated-title-update tests cover the previously omitted integration seam.
- The branch-strategy qualification and focus-following decision now match the code. Directory reports update currentDirectory for the focused local pane, and focus reconciliation preserves the previous directory when the target has no reported directory (Sources/Workspace.swift:6351-6355,12609-12613). Sidebar directory and branch collections are independently assembled across ordered panes (Sources/Workspace+SidebarDirectories.swift:243-315). Keeping branch selection out of this first strategy avoids silently inventing a multi-pane rule.
- The revised origin-color rationale preserves existing contracts. Origin colors and host-title suffixes are independently gated (Sources/ContentView.swift:13376-13400), and the host registry retains cached collision probing rather than becoming the automatic assigner (Sources/RemoteHostColorRegistry.swift:76-115). Sharing only the hash and palette leaves those semantics intact; the retained palette tests exercise actual registry output and the documented distance floors (cmuxTests/RemoteHostColorRegistryTests.swift:100-155).
- Manual-color behavior remains compatible with both renderers. The snapshot already separates effective color from manual provenance (Sources/SidebarWorkspaceSnapshotFactory.swift:169-172,226-254); SwiftUI menu selection and clearing use that provenance (Sources/TabItemView+WorkspaceContextMenu.swift:156-188), while the native menu and prompt read the manual field directly (Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCommands.swift:183-188,541-575). The setting also fits the existing typed catalog and picker architecture (Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/WorkspaceColorsCatalogSection.swift:3-9; Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/WorkspaceColorsSection.swift:89-118). This approval is based on static repository tracing, not execution of the proposed tests.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.99
**Changed from Round 2:** reject -> reject (no change)

The prior concerns are resolved, but grouped anchor workspaces bypass the proposed color pipeline, contradicting the requirement that every local workspace shows an automatic color.

- The revision adequately fixes the prior provenance and host-suffix issues: locality includes SSH, mirrors, Cloud bindings and projected panes; mirror creation sets its flag after workspace creation; and origin colors and host-title suffixes remain independent settings (Sources/Workspace+SidebarDirectories.swift:45-65, Sources/RemoteTmuxController.swift:509-515, Sources/ContentView.swift:11558-11562).
- A grouped anchor workspace is never emitted as a workspace row; it is represented exclusively by the group header, while collapsed groups suppress all other workspace rows. Therefore the proposed SidebarWorkspaceSnapshotFactory fallback cannot color every local workspace—and a collapsed group can show no automatic worktree color at all (Sources/SidebarWorkspaceRenderItem.swift:50-79). This conflicts with the stated goal and the non-goal that group headers remain unchanged.
- Both sidebar renderers use a separate group-header snapshot path rather than the workspace-row snapshot path: AppKit dispatches group headers separately, and SwiftUI reads groupRowsById separately (Sources/ContentView.swift:12615-12650, Sources/ContentView.swift:14538-14573). The design must either add this missing consumer or explicitly narrow the feature to visible non-anchor workspace rows.
- Group-header color currently resolves only from the group's manual color or directory configuration, not from the anchor workspace's manual, origin or proposed automatic color (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:10-27, Sources/VerticalTabsSidebar+WorkspaceGroups.swift:263-299, Sources/VerticalTabsSidebar+WorkspaceGroups.swift:363-380). If automatic color is extended to headers, the document must define precedence among group color, anchor manual color and automatic color and add grouped, collapsed and both-renderer tests; otherwise its universal manual-wins and every-workspace claims must be narrowed.

## Design Lead Revision (after Round 3)
### Rationale
1. **sol (grouped anchors bypass the pipeline).** Valid, and verified: `SidebarWorkspaceRenderItem` skips the live anchor ("Anchor workspaces are represented exclusively by the group header") and skips members of a collapsed group. `groupColorHexByGroupId` resolves header color from `group.customColor ?? configColor(group)` only, never from the anchor's color. I narrowed the goal to visible workspace rows instead of extending the feature to headers. The anchor's manual color is not painted on the header today, so leaving the automatic color off the header keeps the existing rule ("the automatic color appears only where the manual color would"). Header coloring needs a precedence rule across four sources and overlaps the upstream group-color PR, so it is named as a follow-up. Added a groups test (members colored, header unchanged) and made the anchor gap an explicit decision for Nathaniel, since it affects nine of his rows.
2. **user.** No new concrete point. It restates collisions, focus-following, worktree-only and off by default as product objections. I keep the approach for the reasons given in the earlier rounds. Each trade-off is stated in the document and put to Nathaniel at approval, and it is recorded as contentious.
3. **astra, pragmatist, simplifier, devils-advocate (approve).** No change requested.

### Key Changes
- Narrowed the goal to visible workspace rows; group anchor workspaces (represented only by the header) get no automatic color, matching how their manual color is not painted on the header today.
- Documented the separate group-header color path (`groupColorHexByGroupId`) and named header coloring as a follow-up needing a four-way precedence rule.
- Added a groups test and an anchor-gap decision for Nathaniel.

## Round 4: Deliberation
### Devil's Advocate (devils-advocate)
**Verdict:** approve | **Confidence:** 0.9
**Changed from Round 3:** approve -> approve (no change)

The revised design adequately addresses the concerns raised and provides a solid foundation for the implementation.

- The design adequately addresses the concern about the suitability and reliability of the worktree directory as a key for color assignment.
- The design still does not guarantee distinct colors for all workspaces, but this is an accepted trade-off and a follow-up approach is described.
- The design explores alternative key strategies, such as using the workspace's stable ID or git branch, and leaves room for future extensions.
- The design considers the potential impact on performance and ensures that the automatic color assignment does not interfere with existing manual color assignments or user preferences.
- The design provides a detailed discussion on how to handle workspaces outside any git repository, workspaces with panes in different repositories, and collisions at small counts.
- The design provides a detailed discussion on how to handle the focus-following color in a workspace with panes in different repositories.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 1.0
**Changed from Round 3:** approve -> approve (no change)

The design is now even more pragmatic by explicitly scoping out the complexity of group header coloring and turning it into a documented decision point, further de-risking an already solid implementation plan.

- The decision to narrow the scope to visible workspace rows and defer group header coloring is a pragmatic move that avoids significant complexity and dependency on other work.
- Adding the group anchor behavior to the 'Decisions for Nathaniel' section strengthens an already excellent risk mitigation strategy by ensuring stakeholder alignment on known trade-offs.
- The implementation remains firmly grounded in reusing existing, proven mechanisms, which minimizes execution risk and cost.
- The test plan's explicit inclusion of group behavior confirms that this edge case is well-understood and will be validated, increasing confidence in the final deliverable.
- The revision process has successfully identified and neutralized a source of scope creep, demonstrating a mature and realistic approach to engineering.

### Simplifier (simplifier)
**Verdict:** approve | **Confidence:** 0.95
**Changed from Round 3:** approve -> approve (no change)

The revised design maintains simplicity, clarity, and addresses previous concerns effectively.

- The modular design allows for easy extension and modification.
- Automatic coloring is a fallback, ensuring manual colors always take precedence.
- The design avoids unnecessary complexity by not persisting automatic colors and reusing existing components.
- The use of a shared palette ensures consistency and reduces the risk of color collisions.
- The design is off by default, aligning with the repository's rule for opinionated user-visible behavior.
- The revision rationale adequately addresses previous concerns and maintains the focus on simplicity and clarity.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.95
**Changed from Round 3:** needs_work -> needs_work (no change)

The design team explicitly chose to proceed with acknowledged usability compromises, ensuring the feature remains niche and provides inconsistent value for most users.

- The team explicitly acknowledges and dismisses concerns about color collisions and dynamic color shifts, confirming the feature's inherent instability and limited utility for general users.
- The continued 'By Worktree' exclusivity and 'off by default' setting, combined with acknowledged flaws, ensures this feature will be largely ignored by anyone not fitting a very specific workflow.
- The decision to exclude group anchor workspaces from automatic coloring introduces further inconsistency, making the 'automatic' aspect fragmented and less intuitive, as some workspaces will get colors while functionally similar ones will not.
- The design explicitly prioritizes a single user's workflow over broader user experience, leading to a feature with known adoption barriers for the majority of the user base.

### Astra (astra)
**Verdict:** approve | **Confidence:** 0.95
**Changed from Round 3:** approve -> approve (no change)

My verdict remains approve: the group-anchor revision matches both renderers, preserves the previously reviewed boundaries, and introduces no new blocking concern in static repository tracing.

- The narrowed visible-row goal adequately addresses the group-anchor omission. Anchors are represented exclusively by headers, and collapsed members are excluded from ordinary rows (Sources/SidebarWorkspaceRenderItem.swift:55-79). Header colors resolve independently from group.customColor or configuration (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:17-27), and both native and SwiftUI header builders consume that separate result (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:78-89,280-291). Explicitly deferring header coloring and adding the member-versus-header test is consistent with the implementation.
- Grouped members still use the ordinary workspace snapshot; their group guide is a separate presentation value (Sources/ContentView.swift:15410-15438,15472-15473). Thus the revision can color member rows without changing header or guide precedence, rather than requiring an undocumented group-rendering change.
- The shared fallback helper continues to cover both refresh paths: keyed refresh invokes makeWorkspaceSnapshot directly, while full reconciliation also calculates a presentation key (Sources/ContentView.swift:13281-13367). Root publication already participates in workspace observation (Sources/WorkspaceSidebarObservation.swift:326-398). The proposed keyed-refresh and unrelated-title-update tests target the actual cache seam, whose keyed refresh bypasses presentation-key reuse (Sources/Sidebar/SidebarRowSnapshotCache.swift:30-66).
- The explicit locality guard remains necessary and correctly specified. Mirror creation sets isRemoteTmuxMirror after workspace creation (Sources/RemoteTmuxController.swift:509-515), and root-walk completion checks the refresh ID rather than current provenance (Sources/Workspace.swift:3587-3608). Using usesRemoteDirectoryProvenance excludes mirrors, SSH workspaces, Cloud bindings and projected panes even with a retained local root (Sources/Workspace+SidebarDirectories.swift:45-66).
- The retained boundaries preserve existing consumers: effective color and manual provenance are separate snapshot fields (Sources/SidebarWorkspaceSnapshotFactory.swift:169-172,226-254), menu selection and clearing remain manual-only (Sources/TabItemView+WorkspaceContextMenu.swift:156-188; Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCommands.swift:541-575), and sharing only the palette and hash preserves the host registry's cached collision probing (Sources/RemoteHostColorRegistry.swift:76-115). The palette-distance tests exercise actual registry output (cmuxTests/RemoteHostColorRegistryTests.swift:100-155). These conclusions are based on inspection; I did not execute tests.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.98
**Changed from Round 3:** reject -> reject (no change)

The anchor-workspace contradiction is resolved, but the revision retains factual errors about menu behavior and test-first coverage.

- The prior concern is adequately addressed: anchors are represented only by group headers and collapsed members are omitted, while header colors use only group/config colors; the narrowed visible-row goal now matches the repository (Sources/SidebarWorkspaceRenderItem.swift:50-79; Sources/VerticalTabsSidebar+WorkspaceGroups.swift:10-27; Sources/ContentView.swift:12615-12650; Sources/ContentView.swift:14538-14577).
- The claim that the Workspace Color menu and prompt already gate on hasManualCustomColor is only true for SwiftUI. The AppKit renderer reads tab.customColor directly for Clear Color, swatch selection, and prompt prefill. Its behavior remains correct, but the document misstates this second consumer and should distinguish the two paths (Sources/TabItemView+WorkspaceContextMenu.swift:157-190; Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCommands.swift:182-188; Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCommands.swift:540-578).
- The statement that an automatic color can never match a named Workspace Color entry is false because the named palette is user-editable and accepts arbitrary names and hex values. Such a match still will not show a checkmark because selection is manually gated, but the asserted palette trade-off is inaccurate (Sources/WorkspaceTabColorSettings.swift:42-56; Sources/WorkspaceTabColorSettings.swift:72-94; Sources/WorkspaceTabColorSettings.swift:137-144).
- The claim that every listed behavioral test fails before implementation conflicts with two listed tests. The existing project-root walk already accepts any .git filesystem entry, so a linked-worktree .git-file assertion should pass before this feature; the palette-distance test also already exists and passes. Classify these as characterization/refactor checks rather than red feature tests (Sources/Workspace.swift:3612-3619; cmuxTests/RemoteHostColorRegistryTests.swift:115-155).

## Convergence Trace
| Round | devils-advocate | pragmatist | simplifier | user | astra | sol | Consensus? |
|---|---|---|---|---|---|---|---|
| 1 | needs_work | approve | approve | needs_work | reject | reject | No (2/6 approve) |
| 2 | needs_work | approve | approve | needs_work | approve | reject | No (3/6 approve) |
| 3 | approve | approve | approve | needs_work | approve | reject | No: majority, but new critical issue (sol: group anchors) |
| 4 | approve | approve | approve | needs_work | approve | reject | Max rounds reached (4/6 approve; sol R4 points are non-blocking doc fixes) |

Round 4 was the last round, and its verdicts matched round 3: 4 approve, 1 needs_work, 1 reject. The reject (sol) cites three documentation inaccuracies that the design lead verified but did not revise, because rounds were exhausted. None of them changes behavior. The needs_work (user) is a product-scope objection already decided by the requester.

## Final Synthesis

### Issues That Converged
- **Two refresh paths** (astra, sol; R1). The keyed `refreshWorkspaceSnapshots(workspaceIds:)` bypasses the presentation key. Fixed by one fallback helper used by `makeWorkspaceSnapshot` and the full refresh's presentation key, plus end-to-end keyed-refresh tests. astra and sol both confirmed this in R2.
- **Locality predicate** (astra, sol; R1-R2). `isLocal = !usesRemoteDirectoryProvenance`, checked at paint time. A `nil` root does not imply remote, because a mirror is created local and flagged afterward. Confirmed in R3-R4.
- **Distinctness contradiction** (astra, sol, user, devils-advocate; R1). The promise was removed and collisions at any count are stated. Every persona accepted this as a trade-off except user, who still objects on product grounds.
- **Focus-following premise** (astra, sol; R1). The premise was corrected and focus-following is now an explicit product decision. Confirmed.

### Issues That Were Resolved
- The CLI does not gate on `hasManualCustomColor`; the document now says so (sol, R1).
- The registry is stateful: only `stableHash` and `hostPalette` are shared, and probing is kept (sol, R1).
- Startup flash from a `nil` root: the cwd fallback was dropped, so non-repo workspaces stay uncolored (sol, R1).
- Extensibility claim for "by branch" narrowed (sol, R2).
- Inaccurate host-suffix claim removed (sol, R2).
- Group anchors are rendered only as headers: the goal was narrowed to visible rows and header coloring deferred (sol, R3). astra and sol confirmed this in R4.

### Remaining Contentious Points
- **user (needs_work through all four rounds).** The objections: collisions undermine at-a-glance distinction, focus-following color is distracting, worktree-only plus off-by-default makes the feature niche, and the anchor exclusion makes coverage inconsistent. These are product trade-offs the requester chose. The document lists them under "Decisions for Nathaniel at approval" rather than resolving them.
- **sol (reject in R4)** on three documentation inaccuracies, all verified by the design lead and not yet fixed in the final draft:
  1. Only the SwiftUI menu gates on `hasManualCustomColor`. The AppKit row commands (`Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCommands.swift` ~185, ~546, ~568) read `tab.customColor` directly. Behavior is still correct; the doc should name both paths.
  2. "An automatic color never matches a named Workspace Color entry" is false, because the named palette is user-editable. A match still shows no checkmark.
  3. Two listed tests (the linked-worktree `.git`-file root assertion and the palette distance floors) already pass before the feature. They are characterization/refactor checks, not red-first tests.

### Recommended Actions
1. Apply sol's three R4 corrections to the spec before writing beads. Each is a wording fix with no design change.
2. Nathaniel answers the four "Decisions for Nathaniel at approval": non-repo workspaces uncolored, focus-following in multi-repo workspaces, small-count collisions, and group anchors uncolored (nine rows in his sidebar).
3. Replace the source spec with the final revised document (Appendix) once those decisions are made.
4. While dogfooding, look at how 45 rails read and whether focus-following bothers anyone.

### Deferred
- A persisted allocator or live-set probing for distinctness, behind the assigner seam.
- Coloring a group header from its anchor's worktree, which needs a precedence rule across group color, config color, the anchor's manual color and the automatic color. This overlaps the upstream group-color PR.
- "By workspace", "by group" and "by branch" strategies. Branch needs a new input field and a multi-pane rule.
- Symlink-spelling normalization of worktree paths.

## Appendix: Final Revised Document

# Workspaces color themselves by worktree

Design for the epic "Workspaces automatically color themselves". Brainstormed 2026-11-13;
Nathaniel chose the color key (the worktree directory), the build approach (a paint-time
fallback beside the remote-host origin color) and asked that the key derivation sit behind a
seam that can be swapped or extended later.

## Intent

A workspace gets a sidebar color only when someone picks one, from the row's context menu,
the CLI's `set-color` action or a cmux.json launch action. Nathaniel runs one workspace per
git worktree or epic, 45 workspaces in 9 groups, so the sidebar is a column of same-colored
rows and nothing tells them apart at a glance.

After this change every local workspace inside a git repository shows a color without
anyone choosing one. The color is derived from the workspace's git worktree directory, so
the same worktree shows the same color after a restart, after its workspace is closed and
reopened, and on another Mac with the same checkout path. Different worktrees usually get
different colors, but nothing guarantees it: the color is a hash into a sixteen-entry
palette, and any two worktrees can share one (see Non-goals). A manually chosen color
always wins.

The derivation is split into two replaceable parts: a **key strategy** that turns a
workspace into a string (today: its worktree root) and a **color assigner** that turns the
string into a hex (today: a stable hash into a palette). The setting that turns the feature
on names the strategy, so adding "by workspace" or "by group" later is one new enum case
and one new key strategy, with no change to how colors are painted. "By branch" also needs
a branch field on the strategy input and a rule for which pane's branch a multi-pane
workspace uses; it still leaves painting untouched.

## Goals

- Every visible workspace row for a local workspace whose directory is inside a git
  repository shows a color with no user action, under both indicator styles (left rail and
  solid fill) and in both sidebar renderers (AppKit table, SwiftUI stack). A workspace
  outside any repository stays uncolored. A group's anchor workspace has no row (the group
  header stands for it), so it gets no automatic color, just as its manual color is not
  painted on the header today; members of a collapsed group have no visible row.
- The same worktree directory always gets the same color: across restarts, across close and
  reopen, across machines, in every window.
- A manual color wins over the automatic one. Clearing the manual color reveals the
  automatic one again.
- Turning the setting off removes every automatic color at once and leaves no trace: the
  feature writes nothing to the workspace, the session manifest or the customization store.
- The key strategy and the color assigner are separately replaceable, and the setting that
  enables the feature is an enum that can grow new strategies.
- Off by default in this first change, with a Settings row and a cmux.json key to turn it on.

## Non-goals

- Distinctness. The assigner is a hash modulo sixteen with no probing, so any two
  worktrees can share a color, even two siblings with only two worktrees open (for
  example `/repo/.worktrees/feature-9` and `/repo/.worktrees/feature-10` both land on slot
  4). With five worktrees open the odds that some pair shares a color are about one in
  two; with Nathaniel's 45 rows sharing is certain. The color narrows the search and the
  title and group finish it. A persisted allocator that keeps colors distinct is the
  follow-up described under "Approaches", and it fits behind the assigner seam.
- Any strategy other than the worktree directory. "By workspace" (stable id), "by branch"
  and "by group" are named as future enum cases so the seam is shaped for them; none ships
  here. Say this plainly when the setting lands: the picker offers Off and By Worktree only.
  The input carries the stable id and group id so those two strategies need no input
  change; it does not carry a branch, which that strategy would add with its own
  multi-pane rule.
- Showing the automatic color anywhere the manual color is not already shown: the socket's
  workspace reads, the iOS workspace list, custom sidebars and notification rows keep
  reporting the manual color only.
- Changing the group header color or how members inherit it. Upstream pull request
  "Sidebar: workspaces in a colored group take the group's color" covers that and is
  independent of this change. Group headers have their own snapshot path in both renderers
  (`groupColorHexByGroupId` resolves `group.customColor`, else the per-directory group
  config color) and never read the anchor workspace's color; this change leaves that path
  alone. Coloring a header from its anchor's worktree would need a precedence rule among
  the group color, the config color, the anchor's manual color and the automatic color,
  and is a follow-up.
- Changing the Workspace Color menu, the custom color prompt, or the CLI. The CLI's
  `set_color` and `clear_color` write `workspace.customColor` directly; with the setting
  on, `clear_color` therefore reveals the automatic color, which is the intended
  "clearing reveals the automatic one" behavior.
- Remote, Cloud and remote-tmux mirror workspaces, and mixed workspaces that hold any
  Cloud-projected pane. They keep the origin-color beta behavior and get no automatic
  color. The predicate is `Workspace.usesRemoteDirectoryProvenance`, the same one that
  stops the project-root walk, and it is checked at paint time rather than inferred from a
  `nil` root (see Constraints).

## Anti-goals

- A loud sidebar. Nathaniel's 45 rows will all carry a rail; the palette must stay soft and
  the rail stays a thin stripe. The group-dividers design named a rainbow sidebar as a
  failure; so does this one.
- Filesystem or git work inside a row. Rows receive immutable snapshots; the worktree root
  is resolved above the list boundary and cached.
- A row that looks hand-colored when it is not. Clear Color must stay hidden, no palette
  swatch may show a checkmark, and the custom color prompt must not prefill from an
  automatic color.
- Writing the derived color into the manual color field, at creation or later. That would
  make it impossible to turn off, indistinguishable from a choice, and frozen at creation.

## Constraints

- The sidebar resolves one effective row color above the list boundary and carries it on
  the row snapshot as `customColorHex`, with `hasManualCustomColor` beside it. Today that
  value is "manual color, else origin color", computed in the snapshot factory and in the
  snapshot cache's presentation key. The automatic color must enter through that same
  chain so both renderers, the cache invalidation and the menu gating all pick it up.
- The origin-color beta is the precedent: a per-host color hashed from the host name into a
  sixteen-color palette, gated by a flag, never persisted, resolved once per refresh. The
  automatic color follows its shape and its tests.
- The palette the origin color uses was tuned for the brightened rail: its author showed
  that the workspace color menu's palette (dark reds and magentas) collapses once the rail
  brightens it, and `RemoteHostColorRegistryTests` asserts OKLab distance floors between
  every pair, between neighbors, against the grey sidebar and against the default accent.
  Those floors must keep holding after the palette moves to a shared home.
- `Workspace` already publishes a project root (`extensionSidebarProjectRootPath`): whenever
  `currentDirectory` changes it walks upward on a detached utility task to the nearest
  directory holding a `.git` entry, file or directory, so a linked worktree resolves to its
  own directory and not the main checkout. The walk is fenced by a refresh id so a stale
  result never lands, the value is `nil` for directories outside any repository, and the
  previous value stays in place while a new walk runs. The value starts `nil` on a new or
  restored workspace until the first walk returns. The walk's remote guard is
  `usesRemoteDirectoryProvenance`, which is true for ssh remotes, remote-tmux mirrors,
  Cloud bindings and any workspace with a Cloud-projected pane. That guard runs only when
  a walk is scheduled, so a `nil` root does not prove a workspace remote, nor a non-`nil`
  root prove it local. A remote-tmux mirror is created as an ordinary workspace (which
  schedules a local walk) and only then has `isRemoteTmuxMirror` set; the flag has no
  observer and the walk's completion does not recheck provenance, so a mirror can keep a
  local root. Locality must therefore be checked directly at paint time, never inferred
  from the root. The sidebar observation already includes the value
  (`WorkspaceSidebarObservation`), so a row refreshes when it changes. The worktree key
  reads this value; no new git walk, package API or cache is needed, and nothing touches
  the filesystem during a sidebar refresh.
- `currentDirectory` is reassigned when focus moves to a pane that has a reported
  directory; focusing a pane with no reported directory leaves the previous value. It is
  therefore "the directory of the most recently focused pane that reported one", not
  strictly the focused pane's. The row's branch and directory lines do not follow it: they
  list every pane's branch and directory in spatial order. So in a workspace whose panes
  sit in different repositories, the color picks one of the displayed directories and can
  change on focus while the text does not.
- The sidebar refreshes through two paths that both build snapshots with the shared
  `makeWorkspaceSnapshot` helper in `ContentView`: the full `refreshWorkspaceSnapshots()`
  (initial load and settings changes), which reconciles against a per-row presentation
  key, and the keyed `refreshWorkspaceSnapshots(workspaceIds:)`, which the per-workspace
  observation and coalescer call on ordinary changes such as a cwd or project-root update.
  The keyed path replaces snapshots directly and never consults the presentation key.
- Settings follow the catalog pattern: a typed key in `WorkspaceColorsCatalogSection`, a
  Settings → Workspace Colors row, the cmux.json parser and template, the supported-paths
  list, the JSON path support, the generated schema (`scripts/generate-cmux-config-schema.py`),
  the settings search index and aliases, the curated entry list, `all-keys.md` and the
  appearance docs. The `sidebar.groupDividers` change is the most recent complete example.
- App-linked code stays Swift 6.0 compatible. User-facing strings go through the
  localization audit.
- The repo rule for opinionated user-visible behavior: ship behind a setting first.

## Approaches

Three ways were considered. Nathaniel chose A.

**A. Paint-time fallback beside the origin color (chosen).** The effective row color becomes
"manual, else origin, else automatic". A resolver asks the key strategy for the workspace's
string and the assigner for the string's hex. Nothing is stored; the color is a pure
function of the setting, the project root and the palette. Turning the setting off clears
every automatic color on the next refresh. Trade-off: no distinctness guarantee at any
count; two worktrees can collide.

**B. Persisted allocator, re-keyed.** The shape of the open upstream pull request "Add Left
Rail Auto workspace color indicator mode", keyed by the strategy's string instead of the
workspace id: assign the least-used color on first sight and remember it per key. Colors
stay distinct until the palette runs out. Costs a store to reconcile on palette edits,
stale keys to evict, and colors that can swap between Macs or restarts depending on
first-seen order. Roughly ten times the code. Fits behind the assigner seam later if hash
collisions turn out to bother Nathaniel.

**C. Materialize at creation.** Write the derived hex into the workspace's manual color when
the workspace is created. Dropped: cannot be turned off, indistinguishable from a choice,
never follows a `cd`.

**Key alternatives**, for the record: the workspace's stable id (every row distinct, but a
reopened worktree gets a new color), the git branch (changes on checkout, absent outside a
repo), the group (members cannot be told apart, which is Nathaniel's case). The worktree
directory was chosen because it is Nathaniel's unit of work: he runs one workspace per
worktree, so multi-repository workspaces, where the focus-following behavior shows, are
rare for him.

**Live-set probing**, also considered: probe past collisions among only the worktrees
open right now, recomputed each refresh. It needs no store, but a worktree's color would
change when another one opens or closes, which breaks the stability goal. Not chosen; it
fits behind the assigner seam if distinctness turns out to matter more than stability.

**Palette.** The sixteen soft colors the origin-color registry uses, moved to a shared home,
rather than the user-editable workspace palette. Reason: the rail brightens colors, and the
workspace palette's reds and magentas collapse under that; the host palette has tested
distance floors. Trade-off: an automatic color never matches a named entry in the Workspace
Color menu. Nathaniel accepted this.

**Default.** Off. Nathaniel turns it on with one line in cmux.json. Reason: the repo rule.

## Design

### Setting

A new key in the `workspaceColors` catalog section:

| Dotted id | Type | Default | UserDefaults key |
| --- | --- | --- | --- |
| `workspaceColors.autoColor` | enum `WorkspaceAutoColorMode` | `off` | `workspaceColorsAutoColor` |

`WorkspaceAutoColorMode` is a `String`-backed, `CaseIterable`, `Sendable`, `SettingCodable`
enum with the cases `off` and `worktree`. Unknown strings decode to `nil` so the default
applies, and the cmux.json parser logs the invalid value the way the indicator style does.
Future cases (`workspace`, `branch`, `group`) are not declared; a comment names them.

Settings → Workspace Colors gets a picker row "Automatic Colors" with the choices "Off"
and "By Worktree", placed directly under the indicator style row, with a subtitle
explaining that workspaces without a chosen color take one from their git worktree and that
a chosen color always wins. It appears in settings search and the curated entry list.

cmux.json: `"workspaceColors": { "autoColor": "worktree" }`. The template writes the default,
the schema lists the enum, `all-keys.md` and `docs/customizing-appearance.md` document it.

### Resolver and its seams

Three small types, pure and testable, in the app target beside `RemoteHostColorRegistry`:

```swift
/// What a key strategy may look at. A plain value, so strategies never touch Workspace.
struct WorkspaceAutoColorInput {
    let stableId: UUID
    let currentDirectory: String   // Workspace.currentDirectory (last focused pane that reported one)
    let projectRootPath: String?   // Workspace.extensionSidebarProjectRootPath
    let groupId: UUID?
    let isLocal: Bool              // !Workspace.usesRemoteDirectoryProvenance
}

protocol WorkspaceAutoColorKeyProviding {
    /// nil means "no automatic color for this workspace".
    func key(for input: WorkspaceAutoColorInput) -> String?
}

protocol WorkspaceAutoColorAssigning {
    /// A palette hex for the key. Pure: the same key yields the same hex in every process.
    func colorHex(forKey key: String) -> String?
}

struct WorkspaceAutoColorResolver {
    init(mode: WorkspaceAutoColorMode, keyProvider: any WorkspaceAutoColorKeyProviding,
         assigner: any WorkspaceAutoColorAssigning)
    func colorHex(for input: WorkspaceAutoColorInput) -> String?   // nil when mode is .off
}
```

A static factory maps a mode to its key provider, so adding a strategy is a new enum case,
a new provider type and one line in the factory. The assigner is shared by every strategy.

One adapter, `WorkspaceAutoColorInput.init(workspace:)` (or a static `make(from:)`), is the
only place that reads `Workspace`. It maps `isLocal` from `!usesRemoteDirectoryProvenance`,
so a mixed workspace with any Cloud-projected pane is not local, and it reads the predicate
on every refresh, so a workspace that became a mirror after its root resolved is excluded
even though its root is still set. The key provider checks `isLocal` before the root, and
that guard is load-bearing, not redundant. The adapter is `@MainActor`, reads
only published values and does no filesystem work. The `stableId` and `groupId` fields
have no consumer in this change; they exist so a future strategy does not widen the
input, and the builder may drop them if review prefers a minimal struct.

### Key strategy: worktree directory

`WorktreeDirectoryKeyProvider` is a pure function of its input. It returns
`projectRootPath` for a local workspace (for a linked worktree that is the worktree
directory, not the main checkout) and `nil` otherwise: for a non-local workspace, and
whenever the root is `nil` (outside any repository, or not yet resolved). It does not fall
back to `currentDirectory`. It does no filesystem work and holds no state; tests construct
inputs directly.

Dropping a cwd fallback is deliberate. With one, a restored or new workspace would hash its
subdirectory for the moment before the first root walk returns, so two rows in one
worktree could briefly show different colors and then both change. Without it a row is
uncolored until its root resolves and then takes its final color: on startup a color
appears and never changes hue. The cost is that workspaces outside any repository get no
automatic color, which matches the setting's name ("By Worktree").

Consequences of reusing the existing root, all accepted:

- The color follows `currentDirectory`, which tracks the most recently focused pane that
  reported a directory. A workspace whose panes sit in different repositories changes
  color when focus moves between them, even though its branch and directory lines, which
  list every pane, do not change. This is a product decision, kept because Nathaniel runs
  one worktree per workspace; dogfooding checks it, and a future key strategy (for example
  "first pane in spatial order") can replace it behind the same seam.
- After a `cd` the root resolves asynchronously. Moving within one worktree never flashes,
  because the previous root stays until the walk returns the same value. Moving from one
  worktree to another shows the old color for the few milliseconds the walk takes, then
  the new one. Moving out of every repository clears the color when the walk returns
  `nil`.
- No symlink resolution is done, so two spellings of one directory may differ; the shell
  reports one spelling per directory in practice.

### Color assigner: stable hash

`HashedPaletteAssigner` computes the FNV-1a/64 hash the origin-color registry already uses,
takes it modulo the palette count and returns that entry. No probing, no state.

Only the hash function and the palette are shared. `RemoteHostColorRegistry` is not a
stateless assigner: it caches a slot per host and linear-probes past collisions, and its
tests require that. It keeps all of that. The static `stableHash` and `hostPalette` move to
a shared `WorkspaceDistinguishingPalette` (name is the builder's call); the registry reads
them from there and either keeps forwarding static members or its tests' references
(`RemoteHostColorRegistry.stableHash`, `.hostPalette`) are updated. No other code
references them today. Automatic colors and host colors share a palette but not the
registry's slot table, so a remote row's origin color and a local row's automatic color
can be the same hue. That is accepted: the two flags are independent, and nothing else
reliably marks a remote row by color (the host-title suffix is its own beta flag and only
names hosts whose titles collide).

### Where it plugs in

`ContentView` computes the origin color per workspace above the list boundary in two
places: the shared `makeWorkspaceSnapshot` helper, which passes it to
`SidebarWorkspaceSnapshotFactory` and serves both the full and the keyed refresh, and the
full refresh's presentation-key closure. The automatic color must reach both refresh
paths, so it enters through one helper rather than at either call site:

- A single `ContentView` helper returns a workspace's fallback color (origin, else
  automatic) from the current setting. `makeWorkspaceSnapshot` and the presentation-key
  closure both call it, so the two cannot drift.
- The factory takes the automatic color as a plain value beside `originColorHex` (or one
  combined fallback parameter; builder's call), and its chain becomes:

```
customColorHex = workspace.customColor ?? originColorHex ?? autoColorHex
hasManualCustomColor = workspace.customColor != nil
```

The resolver is a cheap value (an enum and two stateless structs); building it per call or
per refresh is equally fine.

On the full refresh `customColorHex` is part of the presentation key, so a changed
automatic color rebuilds the row's cached snapshot, exactly as a changed origin color
does. The keyed refresh rebuilds the snapshot unconditionally and compares it, so the new
color lands as long as `makeWorkspaceSnapshot` computes it. The project root is already
an observed input, so a `cd` into another worktree reaches the keyed refresh with no new
observer; an integration test proves it (see Tests). Toggling the setting refreshes the
sidebar the way the origin-colors flag does (a live setting with an `onChange` that
triggers the full refresh).

### What stays unchanged, by construction

- The Workspace Color menu and the custom color prompt already gate on
  `hasManualCustomColor`, so with only an automatic color Clear Color is absent, no swatch is
  checked and the prompt opens empty. The CLI does not gate on it and needs no gate: it
  sets or clears `customColor`, and the automatic color sits beneath that.
- The customization store, session manifest and socket reads see only `customColor`.
- Group header colors, member inheritance, drag and drop, row heights: untouched. The
  change is paint-only and rides on the existing color field.

### Tests

Behavioral tests, each failing before its code lands:

- Key provider: an input with a project root keys to that root regardless of how deep the
  cwd is; an input with no root keys to `nil`; a non-local input with a root keys to `nil`.
- Input adapter: built from real `Workspace` instances, `isLocal` is false for an ssh
  remote, a remote-tmux mirror whose host has not resolved, a Cloud-bound workspace, and a
  local workspace holding one Cloud-projected pane; it is true for a plain local
  workspace. One case builds a local workspace, lets its root resolve, then sets
  `isRemoteTmuxMirror = true` (the order `RemoteTmuxController` uses) and asserts no
  automatic color although the root is still published.
- Project root resolution (existing code, one new assertion): a nested directory inside a
  linked worktree fixture (a temp directory whose `.git` is a file) resolves to the
  worktree directory, not the main checkout, so the key strategy's premise holds.
- Assigner: the same key gives the same hex from two separate instances; every hex is in the
  palette; sixteen distinct keys do not all land on one color.
- Resolver: mode `off` gives `nil` regardless of input; mode `worktree` composes provider and
  assigner.
- Snapshot factory: with a manual color, the manual color wins and `hasManualCustomColor` is
  true; with only an automatic color, `customColorHex` is the automatic color and
  `hasManualCustomColor` is false; with the mode off, `customColorHex` is nil.
- Snapshot cache: a changed automatic color changes the presentation key (the existing
  origin-color test is the model).
- Keyed refresh, end to end: with the setting on, publishing a new
  `extensionSidebarProjectRootPath` on a workspace drives the observation, coalescer and
  `refreshWorkspaceSnapshots(workspaceIds:)` path, and the cached row's `customColorHex`
  becomes the new worktree's color. A second case asserts an unrelated keyed update (a
  title change) keeps the automatic color rather than dropping it.
- Focus: in a two-pane workspace whose panes are in different worktrees, focusing the
  other pane changes the color; focusing a pane with no reported directory does not.
- Groups: with the setting on, a grouped member's row carries its automatic color, and the
  group header's color is unchanged (still nil for a group with no custom or config
  color) even though its anchor workspace has a resolved worktree root.
- Setting: JSON and UserDefaults decode of `off`, `worktree` and an unknown string; the
  supported-paths list and the settings search index include the new key (the
  `sidebar.groupDividers` tests are the model).
- Palette: `RemoteHostColorRegistryTests` distance floors still pass against the moved palette.

### Verification and delivery

`python3 scripts/verify-local.py` for the scoped lanes, the focused `cmuxTests` suites run
locally per the fork's test flow, the localization audit for the new strings, and the
schema regeneration check. Dogfood on a tagged dev build with the setting on: Nathaniel's
sidebar shows a rail on every visible local repository row (group headers unchanged), two workspaces in the same worktree
match, a manual color overrides, Clear Color is absent on an auto-colored row, after a
restart each row is uncolored for at most a moment and then takes its final color with no
second change, and turning the setting off clears every rail. Note how the rail reads
across 45 rows; if it is loud, the palette or rail width is the follow-up.

## Left to the builder

- Names and file placement of the new types, within the constraints above.
- Picker and subtitle wording, within the localization audit.
- Where in the appearance docs the key is described, beside the other `workspaceColors` keys.
- Whether the factory takes the automatic color as its own parameter or one combined
  fallback.

## Decisions for Nathaniel at approval

- Workspaces outside any git repository get no automatic color; the cwd fallback was
  dropped to avoid a color change during startup. Say if they should be colored anyway.
- In a workspace with panes in different repositories the color follows focus while the
  branch and directory lines do not.
- Collisions happen at small counts, not only past sixteen worktrees.
- Group anchor workspaces (one per group, nine in Nathaniel's sidebar) get no automatic
  color, because the group header stands for them and header coloring is out of scope.
  Say if the header should take its anchor's worktree color in this change instead.
