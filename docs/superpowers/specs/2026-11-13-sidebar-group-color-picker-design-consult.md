# Design Deliberation: Sidebar workspace groups: Group Color menu and automatic colors

**Source:** docs/superpowers/specs/2026-11-13-sidebar-group-color-picker-design.md
**Date:** 2026-11-13
**Rounds:** 3
**Mode:** converge
**Personas:** devils-advocate, pragmatist, simplifier, user, astra, sol
**Final verdict:** Revision Degraded (round 3 verdicts fell below round 2; the cause is one regression the round 2 revision introduced, plus two omitted consumers. All three have exact fixes under Recommended Actions.)

## Round 1: Initial Critiques
### Devil's Advocate (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.85

The proposal has a solid foundation but requires addressing several points to ensure clarity, consistency, and completeness.

- Clarify the user flow for setting and clearing group colors to ensure consistency across different entry points (menu, CLI, config).
- Ensure that the automatic color resolution algorithm handles edge cases, such as groups with identical names or very large numbers of groups, without performance issues.
- Verify that the localization process includes all necessary strings and handles edge cases, such as groups with names that may require special characters or formatting.
- Confirm that the automatic color setting does not introduce any unintended side effects, such as changing the color of groups with manual colors.
- Ensure that the documentation is comprehensive and covers all aspects of the new feature, including potential pitfalls and troubleshooting steps.
- Consider adding unit tests to cover additional scenarios, such as groups with very long names or groups that are renamed multiple times.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 0.95

This is a well-researched and highly detailed implementation plan that addresses key complexities like dual UI toolkits and state management, providing a clear and feasible path to execution.

- The plan's greatest strength is its thoroughness, addressing UI, core logic, CLI, configuration, testing, and documentation in one cohesive design.
- It correctly identifies the main implementation risk—maintaining consistency between AppKit and SwiftUI renderers—and mitigates it by maximizing shared code and models.
- The proposed automatic color algorithm, including stable hashing and linear probing, is a practical and performant solution for providing distinct, predictable colors without persisting state.
- Centralizing the color normalization logic in `TabManager` is a robust choice that ensures consistency and prevents future bugs from disparate entry points.
- The detailed verification plan, including specific unit tests and manual dogfooding steps, provides high confidence that the feature will be delivered with quality.

### Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.85

The proposal is generally solid but can be streamlined for better simplicity and clarity.

- The addition of automatic colors introduces complexity that may not be necessary. Consider if manual color setting alone can meet user needs.
- The design could benefit from a simpler color selection mechanism, possibly reducing the number of steps required to choose a color.
- Evaluate if the current level of detail in the design documentation is necessary or if it can be condensed without losing critical information.
- Consider simplifying the automatic color collision resolution algorithm to reduce complexity.
- The addition of new strings for every locale may not be necessary if the current localization framework can handle the new feature without additional keys.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.9

The UI for setting group colors is a minor convenience, but the proposed automatic coloring introduces unnecessary visual noise and potential for frustrating instability, requiring users to explicitly disable it.

- A UI picker for group colors is a marginal improvement at best; power users already use the CLI, and it's not a critical feature for most daily workflows.
- Automatically assigning colors by default creates visual noise and forces users who prefer a neutral interface or specific color schemes to actively seek out and disable the feature.
- The admitted instability of automatic colors, where "adding a colliding group can shift one neighbor's color," will undermine visual consistency and cause frustration when the sidebar's appearance changes unexpectedly.
- This feature addresses a problem ('my groups aren't colored by default') that many users didn't actually have, adding complexity without a clear, compelling benefit for the average user.
- The 'stable hash then probe' collision rule is a convoluted solution that still results in an unstable visual state, making the automatic colors unreliable for quick visual identification.

### Astra (astra)
**Verdict:** reject | **Confidence:** 0.97

The shared menu approach fits the repository, but the design misstates settings and schema plumbing and leaves gaps in palette invalidation, collision guarantees, normalization, and existing multi-selection behavior.

- The settings plan omits the actual toggle. CuratedSettingEntry supplies search metadata, not rendered controls (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Navigation/CuratedSettingEntry.swift:4-35). The existing Group dividers control separately declares, initializes, and observes a DefaultsValueModel and renders its toggle in Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/SidebarSection.swift:39-40,74-75,94-120,546-554. Add the corresponding automatic-color control and anchor there. Merely adding its path to SettingsRowAnchorResolutionTests can falsely establish reachability because that test uses a hand-maintained list rather than inspecting rendered rows (Packages/macOS/CmuxSettingsUI/Tests/CmuxSettingsUITests/SettingsRowAnchorResolutionTests.swift:14-37). The promised app-side search-index test also needs its production mapping in Sources/SettingsSearchIndex.swift:345-348.
- The schema generation direction is incorrect. `scripts/generate-cmux-config-schema.py` does not regenerate web/data/cmux.schema.json: that JSON is its input, and the only generated output is CmuxConfigSchema.generated.swift (`scripts/generate-cmux-config-schema.py:9-21,36-38,75-83`). Explicitly require editing the authoritative JSON schema first, then regenerating the embedded Swift schema. Following the stated generator-only step would leave sidebar.groupAutoColor undeclared and rejected by schema-backed validation.
- The new palette dependency has no specified invalidation path. SidebarTabItemSettingsSnapshot contains appearance settings but no palette value or revision (Sources/SidebarTabItemSettingsSnapshot.swift:8-49), and its store suppresses publication when the reconstructed snapshot compares equal (Sources/ContentView.swift:11381-11388). Palette mutations write UserDefaults independently (Sources/WorkspaceTabColorSettings.swift:88-119). Adding only autoColorsGroups and reading palette() during rendering therefore does not ensure automatic colors refresh after a palette-only change—for example, a custom entry added in another window. Include the effective palette or a revision in the observed snapshot, and verify palette-only updates without relying on an unrelated sidebar refresh.
- Probing distinct palette slots does not guarantee distinct colors. palette() preserves differently named entries with identical hex values, and palette normalization does not deduplicate values (Sources/WorkspaceTabColorSettings.swift:43-56,240-247). Two colliding groups can therefore receive different slots containing the same color. Define whether automatic assignment deduplicates canonical hexes or permits this outcome, and add coverage. Also qualify the goals: an explicitly empty palette is supported (Sources/WorkspaceTabColorSettings.swift:181-188,201-203), exhaustion necessarily permits repeats, and restart stability depends on the palette and reserved manual/config colors remaining unchanged—not merely the group-name set.
- The two normalizers do not actually enforce the same canonical-color contract. WorkspaceTabColorSettings.normalizedHex checks length and uses UInt64 parsing (Sources/WorkspaceTabColorSettings.swift:128-134), which accepts a leading plus sign; '+12345' therefore becomes '#+12345', not six hexadecimal digits. The socket normalizer explicitly requires six ASCII hexadecimal characters and rejects that input (Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/WorkspaceGroup/ControlCommandCoordinator+WorkspaceGroup.swift:541-546). The shared custom-color prompt uses the former parser through addCustomColor (Sources/WorkspaceCustomColorPrompt.swift:32-37; Sources/WorkspaceTabColorSettings.swift:110-118). Specify how to align validation before promising identical canonical storage, and include signed-input cases in the parity tests.
- The statement that group headers have no multi-select is factually incorrect. Command- or Shift-clicking a header invokes anchorCmdClickSelection (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:694-701), which retains other selected anchors and toggles the clicked anchor (Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/Sidebar/SidebarSelectionKindPolicy.swift:29-47); an existing test explicitly expects two selected anchors (Packages/macOS/CmuxFoundation/Tests/CmuxFoundationTests/SidebarSelectionKindPolicyTests.swift:25-38). The proposed single-group menu behavior is still viable, but describe the non-goal as bulk color editing, preserve existing selection behavior, and verify that coloring one of several selected headers changes only the context-clicked group.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.99

The design misses required settings and rendering consumers, contains several false code claims, and specifies guarantees its algorithm cannot meet.

- The proposed Settings row is incomplete: CuratedSettingEntry is search metadata, not rendered UI (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Navigation/CuratedSettingEntry.swift:4-15,24-34). The actual toggle requires state, initialization, observation, and a SettingsCardRow in SidebarSection (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/SidebarSection.swift:10-78,94-119,545-555), none of which the design names.
- Palette changes will not reliably recompute automatic colors. WorkspaceTabColorSettings.palette() reads a separate UserDefaults-backed palette (Sources/WorkspaceTabColorSettings.swift:14-56,200-203), while SidebarTabItemSettingsStore publishes only when SidebarTabItemSettingsSnapshot changes (Sources/ContentView.swift:11334-11342,11382-11389). The design adds only the auto-color Boolean to that snapshot, so changing workspaceColors.colors alone leaves automatic assignments stale. Include the palette hexes or an equivalent revision in the observed snapshot.
- The new settings path must be added to `skills/cmux-settings/references/all-keys.md`. The installed-settings helper derives its paths from that file, and its parity test explicitly fails when a schema path is absent (`tests/test_cmux_settings_supported_paths.py:100-117`). This required consumer is omitted.
- The schema-generation claim is factually reversed. `scripts/generate-cmux-config-schema.py` reads web/data/cmux.schema.json and writes only CmuxConfigSchema.generated.swift (`scripts/generate-cmux-config-schema.py:10-20,36-63,75-83`); it does not generate the web schema. The design must require editing web/data/cmux.schema.json first, then regenerating the embedded copy.
- The automatic-color guarantees conflict with the algorithm. The palette can be empty because a stored empty dictionary is accepted, and duplicate hex values are not deduplicated (Sources/WorkspaceTabColorSettings.swift:200-203,240-247). The shipped palette is also finite (Sources/WorkspaceTabColorSettings.swift:20-36). Therefore neither “every group has a color” nor unconditional distinct colors for colliders is guaranteed; define behavior in terms of available unique palette colors.
- The non-goal claiming group headers have no multi-select is false. Header snapshots explicitly derive isMultiSelected from the anchor selection (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:75-77), and command/shift clicks mutate multi-selection (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:693-704). Specify and test that Group Color intentionally affects only the clicked group despite an active multi-selection.
- SwiftUI swatch rendering lacks a required snapshot input. The existing workspace helper uses settings.brightenInDarkMode and sometimes forceBright (Sources/ContentView.swift:17184-17190), while the AppKit palette builder always uses forceBright false (Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowColorMenu.swift:25-31). The design adds brightenInDarkMode only to the AppKit model; it must carry the value through the SwiftUI group snapshot/view and explicitly resolve the forceBright parity decision.
- The prescribed focused-test command is not executable as written. scripts/test-unit.sh adds the test action only when it receives no arguments (scripts/test-unit.sh:10-13); passing -only-testing alone therefore defaults to a build action. The plan should use scripts/test-unit.sh test -only-testing:<target/test> (scripts/test-unit.sh:38-44).
- The Chief Home claim is inaccurate: ungroup is also explicitly gated, in addition to pin, anchor, and delete (Sources/TabManager.swift:2420-2428,2432-2439,2460-2481). Color itself is currently ungated, so the intended conclusion remains valid, but the design should correct its factual rationale.


## Design Lead Revision (after Round 1)
### Rationale
1. Settings toggle (astra, sol): accepted, verified. `CuratedSettingEntry` is search metadata; the Group dividers toggle is a `DefaultsValueModel` plus `SettingsCardRow` in `SidebarSection.swift` (lines 40, 75, 116, 547-551). The design now names the SidebarSection control, the `SettingsSearchIndex.swift` entry and path mapping, and adds a dogfood step through Settings search, since the anchor test's list is hand-kept.
2. Schema direction (astra, sol): accepted, verified. `generate-cmux-config-schema.py` reads `web/data/cmux.schema.json` and writes only `CmuxConfigSchema.generated.swift`. The design now says to edit the JSON by hand first, then regenerate.
3. `all-keys.md` consumer (sol): accepted, verified (`sidebar.groupDividers` row at line 149). Added it, with the supported-paths parity test in Verification.
4. Palette invalidation (astra, sol): accepted, verified. `SidebarTabItemSettingsStore.refreshSnapshot` returns early when the rebuilt snapshot is equal (ContentView.swift ~11382). The snapshot now carries `groupAutoColorPalette: [String]`, empty when the setting is off, and the resolver takes that instead of reading UserDefaults during render. Added a test.
5. Automatic palette growth (design lead's own finding, no reviewer raised it): `palette()` appends custom entries, and Choose Custom Color… adds one. `hash % count` would then reshuffle every automatic group whenever anyone picked a custom color. The automatic palette is now the built-in-named entries of the shared palette, in built-in order, with duplicate hexes dropped. The menu still lists the full palette. This changes HOW the fixed "hash into the shared palette" decision works, not whether it holds; Nathaniel should confirm it.
6. Duplicate hexes, empty palette, exhaustion (astra, sol): accepted. Deduping hexes makes a distinct slot a distinct color. The Goals now promise distinct colors only while unused colors remain, coloring only with a non-empty automatic palette, and restart stability conditioned on names, palette, and manual/config colors.
7. Normalizer mismatch (astra): accepted, verified. `UInt64("+12345", radix: 16)` returns 74565, so `normalizedHex("+12345")` yields `#+12345`. `normalizedHex` is tightened to six ASCII hex digits, matching the socket rule. Signed-input cases are added to the tests.
8. Multi-select non-goal (astra, sol): accepted, verified (`anchorCmdClickSelection` at VerticalTabsSidebar+WorkspaceGroups.swift:695). The non-goal is now "bulk color editing", with a Target group rule (act on the clicked groupId, leave the selection alone) and a test and a dogfood step for it.
9. SwiftUI swatch inputs and forceBright (sol): accepted, verified. `tabColorSwatchColor` uses `forceBright: activeTabIndicatorStyle == .leftRail`; the AppKit builder uses false. `brightenInDarkMode` is now on all three header models, and both renderers use `forceBright: false`.
10. test-unit invocation (sol): accepted, verified. The script defaults to `test` only with zero args. The design now says `scripts/test-unit.sh test -only-testing:...`.
11. Chief Home rationale (sol): accepted, verified. Ungroup is gated too (TabManager.swift ~2423). Corrected; color stays ungated.
12. Edge cases and performance (devils-advocate): identical names already have a `uuidString` tiebreak. Added a cost line (one sort and at most palette-count probes per refresh). Rename is covered by the dogfood step. Localization of group names is not affected because the names are user data, not strings. The other points were generic and needed no change.
13. Drop automatic colors / simplify probing (simplifier, user): rejected. Automatic colors, default on, and name-order probing are Nathaniel's decisions and stay fixed. The user persona's instability concern is real but bounded: the revision removes the largest instability source (custom-palette growth) and states the remaining conditions in the Goals. The setting is the escape hatch.
14. Fewer locale keys (simplifier): rejected. The catalog check requires nine locales for every new key. Only two new menu/alert keys plus the settings strings are added, and existing strings are reused wherever they fit.

### Key Changes
- Settings plumbing names the real toggle (`SidebarSection.swift`), the `SettingsSearchIndex` entry and mapping, `all-keys.md`, and the correct schema direction.
- Automatic palette = built-in-named entries of the shared palette, deduplicated by hex; custom entries are excluded so Choose Custom Color... cannot reshuffle automatic groups.
- `SidebarTabItemSettingsSnapshot` carries `groupAutoColorPalette` so palette edits republish.
- `normalizedHex` is tightened to ASCII hex digits only (closes `+12345`).
- The multi-select non-goal is corrected to "bulk color editing", with a target-group rule.
- `brightenInDarkMode` is added to all three header models; `forceBright: false` in both renderers.
- Corrected the `test-unit.sh test -only-testing` invocation and the Chief Home gate facts.

## Round 2: Deliberation
### Devil's Advocate (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.85
Changed from Round 1: needs_work -> needs_work

The proposal has been revised to address several concerns, but further clarification and testing are needed to ensure its completeness and robustness.

- The user flow for setting and clearing group colors appears more consistent across different entry points (menu, CLI, config) after the revisions.
- The automatic color resolution algorithm seems to handle edge cases better, but further testing is needed to confirm its performance with very large numbers of groups.
- The localization process now includes all necessary strings, but edge cases with special characters or formatting in group names should be tested.
- The automatic color setting does not appear to introduce unintended side effects, but continuous monitoring is recommended.
- The documentation is more comprehensive, but additional scenarios (e.g., groups with very long names) should be covered in unit tests.
- The revisions have addressed many of the initial concerns, but further testing and clarification are needed to ensure the feature's robustness and completeness.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 0.98
Changed from Round 1: approve -> approve

The revised plan is exceptionally robust, having proactively identified and fixed a critical user experience flaw in the automatic coloring logic, thereby substantially de-risking the project.

- The revised automatic coloring algorithm, which decouples the automatic palette from user-added custom colors, is a crucial fix that prevents a major UX pitfall and ensures the feature's stability.
- Plumbing the automatic palette through the state snapshot mechanism is a much more robust implementation pattern that correctly respects architectural boundaries and prevents a class of potential state-related bugs.
- The plan has been tightened across the board, from closing normalization loopholes to adding more specific tests and dogfooding steps, which increases the likelihood of a smooth and predictable implementation.
- The detailed breakdown of required changes across the entire system—including settings UI, schema, CLI, documentation, and localization—leaves very little to interpretation, providing a clear blueprint for the executing engineer.
- The design lead's rationale for rejecting simplifications while providing an escape hatch (`sidebar.groupAutoColor`) demonstrates a pragmatic balance between meeting stakeholder requirements and addressing user concerns.

### Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.85
Changed from Round 1: needs_work -> needs_work

The revised document shows improvements but still has room for simplification and clarity.

- The addition of automatic colors remains a point of concern for unnecessary complexity.
- The design documentation could still be condensed to improve readability and focus on critical information.
- The automatic color collision resolution algorithm could be further simplified to reduce complexity.
- The need for new strings for every locale should be re-evaluated to ensure it is necessary.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.8
Changed from Round 1: needs_work -> needs_work

While the manual color picker is a minor convenience, the decision to keep automatic group coloring enabled by default with acknowledged instability still creates unnecessary friction for users.

- The core problem of automatic colors being 'on' by default, forcing users to actively seek out and disable a feature they likely didn't ask for, remains unaddressed.
- The admitted 'bounded' instability, where adding a group can shift a neighbor's color, undermines the utility of color for reliable visual identification.
- Providing an 'escape hatch' setting to turn off unwanted default behavior is a workaround for user friction, not a solution that enhances the user experience.
- Users who prefer a stable or neutral interface are still burdened with finding and managing a setting to achieve their desired state.
- The technical complexity of the hash and probe algorithm does not translate to a stable or predictable visual outcome from a user's perspective.

### Astra (astra)
**Verdict:** approve | **Confidence:** 0.94
Changed from Round 1: reject -> approve

The revision adequately addresses my prior objections, and tracing the affected renderers, settings pipeline, mutation path, and persistence revealed no additional blocking defect.

- The settings correction addresses the missing rendered control, not just search metadata: the existing pattern requires state, initialization, observation, and a SettingsCardRow (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/SidebarSection.swift:40-75,94-120,546-554). The revision also covers the separate app search entry and path mapping (Sources/SettingsSearchIndex.swift:166-166,348-348) and correctly acknowledges that the anchor test uses a hand-maintained list (Packages/macOS/CmuxSettingsUI/Tests/CmuxSettingsUITests/SettingsRowAnchorResolutionTests.swift:14-37).
- The schema and supported-path corrections are sufficient. The generator reads web/data/cmux.schema.json and writes the embedded Swift schema, exactly as the revised instructions now state (`scripts/generate-cmux-config-schema.py:9-21,75-83`). Updating all-keys.md also covers the installed helper's schema-parity consumer (`tests/test_cmux_settings_supported_paths.py:102-118`). Mirroring the existing settings suite exercises the real importer and an isolated defaults suite rather than merely validating the schema (cmuxTests/SidebarGroupDividersSettingsTests.swift:24-75,78-101).
- Carrying the effective automatic palette in the settings snapshot resolves the previously missing invalidation dependency: publication currently stops when the rebuilt snapshot is equal (Sources/ContentView.swift:11381-11388). The built-in-name filtering matches the existing palette partition, and deduplication addresses the fact that different names can retain identical hex values (Sources/WorkspaceTabColorSettings.swift:43-62,240-247). Excluding custom entries also correctly avoids palette-size changes from the shared prompt's addCustomColor path (Sources/WorkspaceTabColorSettings.swift:110-119).
- The normalization revision closes the identified validation gap without requiring a socket contract change. The current app normalizer uses UInt64 parsing (Sources/WorkspaceTabColorSettings.swift:128-144), while the socket validates before forwarding and returns its normalized value (Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Coordinator/WorkspaceGroup/ControlCommandCoordinator+WorkspaceGroup.swift:376-409). The forwarding adapter already reaches TabManager.setWorkspaceGroupColor (Sources/TerminalController+ControlWorkspaceGroupContext.swift:354-362), so the proposed app-side normalization preserves the shared mutation route.
- The revised single-group targeting and snapshot fields fit both renderers' existing shared action construction (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:209-216,425-438,493-513), while preserving the actual multi-anchor selection behavior (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:694-711). Restart stability is also supported by existing persistence: group IDs, names, and manual colors are saved and restored unchanged, including IDs needed for duplicate-name tie-breaking (Sources/TabManager.swift:7055-7066,7307-7319,7339-7347). The automatic resolver can therefore remain presentation-only without adding persisted state.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.98
Changed from Round 1: reject -> reject

The revision resolves the prior findings, but invalid persisted/config colors still defeat the automatic-color guarantee and one settings-search consumer remains omitted.

- The prior concerns were adequately addressed: the rendered toggle pattern is in Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/SidebarSection.swift:40-116,547-551; snapshot publication is equality-gated in Sources/ContentView.swift:11382-11389; and the schema source precedes its generated copy in web/data/cmux.schema.json:1798-1802 and Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/ConfigValidation/CmuxConfigSchema.generated.swift:1808-1812.
- The claim that every group receives an automatic color remains false for malformed manual or config colors. The config schema accepts any string without a hex pattern (web/data/cmux.schema.json:647-650), config resolution stores that string without color validation (Sources/CmuxConfig.swift:3274-3280), and restored groups likewise accept persisted customColor verbatim (Sources/TabManager.swift:7307-7318,7339-7346). The resolver currently treats every non-nil value as resolved (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:17-26), while rendering can reject it as a color (Sources/SidebarWorkspaceGroupHeaderView.swift:131-136). The design must either validate these inputs and treat invalid values as absent or narrow its guarantee and add malformed-config/persistence tests.
- The settings-search plumbing still omits Sources/SettingsSearchAliases.swift. Legacy SettingsSearchIndex entries automatically append aliases from that registry (Sources/SettingsSearchAliases.swift:261-274), and groupDividers has a corresponding localized alias entry there (Sources/SettingsSearchAliases.swift:170-177). CuratedSettingEntry is a separate copied registry, as documented in Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Navigation/CuratedSettingEntry+Default.swift:4-17; updating it does not update the legacy alias consumer.
- The changed precedence also makes the public WorkspaceGroup documentation stale: it currently promises custom color, then cwd config, then no tint in Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Values/WorkspaceGroup.swift:26-30. The design should require updating that contract to acknowledge the app-level automatic fallback.
- Opinion, supported by repository precedent: “sorted by name” should specify a locale-independent comparator. WorkspaceTabColorSettings uses localizedStandardCompare for palette names (Sources/WorkspaceTabColorSettings.swift:50-55); following that precedent could reorder colliding groups after a locale change and violate the stated restart guarantee.


## Design Lead Revision (after Round 2)
### Rationale
1. Malformed manual/config colors block the automatic fallback (sol): accepted, verified. The schema's `color` is a plain string (web/data/cmux.schema.json ~647), `CmuxConfig` only applies `sanitizeConfigText` (CmuxConfig.swift ~3278), a restored `customColor` is taken as stored (TabManager.swift ~7317), the resolver accepts any non-nil value, and the SwiftUI icon falls back to `.secondary` when `NSColor(hex:)` fails. The resolver's first pass now normalizes each candidate and treats one that does not normalize as absent, so the group falls to the next rung. Stored values are not rewritten. Added malformed and lowercase cases to the resolver tests.
2. `SettingsSearchAliases.swift` omitted (sol): accepted, verified. `SettingsSearchIndex.setting(...)` appends `SettingsSearchAliasIndex.aliases(...)`, and `group-dividers` has its own alias entry there (~line 176). Added a `group-auto-color` alias entry, kept separate from the `CuratedSettingEntry` copy.
3. Stale `WorkspaceGroup.customColor` contract (sol): accepted, verified ("falls back to the cwd-config color ..., then to no tint"). Added to Docs, worded so the package does not claim to compute the automatic color.
4. Locale-independent name sort (sol): accepted. The second pass sorts with plain `String` `<`, not `localizedStandardCompare`, so a locale change cannot reorder colliders.
5. Long, odd and case-variant names (devils-advocate): accepted as cheap coverage. Resolver tests now include names that differ only in case, non-ASCII names and a very long name. On performance, the cost line from round 1 stands: one sort plus bounded probes, per refresh, over tens of groups. "Continuous monitoring" is not a design change.
6. Astra approved and raised nothing new; no change.
7. Drop automatic colors / default off / simpler probing (user, simplifier): unchanged and fixed by Nathaniel. Round 1 removed the largest instability source (custom-palette growth), and round 2 removes another (malformed colors). The remaining shift (a colliding group added or renamed moves one neighbor) is the trade-off Nathaniel accepted with option 2. The fewer-locale-keys request is not possible: the catalog check requires all nine locales for each new key.
8. Condense the document (simplifier): partly declined. The detail it carries is consumer lists that reviewers showed were missing; cutting them would bring those gaps back.

### Key Changes
- The resolver's first pass normalizes manual and config colors and treats a malformed value as absent.
- A `SettingsSearchAliases.swift` alias entry is added.
- The `WorkspaceGroup.customColor` doc comment is updated.
- The second pass sorts names with plain `String` `<` (locale-independent).
- Resolver tests gain malformed, lowercase, case-variant, non-ASCII and long-name cases.

## Round 3: Deliberation
### Devil's Advocate (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.85
Changed from Round 2: needs_work -> needs_work

The proposal has been revised to address several concerns, but further clarification and testing are needed to ensure its completeness and robustness.

- The user flow for setting and clearing group colors appears more consistent across different entry points (menu, CLI, config) after the revisions.
- The automatic color resolution algorithm seems to handle edge cases better, but further testing is needed to confirm its performance with very large numbers of groups.
- The localization process now includes all necessary strings, but edge cases with special characters or formatting in group names should be tested.
- The automatic color setting does not appear to introduce unintended side effects, but continuous monitoring is recommended.
- The documentation is more comprehensive, but additional scenarios (e.g., groups with very long names) should be covered in unit tests.
- The revisions have addressed many of the initial concerns, but further testing and clarification are needed to ensure the feature's robustness and completeness.

### Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 0.95
Changed from Round 2: approve -> approve

This revised plan is exceptionally thorough, addressing prior feedback by mitigating key risks and providing a concrete, low-risk implementation path.

- The plan's exhaustive checklist of every affected file, setting, schema, and API demonstrates a rigorous and practical approach that significantly de-risks the implementation phase.
- The automatic coloring algorithm has been made more robust by correctly handling malformed config/manual colors and decoupling the automatic palette from user-made custom colors, preventing unstable behavior.
- The design respects and leverages existing architectural patterns, such as the snapshot-based invalidation model and shared action bundles, which reduces complexity and avoids introducing new categories of bugs.
- Proactively identifying and designing a fix for the inconsistent hex normalization between different code paths is a pragmatic move that improves codebase health beyond the scope of the immediate feature.
- The detailed verification plan, combining specific unit test cases with concrete dogfooding scenarios, provides high confidence that the feature will be shipped with quality and will work as expected in the real world.

### Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.85
Changed from Round 2: needs_work -> needs_work

The revised document shows improvements but still has room for simplification and clarity.

- The addition of automatic colors remains a point of concern for unnecessary complexity.
- The design documentation could still be condensed to improve readability and focus on critical information.
- The automatic color collision resolution algorithm could be further simplified to reduce complexity.
- The need for new strings for every locale should be re-evaluated to ensure it is necessary.
- The Design Lead's rationale for each point is acknowledged, but further simplification and clarity are still needed.

### User (user)
**Verdict:** needs_work | **Confidence:** 0.9
Changed from Round 2: needs_work -> needs_work

The design still prioritizes an opinionated default for automatic coloring that introduces visual instability and requires user intervention to disable, despite explicit user feedback.

- The primary user objection regarding automatic colors being enabled by default and causing visual shifts when new groups are added or renamed remains unaddressed.
- Users who rely on color for stable visual identification will find the "colliding group can shift one neighbor's color" behavior counterproductive and unreliable.
- Requiring users to actively disable an auto-coloring feature they didn't ask for is friction, not a beneficial default experience.
- The design explicitly states that the user's request to "Drop automatic colors / default off" was "unchanged," confirming the burden on the user.
- While technical clarity is improved, the user-facing impact of unpredictable color changes for automatically colored groups persists.

### Astra (astra)
**Verdict:** needs_work | **Confidence:** 0.95
Changed from Round 2: approve -> needs_work

The prior concerns are addressed, but the new malformed-color fallback conflicts with the promise that disabling automatic colors restores today's behavior exactly.

- Resolve the off-state compatibility contract. Today, a restored manual color of "nope" suppresses a valid config color: restoration preserves the raw value (Sources/TabManager.swift:7339-7345), the resolver selects the first non-nil value (Sources/VerticalTabsSidebar+WorkspaceGroups.swift:17-27), and the header icon falls back to neutral when parsing fails (Sources/SidebarWorkspaceGroupHeaderView.swift:131-135). The revised first pass instead selects the valid config color before checking whether autoPalette is empty. Therefore, switching automatic colors off will not restore the old appearance for this case, contrary to Goals and No state. Keep the proposed normalization if intended, but explicitly exempt malformed-color handling from the compatibility promise and add an off-state regression test; otherwise specify how the old precedence is preserved when disabled.
- The malformed-input rationale is otherwise supported by the repository: the config schema permits an arbitrary string (web/data/cmux.schema.json:647-649), config resolution only sanitizes text (Sources/CmuxConfig.swift:3274-3281), and session restoration does not validate the manual color (Sources/TabManager.swift:7307-7318,7339-7345). Normalizing candidates in the shared resolver addresses both renderers without rewriting stored state.
- The additional consumer corrections adequately address the earlier omissions. The legacy search helper actually appends SettingsSearchAliasIndex aliases (Sources/SettingsSearchAliases.swift:261-274), with group-dividers registered separately at line 176, so the new alias entry is appropriate. The package color contract does currently promise config followed by no tint (Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Values/WorkspaceGroup.swift:27-30), so updating it to describe an app-owned automatic fallback is also necessary. I found no additional missing interface counterpart in these revisions.

### Sol (sol)
**Verdict:** reject | **Confidence:** 0.98
Changed from Round 2: reject -> reject

The prior findings are addressed, but the design still misses the public coordinator mutation path and the web localization consumer of the schema.

- The revision adequately addresses the prior resolver, search-alias, documentation, and locale-independent sorting concerns; the relevant existing seams are Sources/VerticalTabsSidebar+WorkspaceGroups.swift:17-26, Sources/SettingsSearchAliases.swift:261-274, and Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Values/WorkspaceGroup.swift:26-30.
- The claimed single normalization path is not actually single: TabManager delegates to the public WorkspaceGroupCoordinator setter (Sources/TabManager.swift:2470-2472), while that public package API still stores arbitrary strings unchanged (Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Coordinators/WorkspaceGroupCoordinator.swift:530-535). A direct package caller can therefore bypass normalization. Move canonicalization to a shared/package layer or explicitly change and constrain this public contract.
- The schema descriptionKey has a separate web localization consumer that the design does not enumerate. The schema establishes the key pattern at web/data/cmux.schema.json:1798-1802, and the configuration page resolves every descriptionKey through next-intl at web/app/[locale]/(landing)/docs/configuration/page.tsx:223-225. Existing sidebar schema descriptions live under web/messages/en.json:3516-3519 across every locale declared in web/i18n/routing.ts:3-24, with all-locale coverage precedent in web/tests/docs-search-index.test.ts:98-113. The work must add the new key to every web/messages locale and corresponding coverage; the nine-locale macOS catalog workflow does not update this other side.


## Convergence Trace
| Round | devils-advocate | pragmatist | simplifier | user | astra | sol | Consensus? |
|---|---|---|---|---|---|---|---|
| 1 | needs_work | approve | needs_work | needs_work | reject | reject | No (1 approve, 2 reject) |
| 2 | needs_work | approve | needs_work | needs_work | approve | reject | No (2 approve, 1 reject) |
| 3 | needs_work | approve | needs_work | needs_work | needs_work | reject | No, degraded (1 approve, 1 reject); stopped |

## Final Synthesis

### Issues That Converged
- **Settings plumbing was incomplete** (astra and sol, round 1). The rendered toggle in `SidebarSection.swift`, the `SettingsSearchIndex` entry and mapping, `SettingsSearchAliases.swift`, `all-keys.md`, and the schema direction (the hand-edited `web/data/cmux.schema.json` generates the Swift copy, not the reverse) were missing or reversed. Each has been verified and fixed.
- **Palette invalidation** (astra and sol). The settings store republishes only when the snapshot changes, so the automatic palette now rides in `SidebarTabItemSettingsSnapshot`.
- **The guarantees overpromised** (astra and sol). With a finite palette, duplicate hexes, a possibly empty palette, and stability that depends on more than names, the Goals were restated to match what the algorithm can deliver.
- **The multi-select fact was wrong** (astra and sol). Headers do multi-select, so the non-goal became bulk editing, with a rule that only the clicked group changes.

### Issues That Were Resolved
- Normalizer mismatch: `UInt64(radix:)` accepts a leading sign, so `normalizedHex` is tightened.
- SwiftUI swatches were missing `brightenInDarkMode`, and the `forceBright` choice was unstated. Both renderers now use `forceBright: false`.
- The `test-unit.sh` invocation was wrong, and the Chief Home gate facts were wrong.
- Malformed manual or config colors blocked the automatic fallback. They are now normalized in the resolver.
- The `WorkspaceGroup.customColor` contract was stale, and the name sort was locale-dependent.
- The design lead's own finding: custom palette entries would reshuffle every automatic color. The automatic palette is now limited to built-in-named entries.

### Remaining Contentious Points
- **Automatic colors on by default, and neighbor shifts** (user, simplifier; every round). This is unchanged because Nathaniel fixed the setting, its default, and option 2. The revisions removed two instability sources: custom-palette growth and malformed colors. The only remaining shift is the one option 2 accepts.
- **Condensing the document and reducing locale keys** (simplifier). Declined. The detail is the consumer list the agent reviewers proved was needed, and the locale count is set by the catalog check.
- **Devil's advocate** repeated generic testing requests in rounds 2 and 3 with no new specifics. Round 2 added the concrete cases it named.

### Recommended Actions
Apply these three to the final document before it becomes the spec. Each was verified against the code in round 3.

1. **Off-state contract (astra, verified).** The round 2 revision normalizes candidates before it checks the setting. A malformed restored manual color (`"nope"`) used to block a valid config color and leave the group neutral; it now falls through to the config color even with automatic colors off. Keep the fix, and change the Goals and **No state** text to say: "Turning the setting off restores today's neutral fallback for every group with no valid manual or config color. One deliberate change ships regardless of the setting: a malformed manual or config color now counts as absent rather than blocking the next rung." Add a resolver test with automatic colors off: a manual `"nope"` plus a valid config color resolves to the config color.
2. **Web schema localization (sol, verified).** The configuration docs page calls `t(property.descriptionKey)` (`web/app/[locale]/(landing)/docs/configuration/page.tsx` around line 225), and all 20 `web/messages/*.json` locales carry `groupDividers`. Add the new schema description key to every `web/messages` locale under the same `docs.configuration` path, and name that in the Setting plumbing list next to the schema bullet. This is separate from the nine-locale macOS catalog.
3. **Coordinator contract (sol, verified, kept within the fixed decision).** `TabManager.setWorkspaceGroupColor` is the only production caller of `WorkspaceGroupCoordinator.setWorkspaceGroupColor`, but the public package setter stores raw strings. `CmuxWorkspaces` cannot see `WorkspaceTabColorSettings`, so normalization stays in TabManager. Add a doc-comment change on the coordinator setter: "Stores `hex` verbatim; app callers go through `TabManager.setWorkspaceGroupColor`, which canonicalizes to `#RRGGBB`." Also name `TerminalController+ControlWorkspaceGroupContext.swift:361` as the socket path's route into TabManager.

### Deferred
- A Group Icon picker (the same gap exists for `set-icon`).
- Exposing the effective color over the socket or the CLI.
- Moving hex canonicalization into a package both `CmuxWorkspaces` and the app can see, if a second direct coordinator caller ever appears.
- Nathaniel should confirm that limiting the automatic palette to built-in-named entries is acceptable. It refines the fixed "hash into the shared palette" decision.

## Appendix: Final Revised Document
# Sidebar workspace groups: Group Color menu and automatic colors

Design for the epic "Group Color submenu on the workspace group header context menu".
Brainstormed 2026-11-13. Nathaniel chose the menu shape, added automatic coloring, and
picked the collision rule recorded below.

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
- One setting turns automatic colors off and restores today's neutral fallback exactly.
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
- `docs/configuration.md` gets a `sidebar.groupAutoColor` section modeled on the
  `sidebar.groupDividers` one.

**The automatic palette.** Automatic colors draw from the built-in-named entries of the
shared palette: `WorkspaceTabColorSettings.palette()` minus `customPaletteEntries()`, in
built-in order, with duplicate hexes dropped (first occurrence wins; palette hexes are
already normalized). These are the sixteen stock colors as the user has them, including
any the user recolored or removed. Custom entries stay out on purpose: Choose Custom
Color… adds one, and a palette that grew by one would change `hash % count` and reshuffle
every automatic group the moment anyone picked a custom color. Dropping duplicate hexes is
what makes "different slot" mean "different color".

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
today's neutral fallback exactly, with no migration.

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
  group takes the next rung, and a lowercase one resolves uppercased; names that differ
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

