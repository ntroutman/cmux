import CmuxTerminal
import Foundation

/// Nonblocking ordered handoff from Ghostty's serialized PTY callback to the
/// main actor. The AsyncStream handoff still preserves callback order for later
/// OSC notifications. The latest-directory snapshot is no longer confined to
/// that callback: it is a lock-guarded, last-writer-wins field written by the
/// OSC 7 callback thread (`enqueue`) and by main-actor socket reports
/// (`recordExternallyReportedDirectory`), and read by the
/// `GHOSTTY_ACTION_OPEN_URL` cmd-click path and the desktop-notification
/// `hookDirectory` path via `directorySnapshot()`.
final class GhosttyCurrentDirectoryActionDispatcher {
    typealias Delivery = @MainActor @Sendable (GhosttyCurrentDirectoryAction) -> Void

    private let startBoundaryHash: UInt64?
    private let endBoundaryHash: UInt64?
    private let replayBoundaryContinuation: AsyncStream<GhosttyCurrentDirectoryAction>.Continuation
    private let ordinaryContinuation: AsyncStream<GhosttyCurrentDirectoryAction>.Continuation
    // LOCK CARVE-OUT (skills/cmux-architecture Swift 6 concurrency): the writer
    // (GHOSTTY_ACTION_PWD) and primary reader (GHOSTTY_ACTION_OPEN_URL) are
    // synchronous C action callbacks on Ghostty's I/O thread — and, for a
    // cmd-click release, synchronously on main — plus main-actor socket reports;
    // none can `await` an actor, so an actor cannot serve this field. Each
    // critical section is a single optional-String assign or read, never held
    // across hashing, the AsyncStream yield, or main-actor work. It replaces an
    // existing unsynchronized cross-thread access and guards no ongoing domain
    // state (the authoritative directory record stays in Workspace).
    private let latestDirectoryLock = NSLock()
    private var latestDirectory: String?

    init(
        startBoundary: String? = nil,
        endBoundary: String? = nil,
        delivery: Delivery? = nil
    ) {
        self.startBoundaryHash = startBoundary.map(Self.stableHash)
        self.endBoundaryHash = endBoundary.map(Self.stableHash)
        let (replayBoundaryStream, replayBoundaryContinuation) =
            AsyncStream<GhosttyCurrentDirectoryAction>.makeStream(
                bufferingPolicy: .bufferingNewest(2)
            )
        let (ordinaryStream, ordinaryContinuation) =
            AsyncStream<GhosttyCurrentDirectoryAction>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
        self.replayBoundaryContinuation = replayBoundaryContinuation
        self.ordinaryContinuation = ordinaryContinuation
        let resolvedDelivery: Delivery
        if let delivery {
            resolvedDelivery = { action in
                Self.recordReportedWorkingDirectory(action)
                delivery(action)
            }
        } else {
            resolvedDelivery = { action in
                Self.deliver(action)
            }
        }
        Task { @MainActor in
            for await action in replayBoundaryStream {
                resolvedDelivery(action)
            }
        }
        Task { @MainActor in
            for await action in ordinaryStream {
                resolvedDelivery(action)
            }
        }
    }

    deinit {
        replayBoundaryContinuation.finish()
        ordinaryContinuation.finish()
    }

    func enqueue(
        directory: String,
        authoritativeGeometry: NotificationScrollRestoreGeometry?,
        surfaceView: GhosttyNSView,
        terminalSurface: TerminalSurface?
    ) {
        latestDirectoryLock.lock()
        latestDirectory = directory.isEmpty ? nil : directory
        latestDirectoryLock.unlock()
        let directoryHash = Self.stableHash(directory)
        let isStartBoundary = directoryHash == startBoundaryHash
        let isEndBoundary = directoryHash == endBoundaryHash
        let action = GhosttyCurrentDirectoryAction(
            directory: directory,
            authoritativeGeometry: authoritativeGeometry,
            replayBoundaryGeneration: isStartBoundary || isEndBoundary ? 0 : nil,
            surfaceView: surfaceView,
            terminalSurface: terminalSurface
        )
        if action.replayBoundaryGeneration == nil {
            ordinaryContinuation.yield(action)
        } else {
            replayBoundaryContinuation.yield(action)
        }
    }

    /// The latest lock-protected directory value by execution order, written by
    /// the OSC 7 callback (`enqueue`) and by socket reports
    /// (`recordExternallyReportedDirectory`).
    func directorySnapshot() -> String? {
        latestDirectoryLock.lock()
        defer { latestDirectoryLock.unlock() }
        return latestDirectory
    }

    /// Records an already-normalized directory from a socket report, bypassing
    /// the AsyncStream handoff: it never yields an action, so `deliver` and
    /// `recordReportedWorkingDirectory` do not run for it (the socket report
    /// already updated the authoritative record itself). An empty string is a
    /// no-op that leaves the snapshot unchanged; it does not clear.
    func recordExternallyReportedDirectory(_ directory: String) {
        guard !directory.isEmpty else { return }
        latestDirectoryLock.lock()
        latestDirectory = directory
        latestDirectoryLock.unlock()
    }

    @MainActor
    private static func deliver(_ action: GhosttyCurrentDirectoryAction) {
        guard let surfaceView = action.surfaceView else { return }
        if action.terminalSurface?.hostedView.sessionScrollbackReplayDidReceiveBoundary(
            action.directory,
            authoritativeGeometry: action.authoritativeGeometry
        ) == true || action.replayBoundaryGeneration != nil {
            return
        }
        recordReportedWorkingDirectory(action)
        guard let tabId = surfaceView.tabId,
              let surfaceId = action.terminalSurface?.id else { return }
        AppDelegate.shared?.tabManagerFor(tabId: tabId)?.updateReportedSurfaceDirectory(
            tabId: tabId,
            surfaceId: surfaceId,
            directory: action.directory
        )
    }

    @MainActor
    private static func recordReportedWorkingDirectory(_ action: GhosttyCurrentDirectoryAction) {
        guard action.replayBoundaryGeneration == nil,
              let terminalSurface = action.terminalSurface,
              terminalSurface.focusPlacement == .rightSidebarDock else { return }
        terminalSurface.recordReportedWorkingDirectory(action.directory)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xcbf29ce484222325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x100000001b3
        }
    }
}
