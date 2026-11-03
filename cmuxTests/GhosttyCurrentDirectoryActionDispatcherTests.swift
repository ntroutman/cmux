import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Ghostty current-directory action dispatcher", .serialized)
struct GhosttyCurrentDirectoryActionDispatcherTests {
    @Test(arguments: [2, 100])
    func replayBoundariesSurviveOrdinaryPWDQueueing(ordinaryCount: Int) async {
        let startBoundary = "/.cmux/session-scrollback-replay/test/start"
        let endBoundary = "/.cmux/session-scrollback-replay/test/end"
        var deliveredDirectories: [String] = []
        let dispatcher = GhosttyCurrentDirectoryActionDispatcher(
            startBoundary: startBoundary,
            endBoundary: endBoundary
        ) { action in
            deliveredDirectories.append(action.directory)
        }
        let surfaceView = GhosttyNSView(frame: .zero)

        dispatcher.enqueue(
            directory: startBoundary,
            authoritativeGeometry: nil,
            surfaceView: surfaceView,
            terminalSurface: nil
        )
        for index in 0..<ordinaryCount {
            dispatcher.enqueue(
                directory: "/replayed/\(index)",
                authoritativeGeometry: nil,
                surfaceView: surfaceView,
                terminalSurface: nil
            )
        }
        dispatcher.enqueue(
            directory: endBoundary,
            authoritativeGeometry: nil,
            surfaceView: surfaceView,
            terminalSurface: nil
        )
        for index in 0..<ordinaryCount {
            dispatcher.enqueue(
                directory: "/live/\(index)",
                authoritativeGeometry: nil,
                surfaceView: surfaceView,
                terminalSurface: nil
            )
        }

        for _ in 0..<10 where !deliveredDirectories.contains(endBoundary) {
            await Task.yield()
        }

        let startIndex = deliveredDirectories.firstIndex(of: startBoundary)
        let endIndex = deliveredDirectories.firstIndex(of: endBoundary)
        #expect(startIndex != nil)
        #expect(endIndex != nil)
        if let startIndex, let endIndex {
            #expect(startIndex < endIndex)
        }
    }

    @Test("External record overrides the snapshot without delivering an action")
    func externalRecordUpdatesSnapshotWithoutDelivery() async {
        var deliveryCount = 0
        let dispatcher = GhosttyCurrentDirectoryActionDispatcher { _ in
            deliveryCount += 1
        }
        let surfaceView = GhosttyNSView(frame: .zero)

        dispatcher.enqueue(
            directory: "/a",
            authoritativeGeometry: nil,
            surfaceView: surfaceView,
            terminalSurface: nil
        )
        for _ in 0..<10 where deliveryCount == 0 {
            await Task.yield()
        }
        let deliveriesAfterEnqueue = deliveryCount
        #expect(deliveriesAfterEnqueue == 1)

        dispatcher.recordExternallyReportedDirectory("/b")
        #expect(dispatcher.directorySnapshot() == "/b")

        // Give any erroneously yielded action a chance to reach the delivery closure.
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(deliveryCount == deliveriesAfterEnqueue)

        dispatcher.enqueue(
            directory: "/c",
            authoritativeGeometry: nil,
            surfaceView: surfaceView,
            terminalSurface: nil
        )
        #expect(dispatcher.directorySnapshot() == "/c")
    }

    @Test("External record with an empty string leaves the snapshot unchanged")
    func externalRecordWithEmptyStringIsNoOp() {
        let dispatcher = GhosttyCurrentDirectoryActionDispatcher { _ in }
        let surfaceView = GhosttyNSView(frame: .zero)

        dispatcher.enqueue(
            directory: "/a",
            authoritativeGeometry: nil,
            surfaceView: surfaceView,
            terminalSurface: nil
        )
        #expect(dispatcher.directorySnapshot() == "/a")

        dispatcher.recordExternallyReportedDirectory("")
        #expect(dispatcher.directorySnapshot() == "/a")
    }
}
