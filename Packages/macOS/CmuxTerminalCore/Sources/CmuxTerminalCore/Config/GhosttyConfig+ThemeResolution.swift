public import Foundation

/// The outcome of resolving a Ghostty `theme` value to a parsed config.
///
/// ``GhosttyConfig/loadTheme(_:environment:bundleResourceURL:preferredColorScheme:)``
/// returns `Void` and leaves the non-optional default colors (`#282C34` /
/// `#FFFFFF`) in place on any miss, so a caller cannot tell a loaded theme from
/// a silent failure. The Markdown appearance builder and Settings validation
/// both need an explicit outcome; ``GhosttyConfig/resolveTheme(_:preferredColorScheme:environment:bundleResourceURL:)``
/// supplies one. See the design spec's "Resolution — result-bearing contract".
public enum GhosttyThemeResolution {
    /// The theme file was found, parsed, and supplied both colors the viewer
    /// needs; the carried config holds the parsed `backgroundColor` and
    /// `foregroundColor`.
    case resolved(GhosttyConfig)
    /// The theme could not be resolved; the case names the cause.
    case failed(GhosttyThemeResolutionFailure)

    /// The failure cause when this is `.failed`, else `nil`.
    ///
    /// `GhosttyThemeResolution` deliberately is not `Equatable`: its `.resolved`
    /// payload is a `GhosttyConfig`, which is not `Equatable`, so a synthesized
    /// or hand-written `==` could never compare two successes meaningfully and
    /// would silently return `false` for `.resolved`-vs-`.resolved` — breaking
    /// reflexivity on a public type. The `.failed` cause is the only part worth
    /// comparing, and ``GhosttyThemeResolutionFailure`` is `Equatable`, so
    /// callers (Settings validation, the Markdown appearance builder, tests)
    /// branch on `.resolved`/`.failed` and compare this cause directly.
    public var failure: GhosttyThemeResolutionFailure? {
        guard case let .failed(failure) = self else { return nil }
        return failure
    }
}

/// Why ``GhosttyConfig/resolveTheme(_:preferredColorScheme:environment:bundleResourceURL:)``
/// could not produce a resolved config.
public enum GhosttyThemeResolutionFailure: Equatable {
    /// No file was found for the resolved name across the search paths.
    case unknownTheme(name: String)
    /// The value named no side for `preferred` (e.g. `light:X` under `.dark`).
    case unmatchedConditionalSide(preferred: GhosttyConfig.ColorSchemePreference)
    /// A readable theme file at `path` that parsed no valid background or
    /// foreground directive, so it would otherwise masquerade as the defaults.
    case missingColors(path: String)
}

extension GhosttyConfig {
    /// Resolves `rawValue` (which may carry conditional `light:.../dark:...`
    /// tokens) for `preferredColorScheme` into an explicit outcome, reusing the
    /// same file search as ``loadTheme(_:environment:bundleResourceURL:preferredColorScheme:)``
    /// without reimplementing it.
    ///
    /// Resolution mirrors `loadTheme`: ``appliedThemeName(from:preferredColorScheme:)``
    /// first (a `nil` there is an unmatched conditional side), then a *readable*
    /// absolute path, then — including when an absolute path is unreadable —
    /// ``themeNameCandidates(from:)`` over ``themeSearchPaths(forThemeName:environment:bundleResourceURL:)``.
    /// A file is parsed into a fresh ``GhosttyConfig``; success requires both
    /// ``hasParsedBackgroundColor`` and ``hasParsedForegroundColor`` — never the
    /// mere presence of the default colors — otherwise `.missingColors`.
    public static func resolveTheme(
        _ rawValue: String,
        preferredColorScheme: ColorSchemePreference,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourceURL: URL? = Bundle.main.resourceURL
    ) -> GhosttyThemeResolution {
        guard let resolvedThemeName = appliedThemeName(
            from: rawValue,
            preferredColorScheme: preferredColorScheme
        ) else {
            return .failed(.unmatchedConditionalSide(preferred: preferredColorScheme))
        }

        // Match `loadTheme` exactly: the absolute branch is taken only when the
        // path is absolute AND readable; an unreadable absolute path falls
        // through to the candidate/search loop below rather than short-circuiting.
        let expandedThemePath = NSString(string: resolvedThemeName).expandingTildeInPath
        if (expandedThemePath as NSString).isAbsolutePath,
           let contents = try? String(contentsOfFile: expandedThemePath, encoding: .utf8) {
            return outcome(forParsedContents: contents, path: expandedThemePath)
        }

        for candidateName in themeNameCandidates(from: resolvedThemeName) {
            for path in themeSearchPaths(
                forThemeName: candidateName,
                environment: environment,
                bundleResourceURL: bundleResourceURL
            ) {
                if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    return outcome(forParsedContents: contents, path: path)
                }
            }
        }

        return .failed(.unknownTheme(name: resolvedThemeName))
    }

    /// Parses `contents` into a fresh config and decides success by the parse
    /// flags, not the resulting color values (a file that sets the real default
    /// colors via valid directives is still a success).
    private static func outcome(
        forParsedContents contents: String,
        path: String
    ) -> GhosttyThemeResolution {
        var config = GhosttyConfig()
        config.parse(contents)
        guard config.hasParsedBackgroundColor, config.hasParsedForegroundColor else {
            return .failed(.missingColors(path: path))
        }
        return .resolved(config)
    }

    /// The theme name on each side a raw `theme` value names, so Settings can
    /// validate every branch rather than only the live one.
    ///
    /// A conditional `light:X,dark:Y` yields `[X, Y]` (in appearance order,
    /// light then dark); a bare `name` yields `[name]`. This resolves each side
    /// through ``appliedThemeName(from:preferredColorScheme:)`` so a one-sided
    /// value such as `light:X` lists only the side it actually names.
    public static func conditionalThemeSides(_ rawValue: String) -> [String] {
        var sides: [String] = []
        for scheme in [ColorSchemePreference.light, .dark] {
            if let name = appliedThemeName(from: rawValue, preferredColorScheme: scheme),
               !sides.contains(name) {
                sides.append(name)
            }
        }
        return sides
    }
}
