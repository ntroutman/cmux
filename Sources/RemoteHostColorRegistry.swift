import Foundation

/// Assigns each remote destination a color from ``hostPalette`` so servers are easy
/// to tell apart at a glance, and the same destination shows the same color in every
/// open window for the life of the app session. The palette and hash live in
/// ``WorkspaceDistinguishingPalette``, shared with the automatic workspace color. Gated by the
/// `remoteTmux.beta.originColors.enabled` flag at the call sites.
///
/// Keyed by the host's `destination` STRING (the ssh alias or `user@host` — the
/// "host name" the user typed), NOT the port/identity-specific ``connectionHash``.
/// That deliberately keeps one color per destination string across ports, at the
/// cost that two spellings of the same box (`box` vs `user@box`) are treated as
/// two hosts. This is a recognizability hint, not an identity — collisions are
/// expected once there are more hosts than palette colors.
///
/// Assignment rule ("hash the host name to a color; on a collision take the next
/// color"):
/// 1. `destination` is hashed with a STABLE FNV-1a string hash (not Swift's
///    per-process randomized `Hasher`) to a starting palette index — so a host
///    that never collides lands on the same color across app launches too.
/// 2. Linear-probe forward from that start to the first slot not already held by a
///    different host — the "collision → next color" behavior.
/// 3. If every slot is taken (more hosts than palette colors), fall back to the
///    hashed start and let colors repeat.
/// 4. The chosen slot is cached per destination, so repeat lookups from any window
///    return the same color.
///
/// Consistency guarantee: within one running session the cache gives a destination
/// one color in every window. Across restarts a lone host is stable (step 1), but
/// two hosts that collide on the same start can swap colors depending on which was
/// seen first. Assignments are in-memory and the cache never shrinks (stale hosts
/// keep reserving a slot); durable persistence and eviction are deliberate
/// follow-ups.
/// One instance is owned by ``RemoteTmuxController`` (itself owned by `AppDelegate`
/// at the app seam) and reached through it, so assignments stay consistent
/// process-wide without an ambient global. Tests construct their own instance with
/// an injected `slotCount` to exercise the probing deterministically.
@MainActor
final class RemoteHostColorRegistry {
    /// The shared ``WorkspaceDistinguishingPalette/colors``; kept so existing callers and the
    /// palette-floor tests keep compiling against the registry.
    static let hostPalette = WorkspaceDistinguishingPalette.colors

    /// Number of palette slots to assign over. Defaults to ``hostPalette``'s count;
    /// tests inject other counts to exercise the probing.
    let slotCount: Int

    /// destination → assigned palette slot (the stable per-host cache).
    private(set) var slotByHost: [String: Int] = [:]
    /// palette slot → destination that holds it (drives collision probing).
    private var hostBySlot: [Int: String] = [:]

    init(slotCount: Int? = nil) {
        self.slotCount = min(max(0, slotCount ?? Self.hostPalette.count), Self.hostPalette.count)
    }

    /// The palette slot for `destination`, assigning one on first sight (stable
    /// hash start + linear probe over free slots) and caching it. `nil` only when
    /// there are no slots.
    @discardableResult
    func slot(for destination: String) -> Int? {
        guard slotCount > 0 else { return nil }
        if let existing = slotByHost[destination] { return existing }
        let start = Int(Self.stableHash(destination) % UInt64(slotCount))
        var chosen = start
        for offset in 0 ..< slotCount {
            let idx = (start + offset) % slotCount
            if hostBySlot[idx] == nil {
                chosen = idx
                break
            }
        }
        slotByHost[destination] = chosen
        hostBySlot[chosen] = destination
        return chosen
    }

    /// The color hex for `destination`'s assigned slot. `nil` when the palette is empty.
    func colorHex(for destination: String) -> String? {
        guard let slot = slot(for: destination), slot < Self.hostPalette.count else { return nil }
        return Self.hostPalette[slot]
    }

    /// Forwards to ``WorkspaceDistinguishingPalette/stableHash(_:)``, the FNV-1a/64 hash that
    /// keeps a host's starting color the same across app launches.
    static func stableHash(_ string: String) -> UInt64 {
        WorkspaceDistinguishingPalette.stableHash(string)
    }
}
