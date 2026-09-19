import Foundation

// ─────────────────────────────────────────────────
// MOTEUR DE MINUTEUR DRIBBLE — pur, sans UI ni Timer.
// Prend les secondes écoulées depuis le départ (horloge murale) et
// répond : quelle étape, combien de secondes restantes, quelles alertes.
// ─────────────────────────────────────────────────

struct DribbleTimerState: Equatable {
    var stepIndex: Int            // == steps.count quand terminé
    var secondsLeftInStep: Int
    var isFinished: Bool
}

enum DribbleAlert: Equatable {
    case stepChanged(newIndex: Int)
    case countdown(secondsLeft: Int)   // 3, 2, 1
    case finished
}

enum DribbleTimerEngine {
    static func state(for steps: [DribbleStep], elapsed: Int) -> DribbleTimerState {
        let t = max(elapsed, 0)
        var end = 0
        for (i, step) in steps.enumerated() {
            end += step.seconds
            if t < end {
                return DribbleTimerState(stepIndex: i, secondsLeftInStep: end - t, isFinished: false)
            }
        }
        return DribbleTimerState(stepIndex: steps.count, secondsLeftInStep: 0, isFinished: true)
    }
}
