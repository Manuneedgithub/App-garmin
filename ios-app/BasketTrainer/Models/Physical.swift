import Foundation

// ─────────────────────────────────────────────────
// EXERCICES PHYSIQUES — modèles purs (aucune dépendance UI)
// ─────────────────────────────────────────────────

enum PhysicalExerciseKind: String, Codable {
    case chrono     // stopwatch: measure elapsed time
    case duration   // fixed-duration countdown: count repetitions
}

struct PhysicalExercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: PhysicalExerciseKind
    var fixedSeconds: Int?    // required (5...600, step 5) iff kind == .duration; nil iff kind == .chrono
}

struct PhysicalAttempt: Codable, Equatable {
    var seconds: Double?      // chrono result (e.g. 14.23)
    var reps: Int?            // duration result (repetitions counted)
}

struct PhysicalSession: Codable, Identifiable {
    var id = UUID()
    var exerciseName: String
    var kind: PhysicalExerciseKind
    var date: Date             // session start; (date, exerciseName) dedupes watch re-sends
    var attempts: [PhysicalAttempt]
    var sentFromWatch: Bool
}

enum PhysicalLibrary {
    static let builtIn: [PhysicalExercise] = [
        PhysicalExercise(name: "25m", kind: .chrono),
        PhysicalExercise(name: "50m", kind: .chrono),
        PhysicalExercise(name: "100m", kind: .chrono),
        PhysicalExercise(name: "Suicide", kind: .chrono),
        PhysicalExercise(name: "1 min aller-retour sprint", kind: .duration, fixedSeconds: 60),
    ]
    static let maxNameLength = 30
    static let fixedSecondsRange = 5...600
    static let maxRepsPerAttempt = 50
}

enum PhysicalFormat {
    // "14.23 s" — hundredths of a second, matches typical sprint-time display.
    static func chronoResult(_ seconds: Double) -> String {
        String(format: "%.2f s", max(seconds, 0))
    }

    // "12 rép." (negative clamps to 0)
    static func repsResult(_ reps: Int) -> String {
        "\(max(reps, 0)) rép."
    }

    // "45 s", "1 min", "1 min 30 s" — same style as DribbleFormat.duration.
    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }

    // Stopwatch / elapsed display while a chrono is running: "m:ss.d"
    static func runningClock(_ seconds: Double) -> String {
        let t = max(seconds, 0)
        let m = Int(t) / 60
        let s = t - Double(m * 60)
        return String(format: "%d:%04.1f", m, s)
    }
}
