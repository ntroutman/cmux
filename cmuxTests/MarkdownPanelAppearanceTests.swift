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
        #expect(result == MarkdownPanelAppearance(
            appearance: terminal,
            proseForeground: nil,
            source: .terminal
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

    /// A defaults suite in system appearance mode, so `preferredColorScheme`
    /// consults the live/system appearance rather than an explicit light/dark
    /// mode.
    private func lightSystemModeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MarkdownPanelAppearanceTests.\(UUID().uuidString)")!
        defaults.set("system", forKey: "appearanceMode")
        return defaults
    }
}
