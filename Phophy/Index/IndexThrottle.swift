import Foundation
import Synchronization

/// Tells indexing when to step aside, so it never competes with the screen.
///
/// Indexing waits while you scroll, swipe or zoom, and for a moment after;
/// it stops completely while a photo is open; and it pauses when the
/// iPhone runs hot or Low Power Mode is on. Scroll views report movement
/// with `noteActivity()`, which is cheap enough to call on every frame.
nonisolated final class IndexThrottle: Sendable {
    static let shared = IndexThrottle()

    enum Pause: Sendable, Equatable {
        case hot, lowPower

        var message: String {
            switch self {
            case .hot: "Paused to keep your iPhone cool"
            case .lowPower: "Paused in Low Power Mode"
            }
        }
    }

    /// How long the screen must be still before indexing carries on.
    static let quietPeriod: Duration = .seconds(1.5)

    private struct State {
        var lastActivity: ContinuousClock.Instant?
        var viewerOpen = false
    }

    private let state = Mutex(State())

    /// Something on screen moved (a scroll, a swipe, a zoom).
    func noteActivity() {
        let now = ContinuousClock.now
        state.withLock { $0.lastActivity = now }
    }

    func setViewerOpen(_ open: Bool) {
        let now = ContinuousClock.now
        state.withLock {
            $0.viewerOpen = open
            // The close animation counts as movement too.
            $0.lastActivity = now
        }
    }

    /// The viewer is open, or the screen moved within the quiet period.
    var screenIsBusy: Bool {
        let now = ContinuousClock.now
        return state.withLock { state in
            if state.viewerOpen { return true }
            guard let last = state.lastActivity else { return false }
            return now - last < Self.quietPeriod
        }
    }

    /// Why indexing should stop for a while, if it should.
    var pause: Pause? {
        let info = ProcessInfo.processInfo
        if info.thermalState == .serious || info.thermalState == .critical { return .hot }
        if info.isLowPowerModeEnabled { return .lowPower }
        return nil
    }
}
