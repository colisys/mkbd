import Foundation

/// Rolling-window keystroke counter. Timestamps must be monotonic (system
/// uptime), which keeps pruning to a single prefix scan even while typing fast.
public struct KeystrokeCounter: Sendable {
    public let window: TimeInterval
    private var timestamps: [TimeInterval] = []

    public init(window: TimeInterval = 60) {
        self.window = window
    }

    public mutating func record(at time: TimeInterval) {
        timestamps.append(time)
        prune(now: time)
    }

    public mutating func prune(now: TimeInterval) {
        let cutoff = now - window
        if let index = timestamps.firstIndex(where: { $0 >= cutoff }) {
            if index > 0 { timestamps.removeFirst(index) }
        } else {
            timestamps.removeAll(keepingCapacity: true)
        }
    }

    public func count(now: TimeInterval) -> Int {
        let cutoff = now - window
        guard let index = timestamps.firstIndex(where: { $0 >= cutoff }) else { return 0 }
        return timestamps.count - index
    }
}
