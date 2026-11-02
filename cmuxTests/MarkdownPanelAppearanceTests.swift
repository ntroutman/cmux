import AppKit
import CmuxTerminalCore
import Foundation
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
    func absolutePathThemeFileWithBackgroundOpacityStillDrawsOpaque() throws {
        // The synthesized-alpha test above forces alpha onto `config.backgroundColor`;
        // a real theme file's `background-opacity` lands in the separate
        // `backgroundOpacity` field instead. This drives the *default* resolver
        // over an on-disk absolute-path theme so the whole parse-to-appearance
        // path proves the directive is discarded for the opaque Markdown page.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-md-theme-opacity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let themeFile = root.appendingPathComponent("translucent-theme", isDirectory: false)
        try "background = #eff1f5\nforeground = #4c4f69\nbackground-opacity = 0.5\n".write(
            to: themeFile,
            atomically: true,
            encoding: .utf8
        )

        // The parser must actually see the directive — otherwise this would
        // prove nothing about discarding it — so confirm the resolved config
        // carries a sub-1 opacity before checking the appearance drops it.
        guard case let .resolved(config) = GhosttyConfig.resolveTheme(
            themeFile.path,
            preferredColorScheme: .dark
        ) else {
            Issue.record("expected the absolute-path theme file to resolve")
            return
        }
        #expect(config.backgroundOpacity < 1)

        let result = MarkdownPanelAppearance.resolve(
            themeSetting: themeFile.path,
            terminalAppearance: darkTranslucentTerminalAppearance(),
            preferredColorScheme: .dark
        )

        #expect(result.source == .theme(name: themeFile.path))
        #expect(result.appearance.usesClearContentBackground == false)
        #expect(result.appearance.backgroundColor.alphaComponent == 1)
        #expect(result.appearance.backgroundColor == NSColor(hex: "#eff1f5"))
        #expect(result.proseForeground == NSColor(hex: "#4c4f69"))
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
    func cacheReResolvesWhenThemeGenerationChangesWithUnchangedOtherInputs() throws {
        // A same-name reload-config or appearance flip changes nothing in the
        // other inputs; the generation bump is the only signal that the disk
        // theme (or the live appearance) must be re-read. Without it folded into
        // the cache key the stale result would be returned.
        let terminal = darkTranslucentTerminalAppearance()
        let cache = MarkdownPanelAppearanceCache { _, _ in }
        var resolverCalls = 0
        let resolver: (String, GhosttyConfig.ColorSchemePreference) -> GhosttyThemeResolution = { _, _ in
            resolverCalls += 1
            return self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69")
        }

        _ = cache.appearance(themeSetting: "Custom", terminalAppearance: terminal, preferredColorScheme: .dark, themeGeneration: 0, resolver: resolver)
        // Repeated read at the same generation stays cached.
        _ = cache.appearance(themeSetting: "Custom", terminalAppearance: terminal, preferredColorScheme: .dark, themeGeneration: 0, resolver: resolver)
        #expect(resolverCalls == 1)

        // A bump re-resolves exactly once even though every other input is equal.
        _ = cache.appearance(themeSetting: "Custom", terminalAppearance: terminal, preferredColorScheme: .dark, themeGeneration: 1, resolver: resolver)
        _ = cache.appearance(themeSetting: "Custom", terminalAppearance: terminal, preferredColorScheme: .dark, themeGeneration: 1, resolver: resolver)
        #expect(resolverCalls == 2)
    }

    @Test
    func cacheWarnsAfterGenerationBumpMadeTheThemeUnresolvable() throws {
        // A reload-config that rewrites the theme file into an invalid state must
        // still warn once, even though the theme name (and every other input but
        // the generation) is unchanged.
        let terminal = darkTranslucentTerminalAppearance()
        var warnings: [GhosttyThemeResolutionFailure] = []
        let cache = MarkdownPanelAppearanceCache { _, failure in warnings.append(failure) }

        _ = cache.appearance(
            themeSetting: "Custom",
            terminalAppearance: terminal,
            preferredColorScheme: .dark,
            themeGeneration: 0
        ) { _, _ in self.resolvedTheme(background: "#eff1f5", foreground: "#4c4f69") }
        #expect(warnings.isEmpty)

        _ = cache.appearance(
            themeSetting: "Custom",
            terminalAppearance: terminal,
            preferredColorScheme: .dark,
            themeGeneration: 1
        ) { _, _ in .failed(.unknownTheme(name: "Custom")) }
        #expect(warnings.count == 1)
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
