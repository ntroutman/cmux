import AppKit
import CmuxTerminalCore
import os

/// The appearance a Markdown viewer paints with, derived from `markdown.theme`
/// independently of the terminal it shares a split with.
///
/// When `markdown.theme` resolves, Markdown panels get the theme's own
/// background and foreground (the page draws opaque, discarding any theme
/// `background-opacity`) while the divider and unfocused-overlay values stay the
/// terminal's so every pane in a split keeps a uniform chrome. On any resolution
/// failure the panel falls back to the terminal appearance with a logged warning
/// rather than a half-applied theme. Conditional `light:X,dark:Y` themes pick a
/// side from the live app/system appearance (`preferredColorScheme`), never the
/// terminal's luminance. See the design spec's "Resolution", "Opacity",
/// "Color-scheme authority", and "Unknown / unresolvable".
struct MarkdownPanelAppearance: Equatable {
    /// The panel appearance to paint with — the theme's colors when resolved,
    /// the terminal's otherwise. Divider and unfocused-overlay values are always
    /// the terminal's so splits stay uniform.
    let appearance: PanelAppearance
    /// The theme's raw foreground color for the rendered prose, or `nil` when
    /// following the terminal (the web renderer then leaves GitHub's stylesheet
    /// in charge of body text). This is the unmodified theme `foreground`, not
    /// the contrast-corrected chrome color in `appearance.foregroundColor`.
    let proseForeground: NSColor?
    /// Whether the appearance came from a resolved theme or the terminal.
    let source: Source
    /// The failure that forced the terminal fallback, or `nil` when the viewer
    /// follows the terminal by choice (unset/empty `markdown.theme`) or a theme
    /// resolved. ``MarkdownPanelAppearanceCache`` logs this once per distinct
    /// `(themeSetting, failure)` rather than on every render.
    let resolutionFailure: GhosttyThemeResolutionFailure?

    /// Where a `MarkdownPanelAppearance` got its colors.
    enum Source: Equatable {
        /// `markdown.theme` was unset/empty, or resolution failed; the viewer
        /// follows the terminal.
        case terminal
        /// `markdown.theme` resolved to the named theme.
        case theme(name: String)
    }

    init(
        appearance: PanelAppearance,
        proseForeground: NSColor?,
        source: Source,
        resolutionFailure: GhosttyThemeResolutionFailure? = nil
    ) {
        self.appearance = appearance
        self.proseForeground = proseForeground
        self.source = source
        self.resolutionFailure = resolutionFailure
    }

    /// The default theme resolver: ``CmuxTerminalCore/GhosttyConfig/resolveTheme(_:preferredColorScheme:environment:bundleResourceURL:)``
    /// with its environment and bundle defaults. A wrapping closure is required
    /// because `resolveTheme` carries extra defaulted parameters the injected
    /// resolver type does not expose.
    static let defaultResolver: (String, GhosttyConfig.ColorSchemePreference) -> GhosttyThemeResolution = {
        rawValue, preferredColorScheme in
        GhosttyConfig.resolveTheme(rawValue, preferredColorScheme: preferredColorScheme)
    }

    /// Builds the viewer appearance for `themeSetting` over `terminalAppearance`.
    ///
    /// `nil`/empty follows the terminal unchanged with no prose foreground. A
    /// resolved theme supplies an opaque theme background, a contrast-corrected
    /// chrome foreground, and the raw theme foreground as `proseForeground`,
    /// while copying the terminal's divider and unfocused-overlay values and
    /// forcing the page opaque. A resolution failure falls back to the terminal
    /// appearance and carries the failure in `resolutionFailure` so the caller
    /// can warn once on a state transition instead of on every render.
    ///
    /// This is a pure function: it reads the theme (through `resolver`) and maps
    /// the outcome to an appearance without logging. ``MarkdownPanelAppearanceCache``
    /// drives the one-shot warning and keeps this resolution — which hits disk
    /// through the default resolver — off the SwiftUI render path.
    static func resolve(
        themeSetting: String?,
        terminalAppearance: PanelAppearance,
        preferredColorScheme: GhosttyConfig.ColorSchemePreference,
        resolver: (String, GhosttyConfig.ColorSchemePreference) -> GhosttyThemeResolution = defaultResolver
    ) -> MarkdownPanelAppearance {
        guard let rawValue = themeSetting, !rawValue.isEmpty else {
            return MarkdownPanelAppearance(
                appearance: terminalAppearance,
                proseForeground: nil,
                source: .terminal
            )
        }

        switch resolver(rawValue, preferredColorScheme) {
        case let .resolved(config):
            let themeBackground = config.backgroundColor.withAlphaComponent(1)
            let appearance = PanelAppearance(
                backgroundColor: themeBackground,
                foregroundColor: cmuxReadableForegroundNSColor(
                    preferred: config.foregroundColor,
                    on: themeBackground
                ),
                dividerColor: terminalAppearance.dividerColor,
                unfocusedOverlayNSColor: terminalAppearance.unfocusedOverlayNSColor,
                unfocusedOverlayOpacity: terminalAppearance.unfocusedOverlayOpacity,
                usesClearContentBackground: false
            )
            return MarkdownPanelAppearance(
                appearance: appearance,
                proseForeground: config.foregroundColor,
                source: .theme(name: rawValue),
                resolutionFailure: nil
            )
        case let .failed(failure):
            return MarkdownPanelAppearance(
                appearance: terminalAppearance,
                proseForeground: nil,
                source: .terminal,
                resolutionFailure: failure
            )
        }
    }

    /// The color-scheme side a conditional `markdown.theme` picks, via the same
    /// launch-guarded shape the terminal reload path uses
    /// (`GhosttyConfig.appearanceSyncColorSchemePreference`). The app appearance
    /// is authoritative, never the terminal's luminance, and no live
    /// `NSApp.effectiveAppearance` read happens before `didFinishLaunching`.
    /// Parameters mirror the helper's seams so the call site stays a one-liner
    /// and both the pre-launch and conditional paths are testable.
    static func preferredColorScheme(
        defaults: UserDefaults = .standard,
        isApplicationFinishedLaunching: () -> Bool = AppIconLaunchState.isApplicationFinishedLaunching,
        liveEffectiveAppearance: () -> NSAppearance? = {
            guard Thread.isMainThread else { return nil }
            return NSApp?.effectiveAppearance
        }
    ) -> GhosttyConfig.ColorSchemePreference {
        GhosttyConfig.appearanceSyncColorSchemePreference(
            passedAppearance: nil,
            defaults: defaults,
            isApplicationFinishedLaunching: isApplicationFinishedLaunching,
            liveEffectiveAppearance: liveEffectiveAppearance
        ).preference
    }

    static func == (lhs: MarkdownPanelAppearance, rhs: MarkdownPanelAppearance) -> Bool {
        lhs.source == rhs.source
            && lhs.resolutionFailure == rhs.resolutionFailure
            && lhs.proseForeground == rhs.proseForeground
            && lhs.appearance.backgroundColor == rhs.appearance.backgroundColor
            && lhs.appearance.foregroundColor == rhs.appearance.foregroundColor
            && lhs.appearance.dividerColor == rhs.appearance.dividerColor
            && lhs.appearance.unfocusedOverlayNSColor == rhs.appearance.unfocusedOverlayNSColor
            && lhs.appearance.unfocusedOverlayOpacity == rhs.appearance.unfocusedOverlayOpacity
            && lhs.appearance.usesClearContentBackground == rhs.appearance.usesClearContentBackground
    }
}

/// Memoizes ``MarkdownPanelAppearance/resolve(themeSetting:terminalAppearance:preferredColorScheme:resolver:)``
/// so the disk-backed theme resolution runs only when its inputs change, never
/// on every SwiftUI render pass.
///
/// `MarkdownPanelView.body` re-evaluates on typing, focus/find changes, and
/// content refresh, reading the appearance several times per pass. The terminal
/// `PanelAppearance` it composes over is a pre-computed value built off the hot
/// path; this cache keeps the viewer's resolution off that path too. Given the
/// same `(themeSetting, terminalAppearance, preferredColorScheme)` it returns
/// the stored result and does no I/O; on a change it resolves once and, on a
/// transition into a new failure, logs exactly one warning (so a permanently
/// unresolvable `markdown.theme` does not spam the log per frame).
final class MarkdownPanelAppearanceCache {
    private struct Inputs: Equatable {
        let themeSetting: String?
        let terminalAppearance: PanelAppearance
        let preferredColorScheme: GhosttyConfig.ColorSchemePreference
    }

    private var inputs: Inputs?
    private var cached: MarkdownPanelAppearance?
    /// The failure last warned about, so the same unresolvable value is logged
    /// once rather than on every re-resolution.
    private var warnedFailure: GhosttyThemeResolutionFailure?
    /// The warning sink, injectable so tests can count one-shot warnings; the
    /// default logs to os_log.
    private let warn: (String, GhosttyThemeResolutionFailure) -> Void

    init(warn: @escaping (String, GhosttyThemeResolutionFailure) -> Void = MarkdownPanelAppearanceCache.logWarning) {
        self.warn = warn
    }

    func appearance(
        themeSetting: String?,
        terminalAppearance: PanelAppearance,
        preferredColorScheme: GhosttyConfig.ColorSchemePreference,
        resolver: (String, GhosttyConfig.ColorSchemePreference) -> GhosttyThemeResolution = MarkdownPanelAppearance.defaultResolver
    ) -> MarkdownPanelAppearance {
        let requested = Inputs(
            themeSetting: themeSetting,
            terminalAppearance: terminalAppearance,
            preferredColorScheme: preferredColorScheme
        )
        if inputs == requested, let cached {
            return cached
        }

        let resolved = MarkdownPanelAppearance.resolve(
            themeSetting: themeSetting,
            terminalAppearance: terminalAppearance,
            preferredColorScheme: preferredColorScheme,
            resolver: resolver
        )

        if let failure = resolved.resolutionFailure, failure != warnedFailure {
            warn(themeSetting ?? "", failure)
        }
        warnedFailure = resolved.resolutionFailure

        inputs = requested
        cached = resolved
        return resolved
    }

    static func logWarning(_ themeSetting: String, _ failure: GhosttyThemeResolutionFailure) {
        logger.warning("markdown.theme '\(themeSetting, privacy: .public)' did not resolve: \(String(describing: failure), privacy: .public); following the terminal appearance")
    }
}

private let logger = Logger(subsystem: "com.cmuxterm.app", category: "MarkdownPanelAppearance")
