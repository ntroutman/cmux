@testable import CmuxComputerUse
import CmuxSettingsUI
import CmuxTerminalCore
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The host override the Markdown Viewer Theme row reaches resolves the name
/// against Ghostty themes and, for a conditional, validates every named side,
/// not just the live one (spec
/// `docs/superpowers/specs/2026-10-23-markdown-viewer-theme-design.md`,
/// "Validation rules"). The resolver reads `GHOSTTY_RESOURCES_DIR` at call
/// time, so these tests point it at a fixture `themes/` directory; they are
/// serialized because that environment variable is process-wide.
@MainActor
@Suite("Host markdown theme validation", .serialized)
struct HostSettingsActionsMarkdownThemeTests {
    private static let bundledName = "Catppuccin Latte"
    /// A name no search path can resolve, including the real app bundle.
    /// Regenerated per test run: `resolveTheme` searches real host/user theme
    /// paths beyond the fixture dir (e.g. `~/.config/ghostty/themes`), so a
    /// fixed literal could collide with a theme that happens to exist locally
    /// and pass spuriously. A fresh UUID cannot, matching the resolver's own
    /// `GhosttyConfigThemeResolutionTests`.
    private let unknownName = "cmux-test-nonexistent-theme-\(UUID().uuidString)"

    /// Builds a fixture resources root with a single resolvable theme file and
    /// points `GHOSTTY_RESOURCES_DIR` at it for the duration of `body`.
    private func withFixtureThemes<R>(_ body: (HostSettingsActions) throws -> R) throws -> R {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-host-md-theme-\(UUID().uuidString)", isDirectory: true)
        let themesDir = root.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        try "background = #eff1f5\nforeground = #4c4f69\n".write(
            to: themesDir.appendingPathComponent(Self.bundledName, isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let previous = ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"]
        setenv("GHOSTTY_RESOURCES_DIR", root.path, 1)
        defer {
            if let previous {
                setenv("GHOSTTY_RESOURCES_DIR", previous, 1)
            } else {
                unsetenv("GHOSTTY_RESOURCES_DIR")
            }
        }

        let host = HostSettingsActions(
            configFileURL: root.appendingPathComponent("cmux.json"),
            computerUseRuntimeService: ComputerUseRuntimeService(),
            browserDataImportCoordinator: BrowserDataImportCoordinator(),
            runComputerUseOnboardingAction: { _ in }
        )
        return try body(host)
    }

    @Test func emptyNameIsValid() throws {
        try withFixtureThemes { host in
            #expect(host.validateMarkdownThemeName("") == .valid)
            #expect(host.validateMarkdownThemeName("   ") == .valid)
        }
    }

    @Test func bundledNameIsValid() throws {
        try withFixtureThemes { host in
            #expect(host.validateMarkdownThemeName(Self.bundledName) == .valid)
        }
    }

    @Test func unknownNameIsInvalid() throws {
        try withFixtureThemes { host in
            guard case let .invalid(message) = host.validateMarkdownThemeName(unknownName) else {
                Issue.record("expected .invalid for an unknown theme name")
                return
            }
            #expect(message.contains(unknownName))
        }
    }

    @Test func conditionalReportsUnknownNonLiveSide() throws {
        try withFixtureThemes { host in
            // The live side resolves; only the dark side is unknown. Validation
            // must still fail and name the dark side.
            let value = "light:\(Self.bundledName),dark:\(unknownName)"
            guard case let .invalid(message) = host.validateMarkdownThemeName(value) else {
                Issue.record("expected .invalid naming the unresolvable dark side")
                return
            }
            #expect(message.contains(unknownName))
            #expect(!message.contains(Self.bundledName))
        }
    }

    /// A one-sided conditional names no theme for the opposite appearance, so
    /// that appearance falls back to the terminal at runtime — exactly the
    /// break the user cannot see. Validation must report it invalid and name
    /// the absent side (here `dark`), not pass because only the named `light`
    /// side happens to resolve.
    @Test func conditionalReportsAbsentDarkSide() throws {
        try withFixtureThemes { host in
            guard case let .invalid(message) = host.validateMarkdownThemeName("light:\(Self.bundledName)") else {
                Issue.record("expected .invalid for a conditional with no dark side")
                return
            }
            #expect(message.contains("dark"))
        }
    }

    /// Symmetric to `conditionalReportsAbsentDarkSide`: a `dark:`-only value
    /// leaves the light appearance unthemed and must be reported naming `light`.
    @Test func conditionalReportsAbsentLightSide() throws {
        try withFixtureThemes { host in
            guard case let .invalid(message) = host.validateMarkdownThemeName("dark:\(Self.bundledName)") else {
                Issue.record("expected .invalid for a conditional with no light side")
                return
            }
            #expect(message.contains("light"))
        }
    }
}
