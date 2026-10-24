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

    /// Where a `MarkdownPanelAppearance` got its colors.
    enum Source: Equatable {
        /// `markdown.theme` was unset/empty, or resolution failed; the viewer
        /// follows the terminal.
        case terminal
        /// `markdown.theme` resolved to the named theme.
        case theme(name: String)
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
    /// appearance and logs one warning naming the cause.
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
                source: .theme(name: rawValue)
            )
        case let .failed(failure):
            logger.warning("markdown.theme '\(rawValue, privacy: .public)' did not resolve: \(String(describing: failure), privacy: .public); following the terminal appearance")
            return MarkdownPanelAppearance(
                appearance: terminalAppearance,
                proseForeground: nil,
                source: .terminal
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
            && lhs.proseForeground == rhs.proseForeground
            && lhs.appearance.backgroundColor == rhs.appearance.backgroundColor
            && lhs.appearance.foregroundColor == rhs.appearance.foregroundColor
            && lhs.appearance.dividerColor == rhs.appearance.dividerColor
            && lhs.appearance.unfocusedOverlayNSColor == rhs.appearance.unfocusedOverlayNSColor
            && lhs.appearance.unfocusedOverlayOpacity == rhs.appearance.unfocusedOverlayOpacity
            && lhs.appearance.usesClearContentBackground == rhs.appearance.usesClearContentBackground
    }
}

private let logger = Logger(subsystem: "com.cmuxterm.app", category: "MarkdownPanelAppearance")
