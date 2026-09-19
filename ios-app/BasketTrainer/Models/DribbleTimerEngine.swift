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

    // Alertes pour chaque seconde entière t avec from < t <= to, dans l'ordre croissant.
    // Robuste aux sauts (app en arrière-plan) : chaque frontière franchie est signalée une fois.
    static func alerts(for steps: [DribbleStep], from: Int, to: Int) -> [DribbleAlert] {
        let lo = max(from, 0)
        guard to > lo, !steps.isEmpty else { return [] }
        var result: [DribbleAlert] = []
        var end = 0
        for (i, step) in steps.enumerated() {
            end += step.seconds
            if step.seconds > 3 {
                for k in stride(from: 3, through: 1, by: -1) {
                    let t = end - k
                    if t > lo && t <= to { result.append(.countdown(secondsLeft: k)) }
                }
            }
            if end > lo && end <= to {
                result.append(i == steps.count - 1 ? .finished : .stepChanged(newIndex: i + 1))
            }
        }
        return result
    }

    // Secondes cumulées par exercice (repos exclus), dans l'ordre de première apparition.
    static func drillTimes(for steps: [DribbleStep]) -> [DribbleDrillTime] {
        var order: [String] = []
        var totals: [String: Int] = [:]
        for step in steps {
            guard let drill = step.drill else { continue }
            if totals[drill] == nil { order.append(drill) }
            totals[drill, default: 0] += step.seconds
        }
        return order.map { DribbleDrillTime(drill: $0, seconds: totals[$0] ?? 0) }
    }
}
