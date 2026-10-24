import AppKit
import Testing
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite
final class MarkdownForegroundRenderingTests {
    /// GitHub's stock `--fgColor-default` for each polarity, as the browser
    /// serializes an opaque color from `getComputedStyle`. Dark `#e6edf3` and
    /// light `#1f2328` live in Resources/markdown-viewer/github-markdown.css.
    private static let stockDarkColor = "rgb(230, 237, 243)"
    private static let stockLightColor = "rgb(31, 35, 40)"

    @Test
    func suppliedForegroundColorsBodyTextInTheRetainedWebView() async throws {
        try await withLoadedMarkdownShell(isDark: true) { webView in
            try await applyThemePayload(foreground: "rgb(10, 200, 30)", in: webView)
            let color = try await bodyTextColor(in: webView)
            #expect(color == "rgb(10, 200, 30)")
        }
    }

    @Test
    func clearingForegroundReturnsBodyTextToGitHubStockColor() async throws {
        try await withLoadedMarkdownShell(isDark: true) { webView in
            try await applyThemePayload(foreground: "rgb(10, 200, 30)", in: webView)
            #expect(try await bodyTextColor(in: webView) == "rgb(10, 200, 30)")

            try await applyThemePayload(foreground: nil, in: webView)
            #expect(try await bodyTextColor(in: webView) == Self.stockDarkColor)
        }
    }

    @Test
    func polarityFlipMovesFgColorAndHighlightSheetsTogether() async throws {
        try await withLoadedMarkdownShell(isDark: true) { webView in
            let dark = try await polaritySnapshot(darkAqua: true, in: webView)
            #expect(dark.bodyColor == Self.stockDarkColor)
            #expect(dark.lightSheetDisabled == true)
            #expect(dark.darkSheetDisabled == false)

            let light = try await polaritySnapshot(darkAqua: false, in: webView)
            #expect(light.bodyColor == Self.stockLightColor)
            #expect(light.lightSheetDisabled == false)
            #expect(light.darkSheetDisabled == true)
        }
    }

    // MARK: Helpers

    /// Mirrors the CSS-variable payload MarkdownWebRenderer.applyTheme emits:
    /// a supplied foreground sets `--fgColor-default`; an unset one removes a
    /// previously installed override from the same element.
    private func applyThemePayload(foreground: String?, in webView: WKWebView) async throws {
        let setOrRemove: String
        if let foreground {
            let data = try JSONSerialization.data(withJSONObject: [foreground])
            let literal = try #require(String(data: data, encoding: .utf8))
            setOrRemove = "content.style.setProperty('--fgColor-default', \(literal)[0]);"
        } else {
            setOrRemove = "content.style.removeProperty('--fgColor-default');"
        }
        _ = try await webView.evaluateJavaScript(
            """
            (function() {
              var content = document.getElementById('content');
              if (!content) { return false; }
              \(setOrRemove)
              return true;
            })();
            """
        )
    }

    private func bodyTextColor(in webView: WKWebView) async throws -> String {
        let result = try await webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('.markdown-body')).color"
        )
        return try #require(result as? String)
    }

    private struct PolaritySnapshot {
        let bodyColor: String
        let lightSheetDisabled: Bool
        let darkSheetDisabled: Bool
    }

    private func polaritySnapshot(darkAqua: Bool, in webView: WKWebView) async throws -> PolaritySnapshot {
        webView.appearance = NSAppearance(named: darkAqua ? .darkAqua : .aqua)
        // Setting webView.appearance propagates to the web content's
        // prefers-color-scheme media query asynchronously. Poll until the query
        // settles to the requested polarity, then read. The production renderer
        // reacts to the same matchMedia change; __cmuxApplyTheme toggles the
        // highlight.js sheets off that query, and GitHub's stylesheet selects
        // --fgColor-default off the same query, so body color and sheet
        // enabled-state move together once it flips.
        // __cmuxApplyTheme derives isDark from the shell's own matchMedia
        // object, which can lag a freshly created one by a turn. Re-run it each
        // iteration and accept only once the sheet state it installed agrees
        // with the requested polarity, so the test observes the production
        // effect rather than racing the media-query propagation.
        for _ in 0..<100 {
            let result = try await webView.evaluateJavaScript(
                """
                (function(wantDark) {
                  if (window.__cmuxApplyTheme) { window.__cmuxApplyTheme(); }
                  var light = document.getElementById('hljs-light');
                  var dark = document.getElementById('hljs-dark');
                  var lightDisabled = !!(light && light.disabled);
                  var darkDisabled = !!(dark && dark.disabled);
                  if (lightDisabled !== wantDark || darkDisabled !== !wantDark) { return null; }
                  return {
                    bodyColor: getComputedStyle(document.querySelector('.markdown-body')).color,
                    lightSheetDisabled: lightDisabled,
                    darkSheetDisabled: darkDisabled
                  };
                })(\(darkAqua ? "true" : "false"));
                """
            )
            if let raw = result as? [String: Any] {
                return PolaritySnapshot(
                    bodyColor: try #require(raw["bodyColor"] as? String),
                    lightSheetDisabled: try #require(raw["lightSheetDisabled"] as? Bool),
                    darkSheetDisabled: try #require(raw["darkSheetDisabled"] as? Bool)
                )
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw PolarityError.mediaQueryDidNotSettle(darkAqua: darkAqua)
    }

    private enum PolarityError: Error {
        case mediaQueryDidNotSettle(darkAqua: Bool)
    }

    private func withLoadedMarkdownShell<T>(
        isDark: Bool,
        _ body: (WKWebView) async throws -> T
    ) async throws -> T {
        let markdownURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-markdown-foreground-\(UUID().uuidString).md")
        let frame = NSRect(x: 0, y: 0, width: 1_000, height: 600)
        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        defer {
            webView.navigationDelegate = nil
            window.close()
        }

        let loadDelegate = MarkdownForegroundShellLoadDelegate()
        webView.navigationDelegate = loadDelegate
        try await loadDelegate.load(
            MarkdownViewerAssets.shared.shellHTML(isDark: isDark),
            in: webView,
            baseURL: markdownURL
        )
        return try await body(webView)
    }
}

private final class MarkdownForegroundShellLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}
