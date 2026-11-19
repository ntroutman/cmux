import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Sidebar snapshot lifetime")
struct SidebarRowSnapshotCacheTests {
    @Test func replacingMembershipAtTheSameCountReleasesRetiredSnapshot() {
        let cache = SidebarRowSnapshotCache()
        let retiredID = UUID()
        let replacementID = UUID()
        let snapshot = SidebarWorkspaceRowSuspensionTests.makeModel().snapshot
        cache.replace(with: [retiredID: snapshot])

        // A restore/reorder can replace membership without changing its count.
        cache.prune(keeping: [replacementID])
        #expect(cache.value(for: retiredID) == nil)
        cache.replace(with: [replacementID: snapshot])
        #expect(cache.value(for: replacementID) == snapshot)
    }

    @Test func clearingManualColorMatchingOriginRefreshesClearColorState() throws {
        let suiteName = "SidebarRowSnapshotCacheTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = Workspace(title: "Color provenance", initialSurface: .cloudVMLoading)
        defer { workspace.teardownAllPanels() }
        let originColor = "#B1A2FA"
        let disabledFactory = SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: defaults),
            showsAgentActivity: false
        )
        let disabledSnapshot = disabledFactory.makeSnapshot()
        #expect(disabledSnapshot.customColorHex == nil)
        #expect(disabledSnapshot.hasManualCustomColor == false)

        let factory = SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: defaults),
            showsAgentActivity: false,
            fallbackColorHex: originColor
        )
        let cache = SidebarRowSnapshotCache()
        let defaultSnapshot = factory.makeSnapshot()
        #expect(defaultSnapshot.customColorHex == originColor)
        #expect(defaultSnapshot.hasManualCustomColor == false)

        let manualColor = "#FF945A"
        workspace.customColor = manualColor
        let differentManualSnapshot = factory.makeSnapshot()
        #expect(differentManualSnapshot.customColorHex == manualColor)
        #expect(differentManualSnapshot.hasManualCustomColor == true)

        workspace.customColor = originColor
        let manualSnapshot = factory.makeSnapshot()
        cache.reconcile(workspaceIds: [workspace.id], presentationKey: manualSnapshot.presentationKey) { _ in
            manualSnapshot
        }
        #expect(cache.value(for: workspace.id)?.hasManualCustomColor == true)

        workspace.customColor = nil
        let originSnapshot = factory.makeSnapshot()
        cache.reconcile(workspaceIds: [workspace.id], presentationKey: originSnapshot.presentationKey) { _ in
            originSnapshot
        }
        #expect(cache.value(for: workspace.id)?.customColorHex == originColor)
        #expect(cache.value(for: workspace.id)?.hasManualCustomColor == false)
    }

    /// The full refresh reuses a cached row only while its presentation key
    /// matches, so a changed automatic color must change the key.
    @Test func changedAutomaticColorChangesThePresentationKey() throws {
        let suiteName = "SidebarRowSnapshotCacheTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = Workspace(title: "Auto color key", initialSurface: .cloudVMLoading)
        defer { workspace.teardownAllPanels() }
        let resolver = WorkspaceAutoColorResolver.make(mode: .worktree)
        let roots = (0..<16).map { "/work/auto-color-key/tree-\($0)" }
        let firstColor = try #require(autoColor(resolver, root: roots[0]))
        let secondColor = try #require(roots.lazy.compactMap { autoColor(resolver, root: $0) }.first { $0 != firstColor })
        func snapshot(_ color: String) -> SidebarWorkspaceSnapshotBuilder.Snapshot {
            SidebarWorkspaceSnapshotFactory(
                workspace: workspace,
                settings: SidebarTabItemSettingsSnapshot(defaults: defaults),
                showsAgentActivity: false,
                fallbackColorHex: color
            ).makeSnapshot()
        }
        let firstSnapshot = snapshot(firstColor)
        let secondSnapshot = snapshot(secondColor)
        #expect(firstSnapshot.presentationKey != secondSnapshot.presentationKey)

        let cache = SidebarRowSnapshotCache()
        cache.reconcile(workspaceIds: [workspace.id], presentationKey: firstSnapshot.presentationKey) { _ in
            firstSnapshot
        }
        cache.reconcile(workspaceIds: [workspace.id], presentationKey: secondSnapshot.presentationKey) { _ in
            secondSnapshot
        }
        #expect(cache.value(for: workspace.id)?.customColorHex == secondColor)
        #expect(cache.value(for: workspace.id)?.hasManualCustomColor == false)
    }

    private func autoColor(_ resolver: WorkspaceAutoColorResolver, root: String) -> String? {
        resolver.colorHex(for: WorkspaceAutoColorInput(
            stableId: UUID(), currentDirectory: root, projectRootPath: root, groupId: nil, isLocal: true
        ))
    }

    @Test func repeatedWorkspaceReplacementDoesNotRetainHistoricalSnapshots() {
        let cache = SidebarRowSnapshotCache()
        let snapshot = SidebarWorkspaceRowSuspensionTests.makeModel().snapshot
        var liveID = UUID()
        cache.replace(with: [liveID: snapshot])
        var retiredIDs: [UUID] = []
        for _ in 0..<100 {
            retiredIDs.append(liveID)
            liveID = UUID()
            cache.prune(keeping: [liveID])
            cache.replace(with: [liveID: snapshot])
            #expect(cache.value(for: liveID) == snapshot)
        }
        #expect(retiredIDs.allSatisfy { cache.value(for: $0) == nil })
        cache.prune(keeping: [])
        #expect(cache.value(for: liveID) == nil)
    }
}
