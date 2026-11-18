import Foundation

/// Assigns a key a palette color by a hash that is stable across processes.
struct HashedPaletteAssigner: WorkspaceAutoColorAssigning {
    let palette: [String]

    init(palette: [String] = WorkspaceDistinguishingPalette.colors) {
        self.palette = palette
    }

    func colorHex(forKey key: String) -> String? {
        guard !palette.isEmpty else { return nil }
        return palette[Int(WorkspaceDistinguishingPalette.stableHash(key) % UInt64(palette.count))]
    }
}
