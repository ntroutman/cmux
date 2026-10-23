# Design Deliberation: Markdown viewer theme independent of the terminal

**Source:** docs/superpowers/specs/2026-10-23-markdown-viewer-theme-design.md
**Date:** 2026-10-23
**Rounds:** 4
**Mode:** converge
**Personas:** devils-advocate, pragmatist, simplifier, user, astra, sol
**Final verdict:** Needs Work (ship-ready architecture; one reviewer (sol) holds reject on an unspecified Settings-validation flow; two non-agent reviewers hold needs_work on standing discoverability/scope trade-offs)

Note: `astra` and `sol` are agent-backed, repo-grounded reviewers that read the actual cmux source. Their findings were independently verified against the code before each revision. `pragmatist`, `simplifier`, `user`, `devils-advocate` are prompt-only reviewers.

## Round 1: Initial Critiques

### Dr. Scrutiny (Devil's Advocate) (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.8

_The proposal has a solid foundation but requires addressing some points to ensure robustness and clarity._

- The proposal assumes that users are familiar with Ghostty's theme naming conventions, which may not be the case for all users.
- The proposal does not explicitly address potential performance implications of parsing theme files on change.
- The proposal should clarify the user experience when an invalid theme name is entered.
- The proposal could benefit from a more detailed discussion of the trade-offs between Approach A and Approach B.
- The proposal should provide more specific guidance on where to place the markdown-only `PanelAppearance` and whether to cache the parsed theme config.

### The Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 0.95

_This is a well-scoped and pragmatic proposal that effectively leverages existing systems to deliver a high-value feature with minimal implementation risk._

- The chosen approach of swapping the panel appearance is highly practical, reusing existing theme resolution and rendering logic to minimize new code.
- Deferring full palette mapping is a smart decision that makes the initial implementation achievable, while leaving the door open for future enhancements based on user feedback.
- The plan correctly identifies and addresses key execution details like opacity for themed panels, graceful fallback for invalid theme names, and maintaining UI cohesion for panel dividers.
- Relying on existing settings infrastructure for live reloads and CLI configuration is an efficient use of resources that reduces implementation overhead.
- While using a text field for the theme name is a reasonable short-term choice, the lack of theme discoverability should be tracked as a follow-on task to improve the user experience.

### The Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.85

_The proposal is clear and well-structured but can be improved by considering a simpler implementation and reducing complexity._

- Consider a simpler implementation that achieves 80% of the value without the need for a separate theme configuration.
- Evaluate if the complexity of approach B is justified by real requirements.
- Explore the possibility of using a single theme configuration that can be dynamically adjusted based on user preferences.
- Simplify the settings UI by providing a dropdown menu with a limited number of predefined themes instead of a text field.

### The User (user)
**Verdict:** needs_work | **Confidence:** 0.75

_This feature solves a niche problem, but the implementation introduces too much configuration friction and its limited scope makes it feel like an incomplete solution._

- Okay, so I *can* have a light page on a dark terminal. Fine, I guess that's useful for *some* people who actually read documentation inside their terminal. I usually just copy it out or use a browser, so 'why should I care' isn't screaming at me.
- Another `cmux.json` setting? And if I use the UI, it's just a text field? So I need to *know* the theme names, or remember where to find a list? That's just asking for typos and me giving up before I even start.
- It's only for the Markdown viewer? So my diffs, file previews, and notes still look like crap if I have a strong preference? Inconsistent theming across different viewers makes the whole app feel half-baked, not a premium experience.
- They explicitly punted on mapping ANSI colors (Approach B). So it'll be a light background, but the code blocks or specific elements might still look off or like a stock GitHub palette, not my chosen theme's *full* aesthetic. What's the point of a 'theme' then if it's only half-applied?
- If I mistype a theme name, it just 'falls back to the terminal appearance.' So I'll just sit there wondering why my theme isn't applying, with no helpful feedback. Great user experience for someone who just wants things to work.

### Astra (GPT-6, repo-grounded) (astra)
**Verdict:** reject | **Confidence:** 0.97

_The panel-boundary approach cannot deliver the promised foreground color, the chosen resolver differs from Ghostty's actual behavior, and the design leaves live-update and Settings-package dependencies unaddressed._

- Blocking: swapping PanelAppearance does not apply the theme's foreground to rendered Markdown, contrary to docs/superpowers/specs/2026-10-23-markdown-viewer-theme-design.md:28-30 and 65-68. MarkdownPanelView passes only the background into MarkdownWebTheme (Sources/Panels/MarkdownPanelView.swift:76-86); MarkdownWebTheme has no foreground field (Sources/Panels/MarkdownWebSupport.swift:391-423), and the renderer's CSS payload contains only backgrounds and borders (Sources/Panels/MarkdownWebRenderer.swift:395-418). Prose therefore retains GitHub's fixed foreground colors (Resources/markdown-viewer/github-markdown.css:69-76,127-132), while the header and text editor receive the selected theme's foreground. Specify the missing foreground contract through the renderer and CSS, preserving existing behavior when unset. The proposed opaque/light appearance test cannot detect this; add a rendered-prose color assertion.
- Blocking: the promised Ghostty-compatible resolution uses the wrong resolver. The design explicitly chooses resolveThemeName (docs/superpowers/specs/2026-10-23-markdown-viewer-theme-design.md:76-79), whose cross-side fallback makes 'light:Catppuccin Latte' resolve to Latte even in dark mode (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1189-1209). Actual loadTheme calls appliedThemeName instead (same file:1108-1111), which returns nil when the current appearance has no assigned theme or unconditional base (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig+AppliedTheme.swift:3-24,57-66). Choose actual Ghostty semantics and define the viewer fallback for an unspecified side, or explicitly document this divergence rather than promising compatibility; cover one-sided values as well as complete pairs.
- Needs work: theme updates must not inherit the typography observer's opt-out behavior. The existing observer only calls adoptTypographyDefaultsIfFollowing, which returns immediately after any per-viewer font-size, font-family, or width customization (Sources/Panels/MarkdownPanel.swift:266-291). Following that adoption path would leave a zoomed or otherwise customized open viewer on its old theme, violating the live-update goal. Require independently observable theme state and adoption outside the typography guard, with a regression covering theme changes and clearing the setting after a local typography override.
- Needs work: conditional themes introduce an appearance dependency that the proposed UserDefaults observer and optional per-name cache do not cover. The specification says to use the current system scheme, but Ghostty's convenience preference reader honors the app's forced light/dark setting before consulting the system (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/ColorScheme/TerminalColorSchemePreference.swift:28-54), and PanelContentView injects the window-resolved scheme rather than an independent system value (Sources/Panels/PanelContentView.swift:46-48). Existing system-change notification handling also exits unless app appearance is 'system' (Sources/SystemAppearanceObserver.swift:69-84). Specify the system-appearance source and invalidation path, including when the app is forced dark but macOS changes appearance; any resolution cache must account for the selected scheme. Add a live paired-theme transition test.
- Needs work: the Settings requirement crosses a package boundary omitted from the design's plumbing list. The existing row is in CmuxSettingsUI and binds through the typed MarkdownCatalogSection (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift:114-116,524-536; Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/MarkdownCatalogSection.swift:10-42). CmuxSettingsUI has no dependency on CmuxTerminalCore, where the required Ghostty resolver lives (Packages/macOS/CmuxSettingsUI/Package.swift:17-29; Sources/GhosttyConfig.swift:1-7). Specify the catalog addition and how the row obtains shared theme validation—through a host callback or an explicitly shared dependency—rather than implying that adding a text field can directly reuse the resolver. SettingsHostActions already owns host-provided theme context (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/SettingsHostActions.swift:152-160), so account for that interface and its implementation if it is extended.

### Sol (GPT-5.6, repo-grounded) (sol)
**Verdict:** reject | **Confidence:** 0.98

_The design cannot satisfy its foreground-color goal through the chosen seam and conflicts with existing theme-resolution and invalid-setting behavior._

- Approach A does not make rendered Markdown use the Ghostty theme foreground. `MarkdownPanelView` passes only the appearance background into `MarkdownWebTheme.resolve` (Sources/Panels/MarkdownPanelView.swift:76-80); `MarkdownWebTheme` has no foreground field (Sources/Panels/MarkdownWebSupport.swift:390-422); and the renderer updates only background and border CSS variables (Sources/Panels/MarkdownWebRenderer.swift:395-417). The foreground currently affects the header and text editor, not preview prose (Sources/Panels/MarkdownPanelView.swift:100-105,130-135). The web-theme contract must change or the stated foreground goal must be removed.
- The proposed resolver does not match Ghostty directive semantics. `GhosttyConfig.loadTheme` uses `appliedThemeName` (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1102-1128), which deliberately does not fall back to the opposite conditional side (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig+AppliedTheme.swift:1-66). The chosen `resolveThemeName` does cross-side fallback (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1147-1209), so `light:X` in dark mode would behave differently from a Ghostty `theme` directive.
- The claim that the setting accepts anything Ghostty's directive accepts conflicts with the resolution and non-goal. Ghostty accepts an absolute theme-file path (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1112-1117), while the specified candidate/search-path flow omits that branch. The existing search path also includes GHOSTTY_RESOURCES_DIR, XDG data directories, Ghostty.app, cmux application-support directories, and legacy Ghostty application support—not merely bundled themes and `~/.config/ghostty/themes` (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1352-1417).
- Unknown-theme fallback conflicts with section-parser error handling. `logInvalid` creates a parsing issue (Sources/KeyboardShortcutSettingsFileStore.swift:1885-1893), and any such issue causes reload to retain the entire previous last-good snapshot (Sources/KeyboardShortcutSettingsFileStore.swift:328-359). Therefore changing a valid theme to an unknown name would retain the previous theme, not fall back to the terminal as specified. The design must choose runtime fallback without a parser issue or define new per-key invalidation semantics.
- Reusing the typography observer does not by itself guarantee live theme updates. Its handler returns early whenever any per-panel typography value has diverged from the followed defaults (Sources/Panels/MarkdownPanel.swift:265-291). Theme adoption must be independent of that guard and must also re-resolve conditional themes when the effective light/dark scheme changes.
- The settings work breakdown omits required contract surfaces. `markdown.*` keys are catalog-owned (Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/MarkdownCatalogSection.swift:10-38), while the Settings row needs corresponding model initialization and observation in `AppSection` (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift:38-42,113-118,174-180). Repository parity tests explicitly require catalog, supported-path, schema, generated embedded schema, and installed skill-reference agreement (tests/test_cmux_schema_parity.py:1-18,215-229; tests/test_cmux_settings_supported_paths.py:102-117). These should be named as required changes.
- The proposed tests cannot prove the anti-goal that GitHub CSS and highlight.js switch together during live updates. That behavior spans native `NSAppearance` assignment (Sources/Panels/MarkdownWebRenderer.swift:134-151) and the page's `prefers-color-scheme` listener and stylesheet toggling (Resources/markdown-viewer/shell.html:1952-1964). A parser test and opaque-light appearance test do not observe this integration.

## Design Lead Revision (after Round 1)

### Rationale

1. **astra & sol (blocking: foreground never reaches prose).** Accepted and treated as the central fix. Verified against code: `MarkdownWebTheme` has no foreground field and `resolve` takes only `backgroundColor`; the renderer writes only background/border CSS variables; the appearance foreground reaches only the header and raw-text editor, not preview prose. Rewrote "Today", added a "Foreground contract" decision that adds a `foreground` field to `MarkdownWebTheme`, a foreground argument to `resolve`, and a prose-foreground CSS variable. Scoped it (prose body follows theme; links/syntax/accents stay stylesheet-driven, which is Approach B's job) so it does not quietly expand into Approach B. Added a required rendered-prose test.
2. **astra & sol (blocking: wrong resolver / value grammar).** Accepted. Switched the stated resolver from `resolveThemeName` to `GhosttyConfig.loadTheme`/`appliedThemeName` (verified: `loadTheme` calls `appliedThemeName`, which does not cross-fall-back; it also handles an absolute path). Restated accepted value forms and the full search-path set, and reframed the non-goal as custom *formats*, not a narrowed search path.
3. **sol (blocking: unknown-theme fallback conflicts with `logInvalid`).** Accepted. Verified the store retains the whole previous snapshot on any parsing issue. Changed the fallback to resolve at appearance-build time with a runtime warning, not `logInvalid`, so an unknown name yields the terminal appearance without poisoning the snapshot or keeping a stale theme.
4. **astra & sol (needs_work: typography observer reuse).** Accepted. Verified the observer returns early once typography diverges. Theme is now independent observed state adopted outside the typography guard, with a regression test on a typography-overridden viewer.
5. **astra & sol (needs_work: color-scheme source / conditional themes).** Accepted. Named the effective-scheme source (window/app-appearance, app-forced setting wins over system), required re-resolve on scheme change, keyed any cache by (name, scheme), and added a paired-theme transition test.
6. **astra & sol (needs_work: Settings package boundary + parity tests).** Accepted. Verified `CmuxSettingsUI` does not depend on `CmuxTerminalCore`. Validation now routes through the `SettingsHostActions` host-callback seam; catalog/`AppSection` and the five parity surfaces are named deliverables.
7. **user (needs_work: discoverability of theme names).** Partially accepted. Kept the text field (matches `markdown.fontFamily`, and a 463-entry picker is a separate design question) but promoted discoverability to an explicit tracked follow-on.
8. **user (needs_work: niche / only-markdown / only-half-themed).** Acknowledged as scope, not changed: scope stays the Markdown viewer per the task constraint; the half-theme concern is now answered by the foreground contract and the anti-goal test, so the shipped result is a coherently themed page rather than a half-theme.
9. **simplifier (needs_work: simpler implementation / dropdown / single config).** Partially accepted. The dropdown is the discoverability follow-on. "A single theme config dynamically adjusted" is declined: the whole point is a theme independent of the terminal, so a separate resolved appearance is the simplification that actually matches intent. Approach B stays deferred per constraint.
10. **devils-advocate (needs_work: Ghostty naming familiarity, parse performance, invalid UX, A-vs-B tradeoff, builder guidance).** Accepted into the relevant sections: invalid UX is the runtime-fallback decision, performance is the (name, scheme) cache note, A-vs-B is clarified so foreground-threading is not mistaken for B, and builder guidance is tightened in "Left to the builder".
11. **pragmatist (approve).** No change required; its one caveat (track discoverability as a follow-on) is now explicit.

### Key Changes

- Rewrote **Today** and added a **Foreground contract**: `MarkdownWebTheme` gains a foreground field, `resolve` takes a foreground, the renderer writes a prose-foreground CSS variable (completes Approach A; not Approach B).
- Switched the stated resolver from `resolveThemeName` to `loadTheme`/`appliedThemeName`; restated accepted value forms and the full search-path set.
- Moved unknown-theme fallback out of `logInvalid` (which poisons the whole snapshot) to appearance-build time.
- Theme observed independently of the typography guard; named the effective-scheme source and conditional re-resolve; named the `SettingsHostActions` seam and the five parity surfaces; promoted discoverability to a tracked follow-on.

## Round 2: Deliberation

### Dr. Scrutiny (Devil's Advocate) (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.8

_The proposal has addressed some concerns but still needs further clarification and testing._

- The proposal now explicitly addresses the user experience when an invalid theme name is entered, which is a positive change.
- The trade-offs between Approach A and Approach B are now more clearly discussed, helping to justify the chosen approach.
- The proposal provides more specific guidance on where to place the markdown-only `PanelAppearance` and whether to cache the parsed theme config, which is helpful for implementation.
- However, the proposal still assumes that users are familiar with Ghostty's theme naming conventions, which may not be the case for all users. More user-friendly alternatives, such as a dropdown menu, should be considered.
- The potential performance implications of parsing theme files on change are not fully addressed. More testing and optimization may be needed to ensure smooth performance.
- The discoverability of theme names is still a concern and should be tracked as a follow-on task.

**Changed from Round 1:** same verdict.

### The Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 0.95

_This revised plan is highly practical and executable, addressing prior technical flaws with specific, low-risk implementation strategies and a comprehensive test plan._

- Reusing the existing theme loader and search paths is a highly efficient approach that minimizes new code and documentation debt.
- The new 'Foreground contract' decision provides a clear, testable path to delivering the core feature without the risk of a 'half-themed' result, which was a blocking issue in the previous version.
- The thoughtful handling of edge cases like unknown themes, live updates with local overrides, and conditional theme transitions demonstrates a strong focus on implementation reality and robustness.
- The plan correctly identifies complex inter-package dependencies and specifies clean architectural solutions, such as host callbacks for the Settings UI, to avoid creating technical debt.
- Deferring complex UI work (a theme picker) and full palette mapping (Approach B) remains the correct pragmatic choice, ensuring the core value can be delivered quickly and safely.

**Changed from Round 1:** same verdict.

### The Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.85

_The revised document addresses some concerns but still has room for simplification._

- The decision to use a separate theme configuration for Markdown viewer is justified, but consider if a simpler approach can achieve 80% of the value.
- The complexity of approach B is deferred, which is acceptable given the current scope.
- The settings UI could be further simplified by using a dropdown menu with predefined themes instead of a text field.
- The discoverability of theme names is acknowledged as a follow-on, which is a good approach.

**Changed from Round 1:** same verdict.

### The User (user)
**Verdict:** needs_work | **Confidence:** 0.8

_While some critical issues like error handling and basic foreground application are addressed, the feature remains limited in scope and delivers only a partial theming experience, leaving significant user friction._

- The 'theme' is still only partially applied; critical elements like links and syntax highlighting won't follow the chosen theme, making it feel incomplete and not truly integrated.
- Discoverability of theme names remains a significant hurdle for immediate adoption, as users still need to know or find theme names manually, despite it being a 'tracked follow-on'.
- The feature's limited scope to only the Markdown viewer continues to create an inconsistent user experience across different content types, making the app feel half-baked.
- While improved, the feedback for an unknown theme name (a runtime warning) is still not as immediate or user-friendly as it could be, potentially leading to confusion about why the theme isn't applying.
- The fundamental 'why should I care' for reading documentation directly in the terminal with a custom theme still isn't compelling enough to overcome the friction of setup and the partial nature of the theming.

**Changed from Round 1:** same verdict.

### Astra (GPT-6, repo-grounded) (astra)
**Verdict:** reject | **Confidence:** 0.97

_The revision addresses most prior concerns, but the verdict remains reject because the conditional-theme authority and theme-loading failure contract still do not match the repository._

- Blocking — The color-scheme decision conflates app appearance with terminal-derived chrome appearance. PanelContentView injects windowAppearance.resolvedColorScheme (Sources/Panels/PanelContentView.swift:46-48), but the window receives the terminal's effective scheme (Sources/Windowing/AppWindowChromeComposition.swift:48-55), which is derived from the terminal background, not TerminalColorSchemePreference.current (Sources/GhosttyTerminalView.swift:1728-1731,2953-2959). For opaque terminals, that terminal scheme explicitly wins over ambient appearance (Packages/macOS/CmuxAppKitSupportUI/Sources/CmuxAppKitSupportUI/WindowChrome/Appearance/WindowAppearanceSnapshot.swift:119-135). Consequently, a permanently dark terminal can keep the Markdown conditional theme on its dark branch when macOS becomes light; conversely, a light terminal can select the light branch despite the app being forced dark. The revision adds invalidation but has not selected one unambiguous authority. Specify the app/system preference as the conditional-selection input, independently of terminal chrome and Markdown-background luminance, and test mismatched terminal/app schemes.
- Blocking — Moving unknown-name handling out of the parser is correct, but loadTheme cannot currently report the outcome the new fallback and Settings validation require. Both overloads return Void; the implementation silently returns for an unspecified conditional side, returns after reading a file, and silently finishes after unsuccessful searches (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1089-1131). A fresh config already contains non-optional background and foreground defaults, so reading those fields does not establish successful resolution (same file:73-99). Specify a shared result-bearing loader/resolution contract consumed by both the appearance builder and host validation, without duplicating the search algorithm. Account for existing directive-loading callers (same file:598-607), and distinguish a successfully loaded theme from missing/unreadable files and an unassigned conditional side. The last case also needs the one-sided regression requested in the prior round.
- Needs work — The new foreground contract specifies installation but not removal from the retained renderer. Emitting today's foreground-free payload after clearing the setting does not restore today's rendering: applyTheme only calls content.style.setProperty for keys present in the payload (Sources/Panels/MarkdownWebRenderer.swift:395-418), and Markdown rerendering replaces the content element's children, not its inline styles (Resources/markdown-viewer/shell.html:1837-1851). A previously installed foreground override therefore survives unless explicitly removed. Define removal on themed-to-unset and themed-to-unresolvable transitions, and make successful theme resolution—not merely a nonempty setting—the condition for supplying the foreground override. Strengthen the live-update regression to inspect computed prose color in the same retained WKWebView after both transitions, rather than checking only panel state or an emitted payload.

**Changed from Round 1:** same verdict.

### Sol (GPT-5.6, repo-grounded) (sol)
**Verdict:** reject | **Confidence:** 0.98

_Most prior concerns are addressed, but the design still relies on a loader result that does not exist and omits required integration work._

- Blocking: `GhosttyConfig.loadTheme` returns `Void`; missing files and unmatched conditional sides simply return while leaving default colors intact. The proposed runtime fallback therefore cannot distinguish failure from a loaded default-colored configuration. Add a success-returning resolver/API or explicitly define resolution without reimplementing it. Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:74-93,1089-1130; Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig+AppliedTheme.swift:25-66.
- The Settings validation contract omits its live host implementation. Adding validation through `SettingsHostActions` requires a protocol method and a meaningful implementation in `HostSettingsActions`; otherwise a default/no-op implementation can make validation silently unavailable. Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/SettingsHostActions.swift:33-47,450-459,649-670; Sources/HostSettingsActions.swift:14-22.
- The foreground contract conflicts with the existing appearance factory: `PanelAppearance.fromConfig` replaces theme foregrounds below 4.5 contrast, so carrying `appearance.foregroundColor` does not always equal the theme's foreground as the required test states. Specify whether prose uses the raw theme color or the contrast-corrected panel color. Sources/Panels/TerminalPanelView.swift:470-489; Sources/Sidebar/SidebarAppearanceSupport.swift:188-200.
- The prior integration-test concern remains. Theme polarity crosses native `WKWebView.appearance`, CSS media queries, and JavaScript-controlled highlight stylesheets; a conditional-resolution test can pass while GitHub CSS or highlight.js remains stale. Require a live renderer test asserting both the GitHub foreground variable and `hljs-light`/`hljs-dark` enabled state after a transition. Sources/Panels/MarkdownWebRenderer.swift:136-143,320-418; Resources/markdown-viewer/shell.html:1952-1968; Resources/markdown-viewer/github-markdown.css:11-75.

**Changed from Round 1:** same verdict.

## Design Lead Revision (after Round 2)

### Rationale

1. **astra & sol (blocking: `loadTheme` returns `Void`, cannot report success/failure).** Accepted — this is a real defect in my Round-1 fallback plan. Verified: `loadTheme` returns `Void`; a fresh `GhosttyConfig` carries non-optional default background (`#282C34`) and foreground (`#FFFFFF`), so reading the fields after a silent miss looks identical to a loaded theme. Added a **result-bearing resolver** in `CmuxTerminalCore` that reuses `appliedThemeName`/`themeNameCandidates`/`themeSearchPaths` (no reimplementation of the search) and returns `.resolved(config)` vs a named failure (unknown/unreadable name, or unmatched conditional side). Success is defined by the search outcome and the `hasParsed*` flags, never by the presence of default colors. Both the appearance builder and Settings validation consume this one resolver; existing directive callers are untouched. Added a resolver-outcome test.
2. **astra (blocking: conditional-theme scheme authority is terminal-derived, not app/system).** Accepted — I named the wrong authority. Verified: `PanelContentView` injects `windowAppearance.resolvedColorScheme`, which is derived from the terminal background and, for opaque terminals, wins over ambient appearance. Changed the authority to `TerminalColorSchemePreference.current` (app forced setting, else system), independent of terminal chrome and of the page's own background luminance. Re-resolve fires on that preference changing. Added a mismatched-terminal/app-scheme transition test.
3. **astra & sol (needs_work/blocking: foreground removal + contrast-correction conflict).** Accepted both halves. (a) Removal: verified `applyTheme` only sets payload-present properties and rerender replaces children not inline styles, so a once-installed override survives clearing. Made the contract two-directional: supply the variable only on successful resolve, and explicitly **remove** it on themed→unset/unresolvable. (b) Contrast: verified `PanelAppearance.fromConfig` applies a 4.5:1 contrast correction. Specified prose uses the theme's **raw** `foregroundColor` (the page keeps the author's intended pairing on the author's background), so the contract and the "prose == theme foreground" test agree. Strengthened the live-renderer test to inspect computed prose color in the retained `WKWebView` and the `hljs-light`/`hljs-dark` state after transitions.
4. **sol (needs_work: Settings validation needs a real host implementation).** Accepted. Made both the `SettingsHostActions` protocol method and a real `HostSettingsActions` implementation (calling the resolver, not a no-op) named deliverables.
5. **devils-advocate (needs_work: Ghostty naming familiarity, parse performance, discoverability).** Standing items, already bounded: discoverability is a tracked follow-on (kept); performance is the (name, preference)-keyed cache; naming familiarity is the hint text plus the follow-on picker. No new change required beyond Round 1's handling.
6. **simplifier (needs_work: dropdown instead of text field; "80% simpler").** Standing trade-off, held. The dropdown is the discoverability follow-on; the separate resolved appearance remains the right-sized realization of "a theme independent of the terminal". Approach B stays deferred per constraint.
7. **user (needs_work: still partial theming, markdown-only scope, niche value, runtime-warning feedback).** Standing trade-offs, held and bounded by the task constraint (scope stays the Markdown viewer; Approach B deferred). The half-theme worry is now answered by the foreground contract plus the anti-goal live-renderer test; links/syntax staying stylesheet-driven is explicitly Approach B's job, deferred by decision, not an oversight. Discoverability is the tracked follow-on. These are acknowledged costs of a deliberately narrow first cut, not unresolved defects.
8. **pragmatist (approve).** No change; it confirmed the foreground contract and edge-case handling as the right fixes.

### Key Changes

- Added a **result-bearing resolver** (success vs named failure) because `loadTheme` returns `Void` and default colors can't signal failure.
- Named the **app/system appearance preference** (not the terminal-derived injected scheme) as the conditional-theme authority.
- Made the foreground contract **two-directional** (install on resolve, explicitly remove on unset/unresolvable) and specified **raw** theme foreground (not `fromConfig`'s contrast-corrected value).
- Named both the `SettingsHostActions` protocol method and a real host implementation; strengthened the live-renderer test.

## Round 3: Deliberation

### Dr. Scrutiny (Devil's Advocate) (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.75

_The revised document addresses some concerns but still has room for improvement._

- The proposal now explicitly addresses the user experience when an invalid theme name is entered, which is a positive change.
- The trade-offs between Approach A and Approach B are now more clearly discussed, helping to justify the chosen approach.
- The proposal provides more specific guidance on where to place the markdown-only `PanelAppearance` and whether to cache the parsed theme config, which is helpful for implementation.
- However, the proposal still assumes that users are familiar with Ghostty's theme naming conventions, which may not be the case for all users. More user-friendly alternatives, such as a dropdown menu, should be considered.
- The potential performance implications of parsing theme files on change are not fully addressed. More testing and optimization may be needed to ensure smooth performance.
- The discoverability of theme names is still a concern and should be tracked as a follow-on task.

**Changed from Round 2:** same verdict.

### The Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 1.0

_This revised plan is exceptionally robust, addressing all previously identified execution risks with clean architectural solutions and a comprehensive testing strategy._

- The new result-bearing theme resolver is the correct and necessary solution to the silent-failure risk of the existing loader, ensuring reliable fallback and validation behavior.
- The refined 'Foreground contract', which specifies using the raw theme color and explicitly removing the CSS override on fallback, is a pragmatic and robust way to prevent visual bugs like a 'half-themed' or 'sticky' state.
- Correctly identifying the app/system preference as the authority for conditional themes fixes a critical logic flaw from the previous draft and ensures the feature behaves as users expect, independent of the terminal's own colors.
- The plan demonstrates a deep understanding of implementation details, from package dependency boundaries (Settings UI) to WKWebView state management, which significantly de-risks execution.
- The continued deferral of a full UI picker and ANSI palette mapping remains the right call, prioritizing the swift and safe delivery of core functionality without getting bogged down in secondary complexity.

**Changed from Round 2:** same verdict.

### The Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.8

_The design has addressed many concerns but could still benefit from further simplification and clarification._

- The addition of a result-bearing resolver addresses the issue of determining theme load success or failure, which is a good step forward.
- Changing the authority for conditional theme selection to the app/system preference instead of the terminal-derived scheme is a sound decision.
- The two-directional contract for foreground removal and the use of the theme's raw foreground color for prose text are well-considered.
- The requirement for a real host implementation for settings validation ensures that the theme resolution is properly tested.
- The decision to defer Approach B and maintain the current scope is reasonable given the constraints.
- The use of a text field for theme selection, while functional, could be simplified further with a dropdown menu for predefined themes.
- Discoverability of theme names remains a follow-on item, which is acceptable but should be prioritized for user experience.
- The design could still benefit from a more thorough consideration of simplification opportunities, particularly in the settings UI and theme selection process.

**Changed from Round 2:** same verdict.

### The User (user)
**Verdict:** needs_work | **Confidence:** 0.9

_The proposed changes acknowledge key user pain points like partial theming and discoverability but explicitly defer their resolution, leaving the feature feeling incomplete and frustrating for immediate use._

- The explicitly 'deferred' full theming (Approach B) means the viewer will still feel incomplete, with links and syntax colors not aligning with the chosen theme.
- Discoverability remains a critical user friction point; a text field for theme names without a list or picker is user-unfriendly, and labeling it a 'tracked follow-on' means I have to deal with it now.
- The feature's continued limitation to only the Markdown viewer offers inconsistent theming across different content types, making its overall value proposition weak.
- Receiving a 'non-blocking runtime warning' for an unknown theme is poor user feedback and will lead to confusion rather than clarity in the settings UI.
- Despite the revisions, the 'why should I care' factor is still undermined by the acknowledged partiality and setup friction, making it a low-priority adoption for most users.

**Changed from Round 2:** same verdict.

### Astra (GPT-6, repo-grounded) (astra)
**Verdict:** needs_work | **Confidence:** 0.9

_The revision resolves my prior blocking concerns, changing my verdict from reject to needs_work, but same-name theme reloads still need an explicit invalidation contract._

- Needs work — Define reload behavior when the theme name and appearance preference remain unchanged. The document permits caching by (name, preference), but a user can edit, delete, or create the corresponding theme file without changing either value. GhosttyConfig.loadTheme currently reads files on each invocation (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1108-1130), while settings reload deliberately avoids rewriting unchanged string defaults (Sources/KeyboardShortcutSettingsFileStore.swift:1527-1532). An independent theme observer therefore cannot rely on a defaults change to refresh an existing viewer, and the permitted cache can preserve obsolete colors or a cached failure. Require explicit reload invalidation and re-resolution, including cached failures; the existing committed-reload notification provides a seam (Sources/GhosttyTerminalView.swift:1989-1997). Add a retained-viewer regression that changes the theme file under the same name, invokes reload-config, and verifies updated colors or terminal fallback.
- Resolved — The result-bearing resolver adequately addresses the loader's silent-failure problem without requiring changes to directive-loading callers: the existing loader returns Void and silently exhausts its search (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1089-1131), while appliedThemeName explicitly preserves one-sided conditional semantics (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig+AppliedTheme.swift:25-66). The revised success/failure contract and outcome tests address the original concern.
- Resolved — The conditional-theme authority is now correct. TerminalColorSchemePreference resolves explicit app light/dark settings before consulting system appearance (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/ColorScheme/TerminalColorSchemePreference.swift:28-55), independently of PanelContentView's injected window scheme (Sources/Panels/PanelContentView.swift:46-48). The mismatched-terminal and forced-dark tests directly cover the previously identified failure.
- Resolved — Explicit foreground removal, raw foreground selection, and independent theme adoption address the renderer and state concerns. The current renderer only installs supplied properties (Sources/Panels/MarkdownWebRenderer.swift:395-418), PanelAppearance transforms the configured foreground through its readability helper (Sources/Panels/TerminalPanelView.swift:470-480), and typography adoption stops after a local override (Sources/Panels/MarkdownPanel.swift:277-291). The revised contracts and retained-WKWebView transition tests target these actual seams. Naming both SettingsHostActions and its concrete host implementation also closes the validation boundary without introducing a terminal-core dependency into CmuxSettingsUI (Packages/macOS/CmuxSettingsUI/Package.swift:17-29; Sources/HostSettingsActions.swift:15-17).

**Changed from Round 2:** reject -> needs_work.

### Sol (GPT-5.6, repo-grounded) (sol)
**Verdict:** reject | **Confidence:** 0.94

_The revision addresses the prior foreground, renderer-transition, resolver, and host-validation concerns, but still names the wrong live appearance authority and leaves malformed and translucent theme outcomes undefined._

- The prior feedback is substantially addressed: the document now accounts for loadTheme's silent Void behavior, requires a real HostSettingsActions implementation, distinguishes raw foreground from PanelAppearance's contrast correction, and requires retained-WKWebView transition coverage. Repository basis: Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:74-99,1089-1130; Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/SettingsHostActions.swift:450-459,649-670; Sources/HostSettingsActions.swift:14-22; Sources/Panels/TerminalPanelView.swift:470-489; Sources/Panels/MarkdownWebRenderer.swift:320-418.
- Blocking factual error: TerminalColorSchemePreference.current is a defaults-based snapshot, not the repository's authoritative live app/system appearance after launch. Existing code explicitly warns that AppleInterfaceStyle defaults may be stale and instead uses NSApp.effectiveAppearance through appearanceSyncColorSchemePreference. The resolver should receive that live preference from the app layer, or share equivalent logic and observation; merely re-calling current on a system transition can choose the wrong conditional branch. Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/ColorScheme/TerminalColorSchemePreference.swift:19-52; Sources/GhosttyConfig+AppearanceSync.swift:4-39.
- The result-bearing resolver still has an undefined outcome for a readable theme file that lacks a valid background or foreground. loadTheme treats any readable file as found, parse silently ignores unknown directives, and the two color parse flags can fail independently; the proposed outcomes name only resolved, unknown/unreadable, and unmatched-conditional cases. Define whether missing or malformed required colors produce a distinct failure and test it, otherwise defaults can still masquerade as a resolved page palette. Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:560-660,751-758,1089-1130.
- Opacity needs an explicit construction rule and test for custom theme files. The parser accepts background-opacity, while PanelAppearance.fromConfig composites that opacity and can choose a clear content background. The Catppuccin Latte test does not prove the stated opaque-page contract for an absolute-path theme containing background-opacity. Require the Markdown appearance builder to discard theme opacity and force an opaque background, with a regression test. Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:638-644; Sources/Panels/TerminalPanelView.swift:470-498.

**Changed from Round 2:** same verdict.

## Design Lead Revision (after Round 3)

### Rationale

1. **sol (blocking: wrong live scheme authority).** Accepted — a real factual error in my Round-2 wording. Verified: `TerminalColorSchemePreference.current` reads the `AppleInterfaceStyle` defaults, which `GhosttyConfig+AppearanceSync` explicitly documents as possibly stale after launch; the authoritative live source in system mode is `appearanceSyncColorSchemePreference` using `NSApp.effectiveAppearance` behind the `isApplicationFinishedLaunching` launch guard, falling back to a passed appearance and only then to defaults. Rewrote the conditional-authority decision to name that live resolution and to have the resolver receive the live preference from the app layer (the same value chrome uses), not read defaults itself. The transition test now says "live app/system preference, not the stale defaults snapshot".
2. **sol (needs_work: malformed/missing-color theme file is an undefined outcome).** Accepted. Verified `loadTheme` treats any readable file as "found", `parse` ignores unknown directives, and the two color parse flags fail independently. Added failure case (c): a readable file that did not parse a valid background or foreground. Success now requires both `hasParsedBackgroundColor` and `hasParsedForegroundColor`, so defaults can't masquerade as a resolved palette; added the malformed-file branch to the resolver-outcome test.
3. **sol (needs_work: theme-file opacity not handled).** Accepted. Verified `parse` accepts `background-opacity` and `fromConfig` composites it / may pick a clear content background. Added an explicit rule that the Markdown appearance builder discards theme-supplied opacity and forces opaque, plus a regression test using an absolute-path theme file with `background-opacity` (the bundled Latte case does not exercise this).
4. **astra (needs_work: same-name reload invalidation).** Accepted — astra flipped reject→needs_work with all three prior blockers marked Resolved, leaving this one. Verified `loadTheme` reads the file each call while settings reload avoids rewriting unchanged string defaults, so a file edited under an unchanged name+preference would leave the (name, preference) cache serving stale colors or a stale failure. Added a decision requiring `reload-config` to invalidate the per-name cache and re-resolve (successes and failures) via the committed-reload notification seam, plus a retained-viewer same-name reload test.
5. **astra (resolved x3) and sol (substantially addressed).** No further action; recorded as resolved in the trace.
6. **devils-advocate, simplifier, user (needs_work — all standing trade-offs).** Held, unchanged. Discoverability/dropdown is the tracked follow-on; partial theming (links/syntax) is Approach B, deferred by task constraint; markdown-only scope is fixed by the task; the runtime-warning feedback plus the validated Settings field is the chosen UX. These are acknowledged costs of a deliberately narrow first cut and have been explained consistently across rounds; none is a new defect.
7. **pragmatist (approve, confidence 1.0).** No change; confirmed the resolver, foreground contract, and authority fix as correct.

### Key Changes

- Replaced `TerminalColorSchemePreference.current` with the **live** `appearanceSyncColorSchemePreference` / `NSApp.effectiveAppearance` authority (defaults snapshot is stale after launch).
- Added resolver failure case (c): readable-but-malformed file with no valid background/foreground; success requires both parse flags.
- Added an explicit **discard-theme-opacity** rule + test.
- Added **same-name reload invalidation** via the committed-reload notification (invalidates cached successes and failures).

## Round 4: Deliberation (final round)

### Dr. Scrutiny (Devil's Advocate) (devils-advocate)
**Verdict:** needs_work | **Confidence:** 0.8

_The proposal has addressed some concerns but still has areas needing improvement._

- The proposal now explicitly handles invalid theme names and provides more specific guidance for implementation, which are positive changes.
- The trade-offs between approaches are more clearly discussed, helping to justify the chosen approach.
- However, the proposal still assumes user familiarity with Ghostty's theme naming conventions, which may not be the case for all users. More user-friendly alternatives should be considered.
- The potential performance implications of parsing theme files on change are not fully addressed. More testing and optimization may be needed.
- Discoverability of theme names is still a concern and should be tracked as a follow-on task.

**Changed from Round 3:** same verdict.

### The Pragmatist (pragmatist)
**Verdict:** approve | **Confidence:** 1.0

_The revisions have transformed an already strong plan into an exceptionally robust and de-risked specification by addressing critical edge cases and implementation details._

- The new result-bearing resolver is the correct architectural choice, converting potential silent failures with malformed or missing themes into testable, manageable outcomes.
- The plan now correctly handles complex real-world state interactions, such as live system appearance changes and same-name theme file reloads, which prevents a whole class of stale-state bugs.
- The explicit decisions to force opacity and precisely define the foreground CSS contract (using raw color and requiring explicit removal) demonstrate a meticulous attention to detail that prevents visual glitches.
- The comprehensive test suite is directly tied to the highest-risk implementation areas, including live state transitions and fallback logic, ensuring a clear and verifiable path to quality.
- The continued tight scoping—deferring a UI picker and full ANSI mapping—is a pragmatic decision that prioritizes delivering the core, high-value functionality reliably and efficiently.

**Changed from Round 3:** same verdict.

### The Simplifier (simplifier)
**Verdict:** needs_work | **Confidence:** 0.8

_The revised document addresses most concerns but could be further simplified._

- The addition of a result-bearing resolver is a good step forward.
- Changing the authority for conditional theme selection to the app/system preference is sound.
- The two-directional contract for foreground removal and the use of the theme's raw foreground color for prose text are well-considered.
- The requirement for a real host implementation for settings validation ensures proper testing.
- The decision to defer Approach B and maintain the current scope is reasonable given the constraints.
- The use of a text field for theme selection could be simplified further with a dropdown menu for predefined themes.
- Discoverability of theme names remains a follow-on item, which is acceptable but should be prioritized for user experience.
- The design could still benefit from a more thorough consideration of simplification opportunities, particularly in the settings UI and theme selection process.

**Changed from Round 3:** same verdict.

### The User (user)
**Verdict:** needs_work | **Confidence:** 0.9

_While technical fixes improve robustness, the core user experience issues of partial theming, discoverability, and feedback remain unaddressed, making its true value proposition weak for users._

- The most significant anti-goal of a 'half-themed' viewer persists, as links, syntax highlighting, and semantic accents will still not align with the chosen theme, leading to an inconsistent visual experience.
- Discoverability remains a critical user friction point; a text field for theme names without any form of list or picker ensures I'll have to go hunting for themes outside the application.
- Receiving a 'non-blocking runtime warning' for an unknown or unresolvable theme is still inadequate user feedback and will lead to confusion rather than clarity about configuration issues.
- The feature's continued limitation to only the Markdown viewer still creates inconsistent theming across different content types, diluting its overall impact and value.
- Despite the technical improvements, the 'why should I care' factor is still low due to the acknowledged incompleteness and setup friction, making it a low priority for adoption.

**Changed from Round 3:** same verdict.

### Astra (GPT-6, repo-grounded) (astra)
**Verdict:** approve | **Confidence:** 0.94

_My verdict changes from needs_work to approve: the revisions address the remaining reload concern and preserve the previously resolved contracts, with no new blocking impacts found._

- Resolved — Same-name reload invalidation now addresses the actual notification gap. Unchanged strings do not trigger a defaults write (Sources/KeyboardShortcutSettingsFileStore.swift:1527-1532), while the committed reload publishes ghosttyConfigDidReload after fanout (Sources/GhosttyTerminalView.swift:1982-1997). Explicit re-resolution and invalidation of both cached successes and failures, backed by a retained-viewer regression, adequately close my remaining concern.
- Resolved — The revised conditional-theme authority matches the live application implementation. GhosttyConfig.appearanceSyncColorSchemePreference prioritizes live application appearance in system mode after launch, then the passed appearance, then the configured preference (Sources/GhosttyConfig+AppearanceSync.swift:13-40). This avoids the terminal-derived scheme injected by PanelContentView (Sources/Panels/PanelContentView.swift:46-48). The mismatched-terminal and forced-dark cases test the relevant distinction.
- Resolved — The result-bearing resolver now distinguishes unusable palettes from successful loads without changing existing directive-loading semantics. loadTheme returns after reading a file without reporting whether colors parsed (Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1102-1131), and background/foreground parse flags are independently maintained (same file:630-660). Requiring both flags addresses malformed and incomplete files. Discarding theme opacity and explicitly forcing an opaque panel also addresses PanelAppearance's compositing and clear-background behavior (Sources/Panels/TerminalPanelView.swift:470-498).
- Resolved — The foreground and live-update contracts cover both directions of the state transition. The renderer currently only installs supplied CSS properties (Sources/Panels/MarkdownWebRenderer.swift:395-418), and typography adoption exits after a local override (Sources/Panels/MarkdownPanel.swift:277-291). Explicit foreground removal, independent theme adoption, and retained-WKWebView tests address those failure modes. The polarity test also reaches the actual highlight.js switching mechanism rather than merely inspecting a payload (Resources/markdown-viewer/shell.html:1952-1968).
- Resolved — Settings validation names both sides of the package boundary. CmuxSettingsUI has no CmuxTerminalCore dependency (Packages/macOS/CmuxSettingsUI/Package.swift:17-29); SettingsHostActions supplies the host-action contract (Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/SettingsHostActions.swift:38-56), and HostSettingsActions is its concrete application implementation (Sources/HostSettingsActions.swift:15-17). Requiring a real resolver-backed implementation, together with catalog and AppSection wiring, closes the previously missing integration.

**Changed from Round 3:** needs_work -> approve.

### Sol (GPT-5.6, repo-grounded) (sol)
**Verdict:** reject | **Confidence:** 0.96

_The prior technical concerns are addressed, but the revised design still omits required consumers of its SettingsHostActions change and leaves validation semantics unresolved._

- The prior concerns are adequately addressed: live scheme authority now matches Sources/GhosttyConfig+AppearanceSync.swift:4-39; malformed or missing colors are detectable through Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:74-99,630-660; and forced opacity avoids PanelAppearance.fromConfig behavior at Sources/Panels/TerminalPanelView.swift:470-488.
- Blocking interface omission: SettingsHostActions has three conformers, but the document names only HostSettingsActions. A required validation method also affects NoopSettingsHostActions at Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/SettingsHostActions.swift:650-670 and CountingMobilePairingHostActions at Packages/macOS/CmuxSettingsUI/Tests/CmuxSettingsUITests/CountingMobilePairingHostActions.swift:6-58. Without a default they stop compiling; with a default, the document's prohibition on default/no-op validation needs qualification and coverage ensuring the real host overrides it.
- Validation behavior remains unspecified. The existing Markdown text field writes every edit directly through DefaultsValueModel at Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift:524-535 and Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Bindings/DefaultsValueModel.swift:118-132, while SettingsHostActions is main-actor isolated at Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/SettingsHostActions.swift:47-49 and theme resolution performs synchronous file reads at Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:1102-1129. Specify whether validation blocks persistence or is advisory, when it runs, and an asynchronous draft/debounce or submit flow so typing cannot perform filesystem I/O on the main actor.
- Conditional validation also needs an explicit rule: appliedThemeName returns different outcomes per preference at Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig+AppliedTheme.swift:25-66. The document does not say whether Settings validates only the live side or every specified light/dark branch, so the same value could be accepted or rejected depending on the current appearance.

**Changed from Round 3:** same verdict.

## Convergence Trace

| Round | devils-advocate | pragmatist | simplifier | user | astra | sol | Consensus? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | needs_work | approve | needs_work | needs_work | reject | reject | no |
| 2 | needs_work | approve | needs_work | needs_work | reject | reject | no |
| 3 | needs_work | approve | needs_work | needs_work | needs_work | reject | no |
| 4 | needs_work | approve | needs_work | needs_work | approve | reject | no |

Direction: strictly improving. Both repo-grounded reviewers started at reject; astra cleared to approve by Round 4, sol narrowed from 7 points (R1) to 4 (R4) confined to the Settings-validation flow. pragmatist held approve throughout (0.95 -> 1.0). The three prompt-only needs_work verdicts never cited a new blocking issue after Round 1; their points are standing trade-offs. No round degraded quality.

## Final Synthesis

### Issues That Converged

- **Discoverability of theme names** (devils-advocate, simplifier, user, and pragmatist's lone caveat): a bare text field with no picker/list forces users to know Ghostty theme names. Agreed across rounds as the one non-blocking UX gap worth a tracked follow-on; not fixed in this cut by design.

### Issues That Were Resolved

- **Foreground never reaches rendered prose** (astra+sol, R1 blocking): fixed by the foreground contract (field + resolve arg + CSS variable, install/remove, raw color).
- **Wrong resolver / value grammar** (astra+sol, R1 blocking): fixed by using `loadTheme`/`appliedThemeName` and a result-bearing wrapper.
- **Unknown-theme fallback poisons the config snapshot** (sol, R1 blocking): fixed by resolving at appearance-build time, not via `logInvalid`.
- **Typography-observer reuse skips customized viewers** (astra+sol, R1): fixed by independent theme adoption outside the guard.
- **Settings package boundary** (astra+sol, R1): fixed by routing validation through `SettingsHostActions` with a real host implementation.
- **`loadTheme` returns Void; defaults masquerade as success** (astra+sol, R2 blocking): fixed by the result-bearing resolver keyed on parse flags.
- **Conditional-theme authority was terminal-derived** (astra, R2 blocking): fixed by the live app/system preference.
- **Foreground removal + contrast-correction conflict** (astra+sol, R2): fixed by two-directional contract and raw-color choice.
- **Malformed-color file undefined; theme opacity** (sol, R3): fixed by failure case (c) and the discard-opacity rule.
- **Same-name reload invalidation** (astra, R3): fixed via committed-reload notification invalidating cached successes and failures. astra confirmed all resolved at R4.

### Remaining Contentious Points

- **Settings-validation flow (sol, R4 reject, verified-plausible).** Three concrete, unaddressed sub-points, all bounded to the Settings seam, not the core architecture:
  1. `SettingsHostActions` has **three conformers** (`HostSettingsActions`, `NoopSettingsHostActions`, and the test double `CountingMobilePairingHostActions`). A required method breaks the latter two unless given a default; a default reopens the no-op-validation hole the design forbids. Needs a rule: provide a default that is safe, require the real host to override, and cover that the real path runs.
  2. **Validation timing / threading unspecified.** The Markdown text field writes every keystroke through `DefaultsValueModel`; `SettingsHostActions` is `@MainActor`; theme resolution does synchronous file reads. Naive per-keystroke validation would do filesystem I/O on the main actor. Needs an explicit advisory-vs-blocking decision and an async draft/debounce/submit flow.
  3. **Conditional validation rule undefined.** `appliedThemeName` yields different outcomes per preference, so `light:X,dark:Y` could validate-pass or -fail depending on current appearance. Needs a stated rule (validate the live side only, or every specified branch).
- **Partial theming / markdown-only scope / runtime-warning feedback (user, every round).** Deliberate, constraint-bound trade-offs (Approach B deferred; scope fixed to the Markdown viewer by the task). Acknowledged, not defects.
- **Dropdown vs text field (simplifier).** The dropdown IS the discoverability follow-on; held.

### Recommended Actions

1. Before implementation, extend the design's Settings section to answer sol's three R4 sub-points (conformer defaults + real-override coverage; async advisory validation flow off the main actor; conditional-side validation rule). These are small spec additions, not architectural changes.
2. File the discoverability follow-on (theme picker or a `cmux-settings list-markdown-themes`-style affordance) as a tracked task referenced from the design.
3. Otherwise the architecture is ready to build: both repo-grounded reviewers consider the core contracts correct and verified against the code.

### Deferred

- **Approach B** (16-color ANSI palette mapping onto GitHub CSS variables + highlight.js): links, syntax, and semantic accents stay stylesheet-driven. Deferred by constraint until Approach A is used and the stock accents are judged.
- **Theme discoverability UI** (picker / name list): tracked follow-on.
- **Theming other viewers** (diff, file preview, notes, agent chat): out of scope.

## Appendix: Final Revised Document

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
