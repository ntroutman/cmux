# Sidebar workspace groups: Group Color menu and automatic colors

Design for the epic "Group Color submenu on the workspace group header context menu".
Brainstormed 2026-11-13. Nathaniel chose the menu shape, added automatic coloring, and
picked the collision rule recorded below. Revised the same day after a three-round design
review in which two reviewers read the repository; the round-by-round record, including
the code facts the first draft got wrong, is in the companion file
`2026-11-13-sidebar-group-color-picker-design-consult.md` beside this one.

## Intent

The epic "Give workspace groups a more visually distinctive divide in the sidebar" (PR #2 on
the fork) gave every group a header band and an indent guide drawn in the group's color. A
user still has no way to set that color from the UI. Today the color comes from two places
only: the CLI (`cmux workspace-group set-color <group> --hex #RRGGBB`) and a `color` in a
per-directory workspace-group config in cmux.json, resolved from the anchor workspace's
directory. Nathaniel expected a picker like the one workspaces have.

Two changes:

- A **Group Color** submenu on the group header's context menu, in both sidebar renderers,
  shaped like the existing Workspace Color submenu: the shared palette swatches, Choose
  Custom Color…, and Clear Color when the group has a manually set color.
- **Automatic group colors**: a group with no manual or config color takes a palette color
  chosen from a stable hash of its name, so a sidebar of several groups is colored without
  anyone choosing, and the colors survive restarts.

## Goals

- Right-clicking a group header in either renderer offers Group Color with the palette
  swatches, Choose Custom Color…, and (only when a manual color is set) Clear Color.
- Picking a swatch recolors the header icon, band, guide and multi-selection wash at once,
  and the color persists across relaunch.
- The menu and the CLI store the same value for the same color.
- Clear Color falls back to the config color, then the automatic color, then neutral.
- With automatic colors on and a non-empty automatic palette, every group has a color.
  Two groups whose names hash to the same slot get different colors while unused colors
  remain; with more uncolored groups than colors, repeats are unavoidable. A group's color
  is the same after a restart as long as the group names, the automatic palette, and the
  manual and config colors are unchanged.
- One setting turns automatic colors off and restores today's neutral fallback, with one
  deliberate difference that holds whether the setting is on or off: a manual or config
  color that is not a valid hex now counts as absent and lets the next rung through, where
  today it wins and then paints neutral.
- New strings carry every locale the catalog check requires.

## Non-goals

- A Group Icon picker. The CLI's `set-icon` has the same gap; it is a separate follow-up.
- Exposing the effective (config or automatic) color over the socket, in `workspace-group
  list`, or in the custom-sidebar data context. Those report the manual color only, as today.
- Automatic colors for workspaces. Workspace rows keep their origin tint fallback.
- A native color panel. The custom-color entry stays the hex alert the workspace menu uses.
- Bulk color editing. Group headers do take part in multi-selection (Command- or
  Shift-click adds anchors through `SidebarSelectionKindPolicy.anchorCmdClickSelection`),
  but Group Color acts only on the group whose header was context-clicked, whatever else
  is selected. Existing selection behavior is unchanged.

## Anti-goals

- A group whose color was hand-picked ever changing color without the user acting.
- Automatic colors leaking into persisted state. Only manual colors are stored; the
  automatic color is recomputed from the name on every refresh.
- The SwiftUI menu body reading the live model. Rows are built from snapshots below the
  list boundary and the menu must respect that rule.

## Constraints

- Both renderers must offer the same menu: the AppKit table (default) and the SwiftUI lazy
  stack fallback. They already share one action bundle, `SidebarGroupHeaderRowActions`,
  built once in `VerticalTabsSidebar+WorkspaceGroups.swift`.
- The header models carry only the effective color (`tintHex`). The workspace menu gates
  Clear Color and the checkmark on the manual color, not the effective one, and this menu
  must do the same.
- The CLI path normalizes hex in the socket layer; `TabManager.setWorkspaceGroupColor`
  stores whatever it is handed. The two existing normalizers almost agree on `#` plus six
  uppercase hex digits, but not quite: `WorkspaceTabColorSettings.normalizedHex` checks
  the length and then parses with `UInt64(_:radix:)`, which accepts a leading sign, so
  `+12345` becomes `#+12345`. `ControlCommandCoordinator.normalizeHexColor` requires six
  ASCII hex digits and rejects it. The design closes that gap (see One mutation path).
- The shared palette is user-editable and grows. `WorkspaceTabColorSettings.palette()`
  returns the built-in names in built-in order, then every custom entry sorted by name.
  Choose Custom Color… adds a custom entry, an explicitly empty stored palette is valid,
  and two names may hold the same hex.
- `SidebarTabItemSettingsStore` observes every UserDefaults change but republishes only
  when the rebuilt `SidebarTabItemSettingsSnapshot` differs, so anything the sidebar
  renders from UserDefaults has to be in that snapshot.
- App-linked code stays Swift 6.0 compatible. `WorkspaceTabColorSettings` lives in the app
  target; the group coordinator lives in the `CmuxWorkspaces` package and cannot see it.
- The string catalog check requires nine macOS locales for every new key (`en`, `de`,
  `fr`, `ar`, `es`, `zh-Hant`, `zh-Hans`, `ko`, `ja`).
- Read `cmux-shared-behavior` (menu, CLI and config are entry points to one color),
  `cmux-debugging` (SwiftUI list snapshot boundary), `cmux-localization` and
  `cmux-testing` before editing.

## Approaches

### Where the menu learns the manual color

| | Approach | Trade-off |
|---|---|---|
| 1 | **A `customColorHex` field on both header models**, set from `group.customColor` in the two snapshot builders (chosen) | Three structs grow a field and the SwiftUI view's `==` grows a clause; follows the workspace rows' `hasManualCustomColor` pattern and keeps menus reading snapshots only |
| 2 | A closure on the action bundle resolved when the menu opens, like `notificationState()` | No model change, but the SwiftUI `.contextMenu` body would read `TabManager` across the list snapshot boundary the rows are built to respect |

### Where hex normalization lives

| | Approach | Trade-off |
|---|---|---|
| 1 | **In `TabManager.setWorkspaceGroupColor`** (chosen) | Every caller, present and future, stores the same canonical value; the socket layer's own normalization becomes a redundant early validation, which is fine |
| 2 | In each caller | The menu's inputs are already canonical, so it works today, but the next caller can store `c0392b` and the checkmark never matches |

### Automatic color collisions

| | Approach | Trade-off |
|---|---|---|
| 1 | Pure hash, no probing | Perfectly stable; colliding groups share a color |
| 2 | **Hash, then probe in name order** (chosen) | Distinct colors; stable while the set of names holds; adding a colliding group can shift one neighbor's color |
| 3 | Hash and probe in first-seen order, as `RemoteHostColorRegistry` does | Distinct, but a collider's color depends on load order and can swap across restarts |

Nathaniel picked option 2.

## Design

### Group Color submenu

**Placement.** Directly after Pin Group / Unpin Group, before the divider that starts the
Mark Read items, in both renderers. Those are the group's own identity items; the
workspace menu puts its color submenu next to its naming items for the same reason.

```
New Workspace in Group
──────────────
Rename Group…
Pin Group
Group Color              ▸   Clear Color            (manual color only)
──────────────               Choose Custom Color…
Mark Group as Read           ──────────────
…                            ✓ ● Blue
                               ● Green
                               ● …
```

**Items**, mirroring `TabItemView+WorkspaceContextMenu.swift` and the AppKit
`addColorMenu(to:)` in `SidebarWorkspaceRowCommands.swift`:

- *Clear Color* (`xmark.circle`), shown only when `customColorHex` is non-nil. Calls the
  set action with `nil`.
- *Choose Custom Color…* (`paintpalette`). Runs the shared hex alert seeded with the manual
  color (nil when none; the alert then seeds from the first custom palette entry, as
  today), and on Apply calls the set action with the normalized value.
- A divider when the palette is non-empty.
- One row per `WorkspaceTabColorSettings.palette()` entry (the full shared palette,
  custom entries included): swatch circle, name, and a checkmark when
  `paletteEntryMatches(currentHex: customColorHex, entryHex:)`. An automatic or config
  color never shows a checkmark; only a manual color counts as chosen, the rule the
  workspace menu already follows.

**Strings.** Reuse `contextMenu.clearColor` and `contextMenu.chooseCustomColor`
unchanged. New keys: `workspaceGroup.contextMenu.color` = "Group Color", and
`alert.customGroupColor.title` = "Custom Group Color" for the alert title. The alert's
message, Apply, Cancel and invalid-color strings are reused.

**Action bundle.** `SidebarGroupHeaderRowActions` gains two closures:

- `onSetColor: (String?) -> Void`, wired in `makeWorkspaceGroupHeaderActions` to
  `tabManager.setWorkspaceGroupColor(groupId:hex:)`.
- `onChooseCustomColor: () -> Void`, wired to run `WorkspaceCustomColorPrompt` against the
  window that contains the live anchor (the same window lookup `onRename` uses), then call
  `onSetColor` with the result.

`WorkspaceCustomColorPrompt.run` gains a title parameter (or a sibling entry point) so the
group alert says "Custom Group Color"; the workspace callers keep their title. Colors it
adds land in the one shared palette, which is intended; they appear in the menus but do
not join the automatic palette (see below).

**Target group.** Every menu action is bound to the context-clicked header's `groupId`,
never to the current selection. A multi-selection of several anchors is left as it is.

**Manual color on the models.** Add `customColorHex: String?` and `brightenInDarkMode:
Bool` to `SidebarWorkspaceGroupRowSnapshot`, `SidebarWorkspaceGroupHeaderView` (and its
manual `==`), and `SidebarGroupHeaderRowModel`. Both snapshot builders in
`VerticalTabsSidebar+WorkspaceGroups.swift` set them from `group.customColor` and
`settings.brightenInDarkMode`. On the AppKit model both are paint-only and are neutralized
in `hasHeightEquivalentContent(to:)` alongside `tintHex`, so a recolor repaints without
re-measuring.

**Swatches.** AppKit reuses `SidebarWorkspaceRowColorMenu.addPaletteItems` with the
model's `colorSchemeIsDark` and `brightenInDarkMode`. SwiftUI reuses
`coloredCircleImage(color:)` from `SidebarAppearanceSupport.swift` and
`WorkspaceTabColorSettings.displayNSColor`, with the view's environment `colorScheme` and
the snapshot's `brightenInDarkMode`. Both renderers draw group swatches with
`forceBright: false`, the AppKit builder's rule. The workspace SwiftUI helper
(`tabColorSwatchColor(for:)` in `ContentView.swift`) forces bright under the left-rail
indicator style; that rule belongs to workspace rows and the group menu does not copy it.

**Chief Home group.** Color is allowed on it. `TabManager` gates pin, anchor, ungroup and
delete there; color is ungated today and stays so, since a color is harmless.

### One mutation path

`TabManager.setWorkspaceGroupColor(groupId:hex:)` becomes the normalizing choke point:

```swift
let normalized = hex.flatMap(WorkspaceTabColorSettings.normalizedHex)
workspaceGrouping.setWorkspaceGroupColor(groupId: groupId, hex: normalized)
```

Nil, empty and unparseable input all clear the color, matching `Workspace.setCustomColor`.
The socket handler keeps rejecting malformed input before it gets here, so the CLI's error
messages are unchanged. The menu, the CLI, and any later caller store `#RRGGBB` uppercase.

`WorkspaceTabColorSettings.normalizedHex` is tightened to accept only six ASCII hex
digits after the optional `#`, the rule `normalizeHexColor` already enforces. This closes
the `+12345` gap for the custom-color prompt (which validates through `addCustomColor`),
for workspaces and groups alike. It only rejects strings that were never valid colors.

### Automatic group colors

**Setting.** `sidebar.groupAutoColor`, `Bool`, default `true`, `userDefaultsKey`
`sidebarGroupAutoColor`, declared next to `groupDividers` in `SidebarCatalogSection`.
Plumbed as `groupDividers` was, through every consumer:

- `SidebarTabItemSettingsSnapshot` gains `autoColorsGroups` and `groupAutoColorPalette`
  (see Invalidation).
- `CmuxSettingsFileStore+SupportedPaths`, `CmuxSettingsJSONPathSupport`,
  `KeyboardShortcutSettingsFileStore+Template` carry the path, defaults key and default.
- The rendered toggle lives in `SidebarSection.swift` (`CmuxSettingsUI`), modeled on
  Group dividers: a `DefaultsValueModel<Bool>` state, its initializer line, its entry in
  the observed-models list, and a `SettingsCardRow` after the Group dividers row with
  `configurationReview: .json("sidebar.groupAutoColor")`, title "Automatic group colors"
  and subtitle "Color each group from its name when it has no color of its own."
- `CuratedSettingEntry+Default` adds the matching search-metadata entry. That file is
  search metadata, not the control, and it is a separate registry from the next one.
- `Sources/SettingsSearchAliases.swift` gains a localized
  `"sidebarAppearance:group-auto-color"` alias entry next to `group-dividers`; the legacy
  `SettingsSearchIndex.setting(...)` entries append aliases from this registry, so
  updating the curated copy alone leaves that consumer without synonyms.
- `Sources/SettingsSearchIndex.swift` gains a `setting(.sidebarAppearance,
  "group-auto-color", ...)` entry and the `"sidebar.groupAutoColor"` path mapping. The
  anchor-resolution test's hand-kept list gains the path too; that list does not prove
  the row renders, so the dogfood step opens the row through Settings search.
- Schema: edit `web/data/cmux.schema.json` by hand (it is the source), then run
  `scripts/generate-cmux-config-schema.py`, which regenerates only
  `CmuxConfigSchema.generated.swift` from it. The schema description key is localized.
- `skills/cmux-settings/references/all-keys.md` gains a `sidebar.groupAutoColor` row next
  to `sidebar.groupDividers`; `tests/test_cmux_settings_supported_paths.py` fails without
  it.
- The schema description also goes under `docs.configuration` in every one of the 20
  `web/messages/*.json` locale files, as `groupDividers` is today. This is the web docs'
  own catalog, separate from the nine-locale macOS catalog check.
- `docs/configuration.md` gets a `sidebar.groupAutoColor` section modeled on the
  `sidebar.groupDividers` one.

**The automatic palette.** Automatic colors draw from the built-in-named entries of the
shared palette: `WorkspaceTabColorSettings.palette()` minus `customPaletteEntries()`, in
built-in order, with duplicate hexes dropped (first occurrence wins; palette hexes are
already normalized). These are the sixteen stock colors as the user has them, including
any the user recolored or removed. Custom entries stay out on purpose: Choose Custom
Color… adds one, and a palette that grew by one would change `hash % count` and reshuffle
every automatic group the moment anyone picked a custom color. Dropping duplicate hexes is
what makes "different slot" mean "different color". Nathaniel chose "the shared palette";
narrowing it to the built-in-named entries is my refinement of that choice, made for the
reshuffle reason above, and is called out at approval.

**Invalidation.** The snapshot carries the automatic palette itself, not only the
Boolean: `groupAutoColorPalette: [String]` is built in the snapshot initializer from
`defaults`, and is empty when the setting is off so palette edits do not churn the sidebar
while automatic colors are unused. A palette edit from any window then changes the
snapshot and republishes, and the resolver never reads UserDefaults during a render.

**Resolution.** `VerticalTabsSidebar.groupColorHexByGroupId(groups:configColor:)` is the
single place the effective color is computed, and the header icon, band, guide and
multi-selection wash all read its output. It gains one input, `autoPalette: [String]`,
passed from the render-context build in `ContentView.swift` as
`settings.groupAutoColorPalette`; an empty array means automatic colors are off or have
nothing to draw from. The algorithm:

1. First pass: a group whose `customColor` normalizes (`WorkspaceTabColorSettings.
   normalizedHex`) takes the normalized value; else a config color that normalizes takes
   it. A value that does not normalize counts as absent and the group falls to the next
   rung. This is new: today any non-nil string wins and then fails `NSColor(hex:)` at
   paint time, leaving the group neutral. Neither source is validated upstream (the
   config schema's `color` is a plain string, config resolution only text-sanitizes it,
   and a restored session's `customColor` is taken as stored), so the resolver is the
   one place that can. Stored values are not rewritten; the menu still shows the raw
   manual value's state (no checkmark, Clear Color present), and Clear Color removes it.
   Record each resolved color that matches an automatic-palette entry as occupying that
   slot; both sides are normalized by then, so a lowercase config hex still counts.
2. If `autoPalette` is empty, stop. Groups without a color are omitted, as today, so the
   band and guide fall back to neutral.
3. Second pass over the remaining groups sorted by name with plain `String` `<` (Unicode
   scalar order, locale-independent, so a locale change cannot reorder colliders; not
   `localizedStandardCompare`, which the palette uses for its names), ties broken by
   `id.uuidString`:
   `start = stableHash(name) % autoPalette.count`; walk forward from `start` to the first
   slot not yet occupied; assign that slot's hex and mark it occupied. If every slot is
   taken, use `start`.

The hash is the FNV-1a/64 that `RemoteHostColorRegistry.stableHash` already implements:
deterministic across processes, unlike `Hasher`. Whether to call it there or lift it into
a small shared helper is the builder's call. The name is hashed exactly as stored, no
trimming or case folding.

Occupying slots with manual and config colors is my call: it keeps an automatic group from
wearing the same color a user hand-picked for another group. It means setting a manual
color can shift one automatic neighbor, the same class of change as adding a group, which
option 2 already accepts.

Cost: one sort of the uncolored groups and at most `autoPalette.count` probes each, per
refresh. Sidebars hold tens of groups, so this is noise next to the snapshot build.

**Precedence**, in one line: manual color, then config color, then automatic color, then
neutral. Clear Color removes the manual color and the group drops to the next rung.

**No state.** Nothing about automatic colors is persisted or cached across refreshes. A
rename recomputes the group's color on the next refresh. Turning the setting off restores
today's neutral fallback with no migration. The one difference from today is independent
of the setting: the first pass treats a malformed manual or config color as absent (see
step 1 above), so with automatic colors off such a group shows its config color, or
neutral, instead of neutral always.

### Entry points, for the shared-behavior check

| Entry point | Writes | Reads |
|---|---|---|
| Group Color menu, AppKit table | `TabManager.setWorkspaceGroupColor` | `customColorHex` on the row model |
| Group Color menu, SwiftUI stack | same | `customColorHex` on the snapshot |
| `cmux workspace-group set-color` | socket → `controlSetWorkspaceGroupColor` → same | `custom_color` in the response |
| Per-directory config `color` | nothing; a fallback | resolver first pass |
| Automatic color | nothing; a fallback | resolver second pass |

## Verification

**Tests** (Swift Testing, in `cmuxTests/`; run `scripts/sync-test-wiring` after adding
files; execute locally with `scripts/test-unit.sh test -only-testing:<target>/<suite>`,
since the script adds the `test` action only when given no arguments and the fork has no
e2e lane):

- Resolver: manual beats config beats automatic; an empty automatic palette yields no
  entry; the same input yields the same output twice; two names hashing to one slot get
  adjacent slots in name order; a manual color matching a palette entry occupies that
  slot, and a lowercase config hex does too; a full palette falls back to the hashed start;
  a malformed manual color (`"nope"`) or config color (`"#12"`) counts as absent, so the
  group takes the next rung, and a lowercase one resolves uppercased; with the automatic
  palette empty (setting off), a manual `"nope"` beside a valid config color resolves to
  the config color; names that differ
  only in case, non-ASCII names and a several-hundred-character name resolve
  deterministically.
- Automatic palette: custom entries are excluded, so adding one leaves every automatic
  color unchanged; duplicate hexes collapse to one slot; a removed built-in shrinks it.
- Invalidation: a palette-only UserDefaults change produces a different
  `SidebarTabItemSettingsSnapshot` with automatic colors on, and an equal one with them
  off.
- Normalization: `setWorkspaceGroupColor(hex: "c0392b")` stores `#C0392B`; `""`,
  `"nope"` and `"+12345"` clear; `normalizedHex("+12345")` and `normalizedHex("-12345")`
  are nil; the socket handler's stored value for `--hex c0392b` equals the menu's.
- Plumbing: both snapshot builders carry `customColorHex` from `group.customColor` and
  leave it nil for a config-only color; `hasHeightEquivalentContent` ignores it (extend
  `SidebarGroupHeaderDividerPlumbingTests`).
- AppKit menu: `makeHeaderMenu()` contains Group Color; Clear Color appears only with a
  manual color; the matching palette item is checked (extend `SidebarAppKitRowCellTests`
  if the cell exposes the menu, else a builder on the model).
- Target group: with two header anchors multi-selected, the set action built for one
  header recolors only that group and leaves `selectedTabIds` unchanged.
- Settings file: a `SidebarGroupAutoColorSettingsTests` mirroring
  `SidebarGroupDividersSettingsTests` (off, on, absent-stays-on, path and schema), plus
  `tests/test_cmux_settings_supported_paths.py` passing with the all-keys row.

**Localization.** `./scripts/localize-changes`, fill the packet, rerun, then
`python3 scripts/localization_catalog.py check`. Report the audit in the PR.

**Dogfood** in a tagged build (`CMUX_TAG=group-color scripts/cmux-debug-cli.sh`), never the
running cmux:

- Right-click a group header in both renderers: menu present, swatch sets the color, header
  icon, band and guide change together, checkmark lands, Clear Color appears and clears.
- Set a color from the CLI, then open the menu: the same swatch is checked.
- With no manual colors, several groups show distinct automatic colors; relaunch and they
  match; rename one and it changes; add a custom color through a workspace menu and no
  automatic group changes; turn the setting off and all go neutral.
- Search Settings for "automatic group colors": the row is found and its toggle works.
- Multi-select two group headers and recolor one: only it changes, the selection stays.
- Screenshots with `cmux shot` from the tagged CLI for the PR.

## Docs

- `docs/workspace-groups.md`: add **Group Color** to the header context menu list and a
  short "Group colors" paragraph covering the menu, the CLI, the config color and the
  automatic color, with the precedence line.
- `docs/configuration.md`: the `sidebar.groupAutoColor` section.
- `docs/customizing-appearance.md`: one line where it mentions group `set-color`.
- The `WorkspaceGroup.customColor` doc comment in `CmuxWorkspaces` (it promises
  "cwd-config color, then no tint") gains the app-level automatic fallback, worded so the
  package does not claim to compute it.
- `WorkspaceGroupCoordinator.setWorkspaceGroupColor` gains a doc comment saying it stores
  the value as given and that app callers go through `TabManager.setWorkspaceGroupColor`,
  which normalizes. The package cannot see `WorkspaceTabColorSettings`, so normalization
  stays in the app; the comment is what keeps the next package-level caller honest.

## Changelog

- Added: a Group Color submenu on the workspace group header's context menu.
- Added: automatic group colors from a stable hash of the group name, with
  `sidebar.groupAutoColor` to turn them off.

## Left to the builder

- Whether `WorkspaceCustomColorPrompt.run` takes a title parameter or gains a group
  sibling.
- Whether to lift `stableHash` out of `RemoteHostColorRegistry` or call it in place.
- Whether the SwiftUI swatch drawing is a small shared helper or inlined.
- Test file names and the exact split across beads.
