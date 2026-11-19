import Foundation
import Testing

import CmuxWorkspaces

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The effective group color resolver: manual, then config, then a color
/// derived from the group's name, then neutral. Slot expectations below were
/// computed from FNV-1a/64 by hand, so a change to the hash or the probe order
/// fails here instead of silently recoloring every automatic group.
@MainActor
@Suite("Workspace group automatic color resolver")
struct WorkspaceGroupAutoColorResolverTests {

    private let palette = ["#C0392B", "#2980B9", "#27AE60", "#8E44AD"]

    private func makeGroup(
        name: String,
        id: UUID = UUID(),
        customColor: String? = nil
    ) -> WorkspaceGroup {
        WorkspaceGroup(
            id: id,
            name: name,
            isCollapsed: false,
            isPinned: false,
            anchorWorkspaceId: UUID(),
            customColor: customColor,
            iconSymbol: nil
        )
    }

    private func resolve(
        _ groups: [WorkspaceGroup],
        config: [UUID: String] = [:],
        autoPalette: [String]
    ) -> [UUID: String] {
        VerticalTabsSidebar.groupColorHexByGroupId(
            groups: groups,
            configColor: { config[$0.id] },
            autoPalette: autoPalette
        )
    }

    // MARK: Hash

    @Test func hashMatchesHardCodedFNV1a64() {
        // Also the value RemoteHostColorRegistry.stableHash("cmux") returns
        // today; pinned as a literal so consolidating the two hashes later
        // cannot change group colors unnoticed.
        #expect(VerticalTabsSidebar.fnv1a64("cmux") == 0x1E15_4C91_2400_A9D0)
        #expect(VerticalTabsSidebar.fnv1a64("") == 0xCBF2_9CE4_8422_2325)
    }

    // MARK: Precedence

    @Test func manualBeatsConfigBeatsAutomatic() {
        let manual = makeGroup(name: "Delta", customColor: "#111111")
        let config = makeGroup(name: "Gamma")
        let automatic = makeGroup(name: "Kappa")

        let map = resolve(
            [manual, config, automatic],
            config: [manual.id: "#222222", config.id: "#333333"],
            autoPalette: palette
        )

        #expect(map[manual.id] == "#111111")
        #expect(map[config.id] == "#333333")
        // Kappa hashes to slot 0.
        #expect(map[automatic.id] == palette[0])
    }

    @Test func emptyAutoPaletteLeavesUncoloredGroupOut() {
        let group = makeGroup(name: "Delta")
        #expect(resolve([group], autoPalette: [])[group.id] == nil)
    }

    @Test func sameInputResolvesToSameOutput() {
        let groups = ["Delta", "Gamma", "Kappa", "Web", "web"].map { makeGroup(name: $0) }
        let first = resolve(groups, autoPalette: palette)
        let second = resolve(groups, autoPalette: palette)
        #expect(first == second)
        #expect(first.count == groups.count)
    }

    // MARK: Collisions

    @Test func collidingNamesTakeAdjacentSlotsInNameOrder() {
        // Both names hash to slot 1 of four; pass them in reverse name order
        // so the sort, not the input order, decides who probes.
        let epsilon = makeGroup(name: "Epsilon")
        let delta = makeGroup(name: "Delta")

        let map = resolve([epsilon, delta], autoPalette: palette)

        #expect(map[delta.id] == palette[1])
        #expect(map[epsilon.id] == palette[2])
    }

    @Test func identicalNamesBreakTiesById() {
        let lowId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highId = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let high = makeGroup(name: "Delta", id: highId)
        let low = makeGroup(name: "Delta", id: lowId)

        let map = resolve([high, low], autoPalette: palette)

        #expect(map[lowId] == palette[1])
        #expect(map[highId] == palette[2])
    }

    @Test func manualColorMatchingPaletteOccupiesItsSlot() {
        let manual = makeGroup(name: "Gamma", customColor: palette[1])
        let delta = makeGroup(name: "Delta")

        let map = resolve([manual, delta], autoPalette: palette)

        #expect(map[delta.id] == palette[2])
    }

    @Test func lowercaseConfigColorMatchingPaletteOccupiesItsSlot() {
        let configured = makeGroup(name: "Gamma")
        let delta = makeGroup(name: "Delta")

        let map = resolve(
            [configured, delta],
            config: [configured.id: palette[1].lowercased()],
            autoPalette: palette
        )

        #expect(map[configured.id] == palette[1])
        #expect(map[delta.id] == palette[2])
    }

    @Test func fullPaletteFallsBackToHashedStart() {
        let twoColors = Array(palette.prefix(2))
        let first = makeGroup(name: "Gamma", customColor: twoColors[0])
        let second = makeGroup(name: "Kappa", customColor: twoColors[1])
        // Delta hashes to slot 1 of two.
        let delta = makeGroup(name: "Delta")

        let map = resolve([first, second, delta], autoPalette: twoColors)

        #expect(map[delta.id] == twoColors[1])
    }

    // MARK: Malformed colors

    @Test(arguments: ["nope", "+12345"])
    func malformedManualColorFallsToConfig(manualColor: String) {
        let group = makeGroup(name: "Delta", customColor: manualColor)
        let map = resolve([group], config: [group.id: "#333333"], autoPalette: palette)
        #expect(map[group.id] == "#333333")
    }

    @Test func malformedConfigColorFallsToAutomatic() {
        let group = makeGroup(name: "Delta")
        let map = resolve([group], config: [group.id: "#12"], autoPalette: palette)
        #expect(map[group.id] == palette[1])
    }

    @Test func malformedManualColorFallsToConfigWithAutomaticOff() {
        let group = makeGroup(name: "Delta", customColor: "nope")
        let map = resolve([group], config: [group.id: "#333333"], autoPalette: [])
        #expect(map[group.id] == "#333333")
    }

    @Test func malformedEverywhereWithAutomaticOffStaysOut() {
        let group = makeGroup(name: "Delta", customColor: "nope")
        let map = resolve([group], config: [group.id: "#12"], autoPalette: [])
        #expect(map[group.id] == nil)
    }

    @Test func lowercaseManualColorResolvesUppercased() {
        let group = makeGroup(name: "Delta", customColor: "#c0392b")
        #expect(resolve([group], autoPalette: [])[group.id] == "#C0392B")
    }

    // MARK: Names

    @Test func namesDifferingOnlyInCaseResolveDeterministically() {
        // Both hash to slot 1; "W" sorts before "w" in scalar order.
        let lower = makeGroup(name: "web")
        let upper = makeGroup(name: "Web")

        let map = resolve([lower, upper], autoPalette: palette)

        #expect(map[upper.id] == palette[1])
        #expect(map[lower.id] == palette[2])
    }

    @Test func nonASCIINamesResolveDeterministically() {
        // Both hash to slot 1; "C" sorts before the CJK scalar.
        let cjk = makeGroup(name: "日本")
        let accented = makeGroup(name: "Café")

        let map = resolve([cjk, accented], autoPalette: palette)

        #expect(map[accented.id] == palette[1])
        #expect(map[cjk.id] == palette[2])
    }

    @Test func longNameResolvesDeterministically() {
        let group = makeGroup(name: String(repeating: "x", count: 500))
        #expect(resolve([group], autoPalette: palette)[group.id] == palette[1])
    }
}
