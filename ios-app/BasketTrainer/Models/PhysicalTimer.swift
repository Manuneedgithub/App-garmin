import Foundation

// Pure timing helpers for physical exercises — no UI/Timer dependency.
enum PhysicalTimer {
    // Remaining whole seconds for a Durée fixe countdown, ceiling-rounded, clamped to 0.
    static func secondsRemaining(fixedSeconds: Int, elapsed: Double) -> Int {
        let remaining = Double(fixedSeconds) - max(elapsed, 0)
        return remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    static func isFinished(fixedSeconds: Int, elapsed: Double) -> Bool {
        max(elapsed, 0) >= Double(fixedSeconds)
    }
}
