import AppKit
import CmuxFoundation
import Foundation
import Testing
@testable import CmuxTerminalCore

/// Coverage for the result-bearing theme resolver that the Markdown appearance
/// builder and Settings validation consume (see spec
/// `docs/superpowers/specs/2026-10-23-markdown-viewer-theme-design.md`,
/// "Resolution — result-bearing contract" and "Validation rules").
///
/// `GhosttyConfig.loadTheme` returns `Void` and leaves the non-optional default
/// colors in place on failure, so a caller cannot tell a loaded theme from a
/// silent miss. `GhosttyConfig.resolveTheme` names the outcome instead.
@Suite struct GhosttyConfigThemeResolutionTests {
    /// Writes a theme file named `name` with the given contents into a fresh
    /// temp `themes/` directory and returns the resources root to pass via
    /// `GHOSTTY_RESOURCES_DIR` (the loader appends `themes/<name>`).
    private func makeThemesRoot(
        _ name: String,
        contents: String
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-theme-resolution-\(UUID().uuidString)", isDirectory: true)
        let themesDir = root.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        try contents.write(
            to: themesDir.appendingPathComponent(name, isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @Test func resolvableThemeCarriesParsedColors() throws {
        let root = try makeThemesRoot(
            "Latte",
            contents: """
            background = #eff1f5
            foreground = #4c4f69
            """
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = GhosttyConfig.resolveTheme(
            "Latte",
            preferredColorScheme: .light,
            environment: ["GHOSTTY_RESOURCES_DIR": root.path],
            bundleResourceURL: nil
        )

        guard case let .resolved(config) = outcome else {
            Issue.record("expected .resolved, got \(outcome)")
            return
        }
        #expect(config.hasParsedBackgroundColor)
        #expect(config.hasParsedForegroundColor)
        #expect(config.backgroundColor.hexString().caseInsensitiveCompare("#EFF1F5") == .orderedSame)
        #expect(config.foregroundColor.hexString().caseInsensitiveCompare("#4C4F69") == .orderedSame)
    }

    @Test func resolvedOutcomeReportsNoFailure() throws {
        // Guards against reintroducing an `Equatable` that treats every success
        // as unequal: a resolved outcome must be distinguishable from any
        // failure through `failure == nil`, not through a broken `==`.
        let root = try makeThemesRoot(
            "Latte",
            contents: "background = #eff1f5\nforeground = #4c4f69"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = GhosttyConfig.resolveTheme(
            "Latte",
            preferredColorScheme: .light,
            environment: ["GHOSTTY_RESOURCES_DIR": root.path],
            bundleResourceURL: nil
        )

        #expect(outcome.failure == nil)
    }

    @Test func unknownThemeNameFails() throws {
        // Empty themes dir so no candidate file exists for the name. The name
        // must be collision-resistant: `themeSearchPaths` also walks host
        // fallbacks (`/Applications/Ghostty.app/...`, `~/.config/ghostty/...`,
        // `~/Library/Application Support/...`) that `GHOSTTY_RESOURCES_DIR` does
        // not isolate, so a fixed name could match a real host theme file and
        // flip this all-paths-must-miss assertion. A per-run UUID cannot.
        let missingName = "cmux-missing-\(UUID().uuidString)"
        let root = try makeThemesRoot("Present", contents: "background = #000000\nforeground = #ffffff")
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = GhosttyConfig.resolveTheme(
            missingName,
            preferredColorScheme: .light,
            environment: ["GHOSTTY_RESOURCES_DIR": root.path],
            bundleResourceURL: nil
        )

        #expect(outcome.failure == .unknownTheme(name: missingName))
    }

    @Test func unmatchedConditionalSideFails() throws {
        let root = try makeThemesRoot(
            "Latte",
            contents: "background = #eff1f5\nforeground = #4c4f69"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // `light:Latte` names no dark side, so the dark scheme matches nothing.
        let outcome = GhosttyConfig.resolveTheme(
            "light:Latte",
            preferredColorScheme: .dark,
            environment: ["GHOSTTY_RESOURCES_DIR": root.path],
            bundleResourceURL: nil
        )

        #expect(outcome.failure == .unmatchedConditionalSide(preferred: .dark))
    }

    @Test func readableFileWithNoColorDirectivesReportsMissingColors() throws {
        let root = try makeThemesRoot(
            "PaletteOnly",
            contents: """
            palette = 0=#000000
            palette = 1=#ff0000
            """
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = GhosttyConfig.resolveTheme(
            "PaletteOnly",
            preferredColorScheme: .light,
            environment: ["GHOSTTY_RESOURCES_DIR": root.path],
            bundleResourceURL: nil
        )

        guard case let .failed(failure) = outcome,
              case let .missingColors(path) = failure else {
            Issue.record("expected .missingColors, got \(outcome)")
            return
        }
        #expect(path.hasSuffix("themes/PaletteOnly"))
    }

    @Test func fileSettingRealDefaultColorsViaDirectivesIsResolved() throws {
        // The default colors reached through valid directives, not inference:
        // success is decided by the parse flags, not the color values.
        let root = try makeThemesRoot(
            "DefaultsAsDirectives",
            contents: """
            background = #282C34
            foreground = #FFFFFF
            """
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = GhosttyConfig.resolveTheme(
            "DefaultsAsDirectives",
            preferredColorScheme: .dark,
            environment: ["GHOSTTY_RESOURCES_DIR": root.path],
            bundleResourceURL: nil
        )

        guard case let .resolved(config) = outcome else {
            Issue.record("expected .resolved, got \(outcome)")
            return
        }
        #expect(config.hasParsedBackgroundColor)
        #expect(config.hasParsedForegroundColor)
        #expect(config.backgroundColor.hexString().caseInsensitiveCompare("#282C34") == .orderedSame)
        #expect(config.foregroundColor.hexString().caseInsensitiveCompare("#FFFFFF") == .orderedSame)
    }

    @Test func unreadableAbsolutePathFallsThroughToSearchLoopLikeLoadTheme() throws {
        // `loadTheme` takes the absolute branch only when the path is absolute
        // AND readable; an unreadable absolute path falls through to the
        // candidate x search-path loop (GhosttyConfig.swift loadTheme). The
        // resolver must match that exactly rather than short-circuit to
        // `.unknownTheme`. Here the configured value is an absolute path that
        // does not exist, but a readable file is staged at the fallthrough
        // location `GHOSTTY_RESOURCES_DIR/themes/<thatAbsolutePath>` (the loop
        // interpolates the whole name into `themes/<name>`), so a faithful
        // resolver — and `loadTheme` — find it.
        let missingAbsolutePath = "/cmux-nonexistent-\(UUID().uuidString)/Themed"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-theme-resolution-\(UUID().uuidString)", isDirectory: true)
        let fallthroughFile = root
            .appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent(missingAbsolutePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: fallthroughFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "background = #123456\nforeground = #abcdef"
            .write(to: fallthroughFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = ["GHOSTTY_RESOURCES_DIR": root.path]
        let outcome = GhosttyConfig.resolveTheme(
            missingAbsolutePath,
            preferredColorScheme: .dark,
            environment: environment,
            bundleResourceURL: nil
        )

        guard case let .resolved(config) = outcome else {
            Issue.record("expected .resolved from the fallthrough search, got \(outcome)")
            return
        }
        #expect(config.backgroundColor.hexString().caseInsensitiveCompare("#123456") == .orderedSame)
        #expect(config.foregroundColor.hexString().caseInsensitiveCompare("#ABCDEF") == .orderedSame)

        // The terminal path agrees: `loadTheme` loads the same colors, proving
        // the resolver did not diverge from it on the unreadable-absolute case.
        var loaded = GhosttyConfig()
        loaded.loadTheme(
            missingAbsolutePath,
            environment: environment,
            bundleResourceURL: nil,
            preferredColorScheme: .dark
        )
        #expect(loaded.backgroundColor.hexString().caseInsensitiveCompare("#123456") == .orderedSame)
        #expect(loaded.foregroundColor.hexString().caseInsensitiveCompare("#ABCDEF") == .orderedSame)
    }

    @Test func conditionalThemeSidesListsEveryNamedSide() {
        #expect(GhosttyConfig.conditionalThemeSides("light:A,dark:B") == ["A", "B"])
    }

    @Test func conditionalThemeSidesOnBareNameIsSingleton() {
        #expect(GhosttyConfig.conditionalThemeSides("Catppuccin Latte") == ["Catppuccin Latte"])
    }
}
