import AppKit
import Foundation
import SwiftUI
import Testing

import CmuxFoundation
import CmuxSettings
import CmuxWorkspaces

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Plumbing coverage for the group-header band facts this leaf carries from the
/// render context to both renderers' header inputs (cmux-ta4.10). No renderer
/// paints yet; these pin the inputs and the header's own height equivalence.
@MainActor
@Suite("Sidebar group header divider plumbing")
struct SidebarGroupHeaderDividerPlumbingTests {
    private static let groupId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private static let anchorId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    // MARK: Band facts

    @Test
    func bandFactsCarryColorNeutralAndNilOff() {
        let blue = "#4f8fe6"
        let colored = VerticalTabsSidebar.sidebarGroupHeaderBandFacts(
            showsGroupDividers: true, isFirstRenderedRow: false, groupColorHex: blue,
            fontScale: 1, colorScheme: .dark, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        )
        let neutral = VerticalTabsSidebar.sidebarGroupHeaderBandFacts(
            showsGroupDividers: true, isFirstRenderedRow: false, groupColorHex: nil,
            fontScale: 1, colorScheme: .dark, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        )
        let off = VerticalTabsSidebar.sidebarGroupHeaderBandFacts(
            showsGroupDividers: false, isFirstRenderedRow: false, groupColorHex: blue,
            fontScale: 1, colorScheme: .dark, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        )

        // The colored band is the shared resolver's output for that color.
        #expect(colored.bandStyle == sidebarGroupBandStyle(
            groupColorHex: blue, colorScheme: .dark, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        ))
        // No group color yields the neutral band, distinct from the colored one.
        #expect(neutral.bandStyle == sidebarGroupBandStyle(
            groupColorHex: nil, colorScheme: .dark, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        ))
        #expect(colored.bandStyle != neutral.bandStyle)
        // The setting off suppresses the band entirely.
        #expect(off.bandStyle == nil)
    }

    @Test
    func topGapIsZeroForFirstRenderedRowAndMetricOtherwise() {
        let first = VerticalTabsSidebar.sidebarGroupHeaderBandFacts(
            showsGroupDividers: true, isFirstRenderedRow: true, groupColorHex: nil,
            fontScale: 2, colorScheme: .light, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        )
        let later = VerticalTabsSidebar.sidebarGroupHeaderBandFacts(
            showsGroupDividers: true, isFirstRenderedRow: false, groupColorHex: nil,
            fontScale: 2, colorScheme: .light, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        )
        let off = VerticalTabsSidebar.sidebarGroupHeaderBandFacts(
            showsGroupDividers: false, isFirstRenderedRow: false, groupColorHex: nil,
            fontScale: 2, colorScheme: .light, increaseContrast: false,
            brightenInDarkMode: true, over: nil
        )
        #expect(first.topGap == 0)
        #expect(later.topGap == SidebarWorkspaceGroupHeaderMetrics.baseTopGap * 2)
        #expect(off.topGap == 0)
    }

    // MARK: Header height equivalence

    @Test
    func recolorDoesNotRemeasureHeaderHeight() {
        let env = makeEnvironment()
        let blue = "#4f8fe6"
        let green = "#3fae6a"
        let base = makeModel(
            tintHex: blue,
            bandStyle: sidebarGroupBandStyle(
                groupColorHex: blue, colorScheme: .light, increaseContrast: false,
                brightenInDarkMode: true, over: nil
            ),
            multiSelectionBackgroundStyle: SidebarWorkspaceRowBackgroundStyle(
                color: NSColor(hex: blue), opacity: 0.2
            ),
            topGap: 10, isFirstRenderedRow: false, showsGroupDividers: true
        )
        let recolored = makeModel(
            tintHex: green,
            bandStyle: sidebarGroupBandStyle(
                groupColorHex: green, colorScheme: .light, increaseContrast: false,
                brightenInDarkMode: true, over: nil
            ),
            multiSelectionBackgroundStyle: SidebarWorkspaceRowBackgroundStyle(
                color: NSColor(hex: green), opacity: 0.2
            ),
            topGap: 10, isFirstRenderedRow: false, showsGroupDividers: true
        )

        // Precondition: a recolor genuinely changes the model, so the
        // height-equivalence below is doing real work, not comparing equals.
        #expect(
            makeConfig(base, env).hasEquivalentContent(to: makeConfig(recolored, env)) == false
        )
        // The height cache must survive a recolor (paint-only change).
        #expect(makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(recolored, env)))
    }

    @Test
    func gapFirstRowSettingAndNameChangesRemeasureHeader() {
        let env = makeEnvironment()
        let base = makeModel(topGap: 10, isFirstRenderedRow: false, showsGroupDividers: true)
        let differentGap = makeModel(topGap: 0, isFirstRenderedRow: false, showsGroupDividers: true)
        let differentFirstRow = makeModel(topGap: 10, isFirstRenderedRow: true, showsGroupDividers: true)
        let differentSetting = makeModel(topGap: 10, isFirstRenderedRow: false, showsGroupDividers: false)
        let differentName = makeModel(name: "Renamed", topGap: 10, isFirstRenderedRow: false, showsGroupDividers: true)

        #expect(
            makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(differentGap, env)) == false
        )
        #expect(
            makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(differentFirstRow, env)) == false
        )
        #expect(
            makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(differentSetting, env)) == false
        )
        #expect(
            makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(differentName, env)) == false
        )
    }

    // MARK: Group color inputs

    @Test
    func colorInputsCarryManualColorSeparatelyFromEffectiveColor() {
        let manual = "#C0392B"
        let configColor = "#3FAE6A"
        let manualGroup = makeGroup(customColor: manual)
        let configOnlyGroup = makeGroup(customColor: nil)

        let manualInputs = VerticalTabsSidebar.sidebarGroupHeaderColorInputs(
            group: manualGroup,
            groupColorHexByGroupId: [manualGroup.id: manual],
            brightenInDarkMode: true
        )
        let configOnlyInputs = VerticalTabsSidebar.sidebarGroupHeaderColorInputs(
            group: configOnlyGroup,
            groupColorHexByGroupId: [configOnlyGroup.id: configColor],
            brightenInDarkMode: false
        )

        #expect(manualInputs.tintHex == manual)
        #expect(manualInputs.customColorHex == manual)
        #expect(manualInputs.brightenInDarkMode)
        // A config color paints the header but is not a manual choice, so the
        // menu's Clear Color and checkmark must not see it.
        #expect(configOnlyInputs.tintHex == configColor)
        #expect(configOnlyInputs.customColorHex == nil)
        #expect(configOnlyInputs.brightenInDarkMode == false)
    }

    @Test
    func manualColorAndBrightenAreHeightNeutral() {
        let env = makeEnvironment()
        let base = makeModel(customColorHex: nil, brightenInDarkMode: true)
        let manuallyColored = makeModel(customColorHex: "#C0392B", brightenInDarkMode: true)
        let notBrightened = makeModel(customColorHex: nil, brightenInDarkMode: false)

        #expect(
            makeConfig(base, env).hasEquivalentContent(to: makeConfig(manuallyColored, env)) == false
        )
        #expect(
            makeConfig(base, env).hasEquivalentContent(to: makeConfig(notBrightened, env)) == false
        )
        #expect(makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(manuallyColored, env)))
        #expect(makeConfig(base, env).hasEquivalentHeightContent(to: makeConfig(notBrightened, env)))
    }

    @Test
    func setColorTargetsOnlyTheClickedGroupAndKeepsSelection() throws {
        let manager = makeTabManager()
        let firstGroupId = try #require(manager.createWorkspaceGroup(name: "First"))
        let secondGroupId = try #require(manager.createWorkspaceGroup(name: "Second"))
        let firstAnchor = try #require(manager.workspaceGroupAnchor(for: firstGroupId)?.id)
        let secondAnchor = try #require(manager.workspaceGroupAnchor(for: secondGroupId)?.id)
        manager.setWorkspaceGroupColor(groupId: secondGroupId, hex: "#3FAE6A")
        // Both header anchors multi-selected, as Command-click leaves them,
        // with the second group focused: a selection-driven action would
        // recolor the second group too.
        manager.sidebarMultiSelection.replaceSelection(with: [firstAnchor, secondAnchor])
        let selectedWorkspaceId = manager.selectedTabId

        let actions = VerticalTabsSidebar.makeWorkspaceGroupColorActions(
            groupId: firstGroupId,
            tabManager: manager
        )
        actions.onSetColor("#c0392b")

        let first = try #require(manager.workspaceGroups.first { $0.id == firstGroupId })
        let second = try #require(manager.workspaceGroups.first { $0.id == secondGroupId })
        #expect(first.customColor == "#C0392B")
        #expect(second.customColor == "#3FAE6A")
        #expect(manager.sidebarSelectedWorkspaceIds == [firstAnchor, secondAnchor])
        #expect(manager.selectedTabId == selectedWorkspaceId)

        actions.onSetColor(nil)
        #expect(manager.workspaceGroups.first { $0.id == firstGroupId }?.customColor == nil)
        #expect(manager.workspaceGroups.first { $0.id == secondGroupId }?.customColor == "#3FAE6A")
    }

    // MARK: Fixtures

    private func makeTabManager() -> TabManager {
        let suiteName = "cmux.group-header-plumbing-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = TabManager(
            autoWelcomeIfNeeded: false,
            settings: UserDefaultsSettingsClient(defaults: defaults),
            closeTabWarningDefaults: defaults
        )
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        return manager
    }

    private func makeGroup(customColor: String?) -> WorkspaceGroup {
        WorkspaceGroup(
            id: UUID(),
            name: "Group",
            isCollapsed: false,
            isPinned: false,
            anchorWorkspaceId: UUID(),
            customColor: customColor,
            iconSymbol: nil
        )
    }

    private func makeEnvironment() -> SidebarWorkspaceTableEnvironmentSnapshot {
        SidebarWorkspaceTableEnvironmentSnapshot(
            colorScheme: .light,
            globalFontMagnificationPercent: 100,
            lazyContractProbe: SidebarLazyContractProbe()
        )
    }

    private func makeActions() -> SidebarGroupHeaderRowActions {
        SidebarGroupHeaderRowActions(
            onToggleCollapsed: {}, onFocusAnchor: { _ in }, onTapPlus: {},
            onRunResolvedItem: { _ in }, onRename: {}, onTogglePinned: {}, onMarkRead: {},
            onMarkUnread: {}, onClearLatestNotifications: {}, onMarkAllRead: {},
            onMarkAllUnread: {}, onUngroup: {}, onDelete: {}, onEditConfig: {}, onOpenDocs: {}
        )
    }

    private func makeConfig(
        _ model: SidebarGroupHeaderRowModel,
        _ environment: SidebarWorkspaceTableEnvironmentSnapshot
    ) -> SidebarWorkspaceTableRowConfiguration {
        SidebarWorkspaceTableRowConfiguration(
            groupHeaderModel: model,
            actions: makeActions(),
            environment: environment
        )
    }

    private func makeModel(
        name: String = "Group",
        tintHex: String? = nil,
        customColorHex: String? = nil,
        brightenInDarkMode: Bool = true,
        bandStyle: SidebarWorkspaceRowBackgroundStyle? = nil,
        multiSelectionBackgroundStyle: SidebarWorkspaceRowBackgroundStyle = .clear,
        topGap: CGFloat = 0,
        isFirstRenderedRow: Bool = false,
        showsGroupDividers: Bool = false
    ) -> SidebarGroupHeaderRowModel {
        SidebarGroupHeaderRowModel(
            groupId: Self.groupId,
            anchorWorkspaceId: Self.anchorId,
            name: name,
            iconSymbol: "folder",
            tintHex: tintHex,
            customColorHex: customColorHex,
            brightenInDarkMode: brightenInDarkMode,
            isCollapsed: false,
            isPinned: false,
            isAnchorActive: false,
            isMultiSelected: false,
            multiSelectionBackgroundStyle: multiSelectionBackgroundStyle,
            memberCount: 1,
            anchorUnreadCount: 0,
            canMarkRead: false,
            canMarkUnread: false,
            hasLatestNotifications: false,
            canMarkAllRead: false,
            canMarkAllUnread: false,
            shortcutHintText: nil,
            shortcutHintXOffset: 0,
            shortcutHintYOffset: 0,
            fontScale: 1,
            globalFontMagnificationPercent: 100,
            cwdContextMenuItems: [],
            rowSpacing: 2,
            isFirstRow: false,
            isBeingDragged: false,
            topDropIndicatorVisible: false,
            bottomDropIndicatorVisible: false,
            colorSchemeIsDark: false,
            notificationBadgeColorHex: nil,
            bandStyle: bandStyle,
            showsGroupDividers: showsGroupDividers,
            topGap: topGap,
            isFirstRenderedRow: isFirstRenderedRow
        )
    }
}
