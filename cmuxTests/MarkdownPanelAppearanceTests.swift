import AppKit
import CmuxTerminalCore
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite(.timeLimit(.minutes(1)))
struct MarkdownPanelAppearanceTests {
    /// A translucent dark terminal appearance that a resolved light theme must
    /// override for background/foreground while keeping divider and overlay.
    private func darkTranslucentTerminalAppearance() -> PanelAppearance {
        PanelAppearance(
            backgroundColor: NSColor(hex: "#24273a")!.withAlphaComponent(0.85),
            foregroundColor: NSColor(hex: "#cad3f5")!,
            dividerColor: Color(nsColor: NSColor(hex: "#5b6078")!),
            unfocusedOverlayNSColor: NSColor(hex: "#181926")!,
            unfocusedOverlayOpacity: 0.35,
            usesClearContentBackground: true
        )
    }

    /// A `.resolved` outcome carrying `background`/`foreground` parsed from valid
    /// directives, mirroring what `GhosttyConfig.resolveTheme` returns.
    private func resolvedTheme(
        background: String,
        foreground: String,
        backgroundAlpha: CGFloat = 1
    ) -> GhosttyThemeResolution {
        var config = GhosttyConfig()
        config.parse("background = \(background)\nforeground = \(foreground)")
        if backgroundAlpha < 1 {
            config.backgroundColor = config.backgroundColor.withAlphaComponent(backgroundAlpha)
        }
        return .resolved(config)
    }

    @Test
    func resolvedLightThemeOverridesDarkTranslucentTerminalOpaquelyKeepingDivider() throws {
        let terminal = darkTranslucentTerminalAppearance()
        let result = MarkdownPanelAppearance.resolve(
            themeSetting: "Catppuccin Latte",
            terminalAppearance: terminal,
            preferredColorScheme: .dark
        ) { _, _ in
            // Catppuccin Latte-like: light page (#eff1f5), dark text (#4c4f69).
            self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69")
        }

        #expect(result.source == .theme(name: "Catppuccin Latte"))
        // Light theme background wins over the dark terminal.
        #expect(result.appearance.backgroundColor.isLightColor)
        // Opaque page regardless of the translucent terminal.
        #expect(result.appearance.usesClearContentBackground == false)
        #expect(result.appearance.backgroundColor.alphaComponent == 1)
        // Divider and overlay stay the terminal's so splits look uniform.
        #expect(result.appearance.dividerColor == terminal.dividerColor)
        #expect(result.appearance.unfocusedOverlayNSColor == terminal.unfocusedOverlayNSColor)
        #expect(result.appearance.unfocusedOverlayOpacity == terminal.unfocusedOverlayOpacity)
        // The raw theme foreground reaches the prose channel unmodified.
        #expect(result.proseForeground == NSColor(hex: "#4c4f69"))
    }

    @Test
    func resolvedThemeWithTranslucentBackgroundStillDrawsOpaque() throws {
        let result = MarkdownPanelAppearance.resolve(
            themeSetting: "Translucent",
            terminalAppearance: darkTranslucentTerminalAppearance(),
            preferredColorScheme: .dark
        ) { _, _ in
            self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69", backgroundAlpha: 0.8)
        }

        #expect(result.appearance.usesClearContentBackground == false)
        #expect(result.appearance.backgroundColor.alphaComponent == 1)
    }

    @Test
    func failedResolutionFallsBackToTerminalAppearanceWithoutProseForeground() throws {
        let terminal = darkTranslucentTerminalAppearance()
        let result = MarkdownPanelAppearance.resolve(
            themeSetting: "Nonexistent Theme",
            terminalAppearance: terminal,
            preferredColorScheme: .dark
        ) { _, _ in
            .failed(.unknownTheme(name: "Nonexistent Theme"))
        }

        #expect(result.source == .terminal)
        #expect(result.proseForeground == nil)
        // The fallback carries the failure so the cache can warn once on the
        // transition; the appearance otherwise matches the terminal.
        #expect(result == MarkdownPanelAppearance(
            appearance: terminal,
            proseForeground: nil,
            source: .terminal,
            resolutionFailure: .unknownTheme(name: "Nonexistent Theme")
        ))
    }

    @Test
    func nilThemeSettingFollowsTerminalUnchanged() throws {
        let terminal = darkTranslucentTerminalAppearance()
        var resolverCalled = false
        let result = MarkdownPanelAppearance.resolve(
            themeSetting: nil,
            terminalAppearance: terminal,
            preferredColorScheme: .dark
        ) { _, _ in
            resolverCalled = true
            return .failed(.unknownTheme(name: ""))
        }

        #expect(resolverCalled == false)
        #expect(result.source == .terminal)
        #expect(result.proseForeground == nil)
        #expect(result.appearance.backgroundColor == terminal.backgroundColor)
        #expect(result.appearance.usesClearContentBackground == terminal.usesClearContentBackground)
    }

    @Test
    func conditionalThemePicksSideFromAppAppearanceNotTerminalLuminance() throws {
        // The terminal is dark, but the live app appearance is light. A
        // conditional theme must follow the app, so the resolver must be called
        // with `.light`.
        let preference = MarkdownPanelAppearance.preferredColorScheme(
            defaults: lightSystemModeDefaults(),
            isApplicationFinishedLaunching: { true },
            liveEffectiveAppearance: { NSAppearance(named: .aqua) }
        )
        #expect(preference == .light)

        var recordedPreference: GhosttyConfig.ColorSchemePreference?
        _ = MarkdownPanelAppearance.resolve(
            themeSetting: "light:Catppuccin Latte,dark:Catppuccin Macchiato",
            terminalAppearance: darkTranslucentTerminalAppearance(),
            preferredColorScheme: preference
        ) { _, preferred in
            recordedPreference = preferred
            return self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69")
        }
        #expect(recordedPreference == .light)
    }

    @Test
    func noLiveAppearanceReadBeforeDidFinishLaunching() throws {
        var liveReadCount = 0
        // System mode is the only mode that ever consults the live appearance,
        // so the pre-launch guard is meaningful only here.
        _ = MarkdownPanelAppearance.preferredColorScheme(
            defaults: lightSystemModeDefaults(),
            isApplicationFinishedLaunching: { false },
            liveEffectiveAppearance: {
                liveReadCount += 1
                return NSAppearance(named: .aqua)
            }
        )

        #expect(liveReadCount == 0)
    }

    // MARK: - Cache (resolution off the render path, one-shot warning)

    @Test
    func cacheResolvesOnceForRepeatedReadsWithUnchangedInputs() throws {
        let terminal = darkTranslucentTerminalAppearance()
        let cache = MarkdownPanelAppearanceCache { _, _ in }
        var resolverCalls = 0

        // The view reads the appearance several times per body pass and re-runs
        // body on typing/focus/find; identical inputs must not touch the
        // disk-backed resolver again.
        for _ in 0..<10 {
            _ = cache.appearance(
                themeSetting: "Catppuccin Latte",
                terminalAppearance: terminal,
                preferredColorScheme: .dark
            ) { _, _ in
                resolverCalls += 1
                return self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69")
            }
        }

        #expect(resolverCalls == 1)
    }

    @Test
    func cacheReResolvesWhenAnyInputChanges() throws {
        let terminal = darkTranslucentTerminalAppearance()
        let cache = MarkdownPanelAppearanceCache { _, _ in }
        var resolverCalls = 0
        let resolver: (String, GhosttyConfig.ColorSchemePreference) -> GhosttyThemeResolution = { _, _ in
            resolverCalls += 1
            return self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69")
        }

        _ = cache.appearance(themeSetting: "Latte", terminalAppearance: terminal, preferredColorScheme: .dark, resolver: resolver)
        // Theme setting change.
        _ = cache.appearance(themeSetting: "Mocha", terminalAppearance: terminal, preferredColorScheme: .dark, resolver: resolver)
        // Preferred color scheme change.
        _ = cache.appearance(themeSetting: "Mocha", terminalAppearance: terminal, preferredColorScheme: .light, resolver: resolver)
        // Terminal appearance identity change.
        var otherTerminal = terminal
        otherTerminal = PanelAppearance(
            backgroundColor: NSColor(hex: "#000000")!,
            foregroundColor: terminal.foregroundColor,
            dividerColor: terminal.dividerColor,
            unfocusedOverlayNSColor: terminal.unfocusedOverlayNSColor,
            unfocusedOverlayOpacity: terminal.unfocusedOverlayOpacity,
            usesClearContentBackground: terminal.usesClearContentBackground
        )
        _ = cache.appearance(themeSetting: "Mocha", terminalAppearance: otherTerminal, preferredColorScheme: .light, resolver: resolver)

        #expect(resolverCalls == 4)
    }

    @Test
    func cacheWarnsOncePerDistinctFailureNotPerRead() throws {
        let terminal = darkTranslucentTerminalAppearance()
        var warnings: [GhosttyThemeResolutionFailure] = []
        let cache = MarkdownPanelAppearanceCache { _, failure in warnings.append(failure) }

        // A permanently unresolvable theme read many times (body re-evaluates on
        // every keystroke) must warn exactly once, not once per read.
        for _ in 0..<10 {
            _ = cache.appearance(
                themeSetting: "Nonexistent",
                terminalAppearance: terminal,
                preferredColorScheme: .dark
            ) { _, _ in .failed(.unknownTheme(name: "Nonexistent")) }
        }
        #expect(warnings.count == 1)

        // A transition to a different failure warns again.
        _ = cache.appearance(
            themeSetting: "AlsoBad",
            terminalAppearance: terminal,
            preferredColorScheme: .dark
        ) { _, _ in .failed(.unknownTheme(name: "AlsoBad")) }
        #expect(warnings.count == 2)

        // Recovering to a resolved theme, then failing with the same cause as
        // before, warns again (the failure is no longer the last-warned one).
        _ = cache.appearance(
            themeSetting: "Latte",
            terminalAppearance: terminal,
            preferredColorScheme: .dark
        ) { _, _ in self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69") }
        _ = cache.appearance(
            themeSetting: "AlsoBad",
            terminalAppearance: terminal,
            preferredColorScheme: .dark
        ) { _, _ in .failed(.unknownTheme(name: "AlsoBad")) }
        #expect(warnings.count == 3)
    }

    @Test
    func resolveDoesNotLogWarningItself() throws {
        // `resolve` is pure: the failure is carried in `resolutionFailure` for
        // the cache to warn on a transition, so `resolve` can stay off the
        // warning path even if called per render.
        let result = MarkdownPanelAppearance.resolve(
            themeSetting: "Nonexistent",
            terminalAppearance: darkTranslucentTerminalAppearance(),
            preferredColorScheme: .dark
        ) { _, _ in .failed(.unknownTheme(name: "Nonexistent")) }

        #expect(result.source == .terminal)
        #expect(result.resolutionFailure == .unknownTheme(name: "Nonexistent"))
    }

    /// A defaults suite in system appearance mode, so `preferredColorScheme`
    /// consults the live/system appearance rather than an explicit light/dark
    /// mode.
    private func lightSystemModeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MarkdownPanelAppearanceTests.\(UUID().uuidString)")!
        defaults.set("system", forKey: "appearanceMode")
        return defaults
    }
}
