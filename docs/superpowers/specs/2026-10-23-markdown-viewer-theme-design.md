# Markdown viewer theme independent of the terminal

Epic: Markdown viewer theme independent of terminal. Status: draft for review.

## Intent

Let the Markdown viewer render in its own color theme, chosen separately from
the terminal. The motivating case: a dark terminal (Catppuccin Macchiato) with
light documentation (Catppuccin Latte) beside it.

## Today

`PanelContentView` hands every panel the same `PanelAppearance`, built from the
Ghostty config's background and foreground. For the Markdown preview,
`MarkdownPanelView` passes **only the background** into `MarkdownWebTheme.resolve`
(`Sources/Panels/MarkdownPanelView.swift`): `MarkdownWebTheme` has no foreground
field (`Sources/Panels/MarkdownWebSupport.swift`), and the renderer writes only
background and border CSS variables (`Sources/Panels/MarkdownWebRenderer.swift`).
`MarkdownWebTheme.resolve` reads the background, decides light or dark from its
luminance, derives muted and border tints as overlays on it, and the renderer
forces the web view's `NSAppearance` so GitHub's markdown CSS and the
highlight.js stylesheet flip between their light and dark variants. GitHub's
CSS supplies the **prose foreground** (`Resources/markdown-viewer/github-markdown.css`);
the appearance's foreground color today reaches only the panel header and the
text-editor (raw-source) view, not the rendered preview. The shell background is
transparent, so the terminal color shows through. There is no Markdown theme
setting; the customization skill docs list it as a known gap.

A Ghostty `theme` directive already resolves a bundled or user theme name to a
file. The loader is `GhosttyConfig.loadTheme`, which calls `appliedThemeName`
(in `GhosttyConfig+AppliedTheme.swift`), then `themeNameCandidates` and
`themeSearchPaths` (`CmuxTerminalCore`). The browser has a precedent for a
viewer-scoped theme knob (`browser.theme`).

## Goals

- A `markdown.theme` key in `cmux.json` naming a Ghostty theme. When set, the
  Markdown viewer takes its background **and its prose foreground** from that
  theme instead of the terminal. "Prose foreground" means the body text color
  the viewer controls; see "Foreground contract" under Decisions for exactly
  which colors change and which GitHub-CSS colors deliberately do not.
- Unset or empty means "follow the terminal", so nothing changes for users who
  don't opt in. Behavior when unset is byte-for-byte what it is today.
- The same reload, Settings and validation plumbing the other `markdown.*` keys
  use: `cmux reload-config`, `cmux-settings set markdown.theme '"Catppuccin Latte"'`,
  live update of open viewers.

## Non-goals

- Mapping the theme's **16-color ANSI palette** onto GitHub CSS variables and
  highlight.js token colors (Approach B below). Threading the single
  background/foreground pair into the prose is in scope and is NOT Approach B;
  the ANSI-to-semantic mapping is what is deferred.
- Custom theme sources beyond what Ghostty's own loader finds. See "Resolution"
  for the exact set (it is broader than only bundled themes plus
  `~/.config/ghostty/themes`, and it includes an absolute path).
- Theming the diff viewer, file preview, notes or agent chat.

## Anti-goals

- A viewer that is half-themed: a Latte page color with dark-mode GitHub text or
  dark highlight.js would be worse than today. The design must prove, by test,
  that the chosen seam actually changes rendered prose color and that GitHub CSS
  and highlight.js flip together — not merely that the panel background changed.
- Any change in behavior when `markdown.theme` is unset.

## Constraints

- App-linked code stays Swift 6.0 compatible.
- User-facing strings go through the localization audit.
- Settings keys are declared in the supported-paths list, JSON-path support,
  the section parser, the settings search index, the schema the
  `cmux-settings validate` command uses, **and the generated embedded schema**;
  repository parity tests (`tests/test_cmux_schema_parity.py`,
  `tests/test_cmux_settings_supported_paths.py`) require catalog,
  supported-path, schema, embedded-schema and installed skill-reference
  agreement, so each is a named deliverable.
- Commit the failing behavioral test before its fix.

## Approaches considered

1. **Light / dark / system switch for the viewer** (like `browser.theme`).
   Cheap, but gives GitHub's stock palette only. Dropped: the user wants a
   specific scheme, not just a polarity.
2. **A: swap the appearance at the panel boundary (chosen).** Resolve the named
   theme to a `GhosttyConfig`, build a separate `PanelAppearance` for Markdown
   panels, draw it opaque, **and carry that appearance's foreground into the
   web-theme contract** so rendered prose follows it. The luminance-keyed
   machinery (GitHub CSS light/dark, highlight.js, muted tints) still follows
   the background; the one addition is a foreground channel the renderer did not
   previously expose. This completes Approach A; it is not Approach B.
3. **B: A plus full ANSI palette mapping.** Also map the 16 ANSI colors onto
   GitHub's CSS variables and highlight.js classes. Truer to the theme, but the
   ANSI-to-semantic mapping is a heuristic and roughly triples the work.
   Deferred until A has been used and the stock accents are judged.

## Decisions

- **Key and value.** `markdown.theme`, a string, resolved through the **same
  loader a Ghostty `theme` directive uses** — `GhosttyConfig.loadTheme` /
  `appliedThemeName` — not `resolveThemeName`. This matters: `appliedThemeName`
  does **not** fall back to the opposite conditional side, whereas
  `resolveThemeName` does. Using `loadTheme` keeps `light:X,dark:Y` behaving
  exactly as it would as a Ghostty directive. Accepted value forms are
  therefore exactly what `loadTheme` accepts: a bare theme name, a conditional
  `light:X,dark:Y`, and an absolute theme-file path. My call: reuse the real
  loader's search and `appliedThemeName` semantics so there is one grammar and no
  divergence to document (see "Resolution" for the result-bearing wrapper this
  design adds, since `loadTheme` itself returns `Void`).
- **Resolution — result-bearing contract.** `GhosttyConfig.loadTheme` returns
  `Void`: on a missing file, an unreadable file, or an unmatched conditional
  side it simply returns, leaving the config's **non-optional default**
  background (`#282C34`) and foreground (`#FFFFFF`) in place. Reading those
  fields after calling it therefore cannot distinguish "theme loaded" from
  "load silently failed", which the runtime fallback and the Settings validation
  both need. So this design adds a thin **result-bearing resolver** alongside
  `loadTheme` — same package (`CmuxTerminalCore`), reusing `appliedThemeName`,
  `themeNameCandidates` and `themeSearchPaths` without reimplementing the search
  — that returns an explicit outcome: `.resolved(GhosttyConfig)` for a theme
  whose file was found, parsed, and actually supplied the colors the viewer
  needs, versus a failure that names the cause. The failure cases are: (a)
  unknown/unreadable name; (b) an unspecified conditional side for the current
  scheme; and (c) **a readable theme file that did not parse a valid background
  or foreground**. Case (c) matters because `loadTheme` treats any readable file
  as "found", `parse` silently ignores unknown directives, and
  `hasParsedBackgroundColor` / `hasParsedForegroundColor` can each fail
  independently — so a malformed file would otherwise leave the non-optional
  defaults (`#282C34` / `#FFFFFF`) in place and masquerade as a resolved palette.
  Success therefore requires **both** parse flags set, never the mere presence of
  the default colors; a file that sets the real default colors via valid
  directives is still a success, but one that never parsed them is failure (c). The appearance builder and the Settings validation both consume this
  one resolver; existing directive-loading callers of `loadTheme` are left
  unchanged. The theme is found through the same search — absolute path, then
  `themeNameCandidates` over `themeSearchPaths`, which spans
  `GHOSTTY_RESOURCES_DIR`, XDG data directories, the Ghostty app bundle, cmux
  and legacy-Ghostty application-support directories, and
  `~/.config/ghostty/themes`. The non-goal is custom *formats*, not a trimmed
  search path. On success, take `backgroundColor` and `foregroundColor` from the
  resolved `GhosttyConfig`. Divider and unfocused-overlay values stay those of
  the terminal appearance so splits look uniform.
- **Foreground contract.** The appearance's foreground must reach rendered
  prose, or the central goal fails and the anti-goal is hit. `MarkdownWebTheme`
  gains an optional `foreground` field; `MarkdownWebTheme.resolve` takes an
  optional foreground argument; and the renderer writes a prose-foreground CSS
  variable that GitHub's markdown CSS consumes for body text. Scope of the
  foreground override, to avoid a half-theme: body/prose text color follows the
  theme foreground; link, syntax-highlight (highlight.js), and semantic accent
  colors continue to come from the GitHub light/dark stylesheet selected by
  background luminance (those are Approach B's job).
  - **Source color (not contrast-corrected).** The prose foreground is the
    theme's **raw** `foregroundColor`, taken from the resolver above — not
    `PanelAppearance.fromConfig`'s foreground, which applies a 4.5:1
    contrast correction against the background for terminal legibility. Prose
    sits on the themed page background the theme author chose, so using the raw
    theme foreground keeps the author's intended pairing; the contrast-corrected
    value is for the terminal chrome, not the page. The required test asserts the
    prose CSS equals the theme's raw foreground, so the contract and the test
    agree.
  - **Install and remove.** `applyTheme` only sets properties present in the
    payload, and a Markdown rerender replaces the content element's children, not
    its inline styles — so an override installed once **survives** a later
    themed-to-unset or themed-to-unresolvable transition unless explicitly
    cleared. The contract is therefore two-directional: supply the
    foreground variable **only when a theme successfully resolves**, and on any
    transition to unset or unresolvable, explicitly **remove** the prose
    foreground property so the page returns to GitHub's stock foreground. "Unset
    emits today's CSS" is necessary but not sufficient; removal of a
    previously-installed override is the operative requirement.
- **Opacity.** A themed Markdown panel draws an opaque background
  (`usesClearContentBackground == false`) even when the terminal is
  translucent, otherwise a dark terminal would bleed through a light page. This
  must also hold when the **theme file itself** carries `background-opacity`:
  `GhosttyConfig.parse` accepts that directive and `PanelAppearance.fromConfig`
  would otherwise composite it and may choose a clear content background. The
  Markdown appearance builder therefore **discards any theme-supplied opacity**
  and forces an opaque page. A regression test uses an absolute-path theme file
  containing `background-opacity` and asserts the resulting Markdown appearance
  is opaque — the bundled `Catppuccin Latte` case alone does not exercise this.
- **Color-scheme authority and live re-resolve.** Conditional themes
  (`light:X,dark:Y`) must choose a side from a single, unambiguous authority.
  That authority is the **live app/system appearance preference**, **not** the
  scheme `PanelContentView` injects. The injected
  `windowAppearance.resolvedColorScheme` is derived from the *terminal
  background* luminance and, for opaque terminals, that terminal scheme wins over
  ambient appearance; keying the Markdown conditional side off it would let a
  permanently-dark terminal hold the theme on its dark branch when macOS turns
  light, and a light terminal pick the light branch while the app is forced dark.
  Those are exactly the mismatches this key exists to break.
  - **Live source, not the defaults snapshot.** The preference is resolved the
    same way chrome resolves it: `GhosttyConfig.appearanceSyncColorSchemePreference`,
    where an explicit app light/dark mode wins, and in **system** mode after
    launch the live `NSApp.effectiveAppearance` is authoritative (behind the
    existing `isApplicationFinishedLaunching` launch guard), falling back to a
    passed appearance and only then to `TerminalColorSchemePreference.current`.
    `TerminalColorSchemePreference.current` alone reads the `AppleInterfaceStyle`
    defaults, which the codebase documents as possibly stale after launch, so
    re-calling it on a system transition can pick the wrong conditional branch.
    The resolver receives this live preference from the app layer (the same value
    chrome uses), rather than reading defaults itself.
  The themed appearance re-resolves when that preference changes (app setting
  change or, in system mode, a live appearance change), not only on
  `reload-config`. Any per-name parse cache is keyed by (name, resolved
  preference). Tests cover a paired-theme transition **with a mismatched
  terminal/app scheme** — e.g. a dark terminal while the app/system flips light —
  and the app-forced-dark case.
- **Unknown / unresolvable theme name.** The section parser's `logInvalid` path
  creates a parsing issue, and a parsing issue makes the settings store **retain
  the entire previous last-good snapshot** rather than fall back per key — so
  routing an unknown theme name through `logInvalid` would silently keep the
  *old* theme, not fall back to the terminal as intended. Instead, accept the
  key at parse time and resolve it at appearance-build time through the
  result-bearing resolver above: on a failure outcome (unknown/unreadable name,
  or an unmatched conditional side), the builder falls back to the terminal
  appearance for that panel and logs a non-blocking runtime warning (not a parser
  issue). Because failure is an explicit outcome and not the presence of default
  colors, the fallback cannot be spoofed by a theme that happens to resolve to
  the defaults. Never crash, never show a half-applied theme, never poison the
  whole config snapshot. A test asserts an unknown name yields the terminal
  appearance while the rest of the config still applies.
- **Live update.** `MarkdownPanel`'s existing `UserDefaults` typography observer
  is **not** reused as-is: its handler returns early once any per-panel
  typography value diverges from the followed defaults
  (`adoptTypographyDefaultsIfFollowing`), so a zoomed or font-customized open
  viewer would keep its old theme. The theme is observed as independent state,
  adopted outside the typography guard, so `cmux reload-config` and the Settings
  UI update open viewers even after a local typography override. A regression
  test changes the theme (and clears it) on a viewer that has a local typography
  override and asserts the theme still updates.
- **Same-name reload invalidation.** A user can edit, delete, or create the
  theme file *without changing* `markdown.theme` or the appearance preference, so
  neither a defaults change nor the (name, preference) cache key changes — yet
  the colors should update. The settings store deliberately does not rewrite
  unchanged string defaults, so an independent theme observer cannot rely on a
  defaults change to refresh an open viewer. Therefore `reload-config`
  **invalidates the per-name cache and re-resolves**, for both cached successes
  and cached failures, using the existing committed-reload notification as the
  seam. A retained-viewer regression changes the theme file under the same name,
  invokes `reload-config`, and asserts the viewer shows the updated colors (or
  falls back to the terminal if the edit made the theme unresolvable).
- **Settings UI.** One row under the existing Markdown settings: a text field
  for the theme name, validated against the same resolution, with a hint naming
  the bundled themes directory. Note the package boundary: the row lives in
  `CmuxSettingsUI`, which does **not** depend on `CmuxTerminalCore` where the
  resolver lives, and the key is catalog-owned in `CmuxSettings`
  (`MarkdownCatalogSection`) with model init / observation in `AppSection`.
  Validation reaches the resolver through the existing host-callback seam
  (`SettingsHostActions`), not by adding a `CmuxTerminalCore` dependency to the
  UI package. Concretely this is a named deliverable on **both** sides of the
  seam: a new protocol method on `SettingsHostActions` *and* a real
  implementation in the host (`HostSettingsActions`) that calls the
  result-bearing resolver — not a default/no-op, which would make validation
  silently unavailable. The row, its catalog entry (`MarkdownCatalogSection`),
  its `AppSection` model init/observation, and the host validation method are all
  named deliverables. My call: a
  463-entry picker is a separate design question; a text field matches
  `markdown.fontFamily`. Discoverability (a picker or a "list themes" affordance)
  is tracked as an explicit follow-on, since a bare text field with no list is a
  real friction point raised in review.
  - **Validation rules (my calls, closing the review's open points).**
    (1) The new `SettingsHostActions` method gets a protocol-extension default
    that returns "validation unavailable", so the existing conformers (the
    sections and the test double) keep compiling; the host implementation
    overrides it, and a test asserts the host override is the one the Markdown
    row reaches, so the default cannot silently stand in for it.
    (2) Validation runs on commit (field loses focus or Return), not per
    keystroke, and is a synchronous main-actor call: one theme resolution is a
    handful of small file reads over a fixed search path, which is the same
    cost `cmux reload-config` already pays on the main actor.
    (3) For a conditional `light:X,dark:Y`, validation resolves **every** named
    side, not just the live one, and reports the first side that fails by name;
    a theme that only breaks when macOS flips appearance is exactly what a user
    cannot discover at runtime.
- **Docs.** Update the customization skill's viewer matrix and the settings
  skill's references so the "Markdown theme is not a setting" note goes away.

## Left to the builder

- Where the markdown-only `PanelAppearance` is produced: `PanelContentView`'s
  `.markdown` case versus inside `MarkdownPanelView`, whichever keeps
  `PanelAppearance` a value type with no extra state.
- Exact spelling of the prose-foreground CSS variable and which GitHub-CSS
  selectors consume it, as long as the contract above holds (prose foreground
  follows the theme; links/syntax/accents stay stylesheet-driven) and the unset
  path emits today's CSS unchanged.
- Whether to cache the parsed theme config per (name, effective scheme) or
  re-parse on change.

## Tests (required)

- Parser/catalog test for `markdown.theme`, plus the parity-test updates
  (supported paths, schema, embedded schema, skill references).
- An appearance test that `Catppuccin Latte` yields an opaque light appearance.
- A **rendered-prose** test: with the theme set, the prose foreground CSS
  equals the theme's **raw** foreground; with it unset, the emitted CSS is
  byte-for-byte today's.
- A **resolver-outcome** test: a resolvable name returns a success carrying the
  parsed config; an unknown/unreadable name, an unmatched conditional side, and a
  readable-but-malformed file that parses no valid background/foreground each
  return the corresponding failure — while a theme that sets the real default
  colors via valid directives still reports success (failure is decided by the
  parse flags, not inferred from default colors).
- A fallback test: an unknown name yields the terminal appearance and does not
  retain a previously valid theme or poison the config snapshot.
- A **live-renderer transition** test in the same retained `WKWebView`: after
  themed→unset and themed→unresolvable, the computed prose color returns to
  GitHub's stock foreground (proving the override was removed, not merely
  re-emitted), and after a polarity change the GitHub foreground variable and the
  `hljs-light`/`hljs-dark` enabled state both flip together (proving GitHub CSS
  and highlight.js do not go stale). This supersedes a payload-only or
  panel-state-only check.
- A live-update test on a viewer with a local typography override: theme changes
  and clears still apply (adoption is outside the typography guard).
- A conditional-theme transition test driven by the **live app/system
  preference** (not terminal chrome, not the stale defaults snapshot):
  `light:X,dark:Y` re-resolves when the preference flips, with a **mismatched
  terminal scheme** (dark terminal, app/system light) and the app-forced-dark
  case.
- An **opacity-discard** test: an absolute-path theme file containing
  `background-opacity` still yields an opaque Markdown appearance.
- A **same-name reload** test: editing the theme file under an unchanged
  `markdown.theme` and running `reload-config` updates a retained viewer's colors
  (or falls back to the terminal when the edit makes it unresolvable),
  invalidating both cached successes and cached failures.
