import Foundation

/// The colors and the stable hash used to give things a color the user never picked, so
/// that each one is easy to tell apart and keeps its color across app launches.
///
/// Shared by the remote-host origin color (``RemoteHostColorRegistry``, which keeps
/// forwarding statics so its callers are unchanged) and the automatic workspace color.
/// The automatic group color carries a private copy of the same constants and pins the
/// hash of a fixed string in a test, so consolidating it onto this type later cannot
/// recolor anything.
enum WorkspaceDistinguishingPalette {
    /// Sixteen soft colors picked for telling hosts apart, rather than borrowed from the
    /// workspace tab palette, whose dark reds and magentas collapse into each other once the
    /// sidebar rail brightens them (two pairs there differ by under 5). As the rail draws them,
    /// every pair differs by at least 11 in OKLab (x100), colors that are neighbors in this order
    /// differ by at least 26, so a host bumped to the next slot by a collision lands on a clearly
    /// different color, each differs from the grey sidebar (#A9A9A9) by at least 15, and from
    /// cmux's built-in blue accent by at least 12. Custom accents are user-controlled and may
    /// intentionally match a palette color, so no universal contrast guarantee is possible for
    /// arbitrary custom accents. `RemoteHostColorRegistryTests` checks those floors.
    static let colors: [String] = [
        "#B1A2FA", // violet
        "#E7BB4E", // gold
        "#9B577B", // mauve
        "#75D1A3", // mint
        "#77779E", // slate
        "#FF945A", // tangerine
        "#A8EAF6", // sky
        "#F06C7F", // coral
        "#DDE2BB", // butter
        "#E18DCD", // pink
        "#8A9E2D", // olive
        "#A963C7", // purple
        "#9B6F0D", // ochre
        "#FFDAFF", // lilac
        "#259E6A", // green
        "#9E5131", // rust
    ]

    /// Stable FNV-1a/64 hash of a string — deterministic across processes (unlike
    /// `Hasher`), so a starting color doesn't change between app launches.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3 // FNV prime
        }
        return hash
    }
}
