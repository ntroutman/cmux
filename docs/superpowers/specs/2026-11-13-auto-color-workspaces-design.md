# Workspaces color themselves by worktree

Design for the epic "Workspaces automatically color themselves". Brainstormed 2026-11-13;
Nathaniel chose the color key (the worktree directory), the build approach (a paint-time
fallback beside the remote-host origin color) and asked that the key derivation sit behind a
seam that can be swapped or extended later. Revised the same day after a four-round design
review in which two reviewers read the repository; the round-by-round record, including the
code facts the first draft got wrong, is in the companion file
`2026-11-13-auto-color-workspaces-design-consult.md` beside this one.

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
  and belongs to the separate workspace-groups session that owns header coloring.
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
- Filesystem or git work inside a row or during a sidebar refresh. Rows receive immutable
  snapshots; the worktree root is the one the workspace already publishes.
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
distance floors. Trade-off: the automatic colors are not entries in the Workspace Color menu,
so a row's automatic hue has no name there. Because that palette is user-editable, a user
can add a matching hex; even then no swatch shows a checkmark, since selection is gated on
the manual color. Nathaniel accepted this.

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

- Both Workspace Color menus already read only the manual color, by different routes: the
  SwiftUI row gates Clear Color, the swatch checkmark and the prompt prefill on the
  snapshot's `hasManualCustomColor`, and the AppKit row commands read `tab.customColor`
  directly for the same three. With only an automatic color, Clear Color is absent, no
  swatch is checked and the prompt opens empty in both renderers. The CLI does not gate
  and needs no gate: it sets or clears `customColor`, and the automatic color sits beneath.
- The customization store, session manifest and socket reads see only `customColor`.
- Group header colors, member inheritance, drag and drop, row heights: untouched. The
  change is paint-only and rides on the existing color field.

### Tests

Behavioral tests. Each test of new behavior fails before its code lands. Two are
characterization checks of code this design relies on and pass today: the linked-worktree
root assertion and the palette distance floors.

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

## Decisions at approval

Nathaniel approved the spec on 2026-11-16 with these four trade-offs as written:

- Workspaces outside any git repository get no automatic color; the cwd fallback was
  dropped to avoid a color change during startup.
- In a workspace with panes in different repositories the color follows focus while the
  branch and directory lines do not.
- Collisions happen at small counts, not only past sixteen worktrees.
- Group anchor workspaces (one per group, nine in Nathaniel's sidebar) get no automatic
  color here, because the group header stands for them. Header coloring is owned by a
  separate session working on workspace groups, not by this epic.
