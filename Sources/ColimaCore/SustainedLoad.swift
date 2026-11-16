import Foundation

// Tracks whether a sampled load, such as VM CPU, stays at or above a threshold
// for a whole period. One dip below the threshold, or a gap between samples
// longer than the period, starts over.
package struct SustainedLoad {
    package let threshold: Double
    package let duration: TimeInterval
    private var since: Date?
    package private(set) var sustained = false
    private var lastSample: Date?

    package init(threshold: Double, duration: TimeInterval) {
        self.threshold = threshold
        self.duration = duration
    }

    // Returns true once per episode: when the load has just stayed high for
    // the whole period.
    package mutating func record(_ value: Double, at date: Date) -> Bool {
        defer { lastSample = date }
        let gap = lastSample.map { date.timeIntervalSince($0) > max(duration, 60) } ?? false
        guard value >= threshold else {
            reset()
            return false
        }
        if since == nil || gap {
            since = date
            sustained = false
        }
        guard !sustained, let since, date.timeIntervalSince(since) >= duration else { return false }
        sustained = true
        return true
    }

    package mutating func reset() {
        since = nil
        sustained = false
    }
}
