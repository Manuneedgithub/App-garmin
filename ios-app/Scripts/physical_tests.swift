import Foundation

// Minimal assertion helper — precondition (not assert) so it still fires under -O.
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: UInt = #line) {
    precondition(a == b, "line \(line): \(a) != \(b) \(msg)")
}

func testModels() {
    expectEqual(PhysicalLibrary.builtIn.count, 5)
    expectEqual(PhysicalLibrary.builtIn[0].name, "25m")
    expectEqual(PhysicalLibrary.builtIn[0].kind, .chrono)
    expectEqual(PhysicalLibrary.builtIn[0].fixedSeconds, nil)
    expectEqual(PhysicalLibrary.builtIn.last?.name, "1 min aller-retour sprint")
    expectEqual(PhysicalLibrary.builtIn.last?.kind, .duration)
    expectEqual(PhysicalLibrary.builtIn.last?.fixedSeconds, 60)
    expectEqual(PhysicalLibrary.maxNameLength, 30)
    expectEqual(PhysicalLibrary.maxRepsPerAttempt, 50)

    // Codable round trip keeps ids and the optional fields.
    let ex = PhysicalExercise(name: "100m", kind: .chrono)
    let data = try! JSONEncoder().encode(ex)
    let back = try! JSONDecoder().decode(PhysicalExercise.self, from: data)
    expectEqual(back, ex)

    let session = PhysicalSession(exerciseName: "100m", kind: .chrono,
                                   date: Date(timeIntervalSince1970: 1000),
                                   attempts: [PhysicalAttempt(seconds: 14.23, reps: nil)],
                                   sentFromWatch: true)
    let sData = try! JSONEncoder().encode(session)
    let sBack = try! JSONDecoder().decode(PhysicalSession.self, from: sData)
    expectEqual(sBack.attempts, [PhysicalAttempt(seconds: 14.23, reps: nil)])
    expectEqual(sBack.sentFromWatch, true)
}

func testFormat() {
    expectEqual(PhysicalFormat.chronoResult(14.23), "14.23 s")
    expectEqual(PhysicalFormat.chronoResult(-3), "0.00 s")
    expectEqual(PhysicalFormat.repsResult(12), "12 rép.")
    expectEqual(PhysicalFormat.repsResult(-1), "0 rép.")
    expectEqual(PhysicalFormat.duration(45), "45 s")
    expectEqual(PhysicalFormat.duration(60), "1 min")
    expectEqual(PhysicalFormat.duration(90), "1 min 30 s")
    expectEqual(PhysicalFormat.runningClock(0), "0:00.0")
    expectEqual(PhysicalFormat.runningClock(4.9), "0:04.9")
    expectEqual(PhysicalFormat.runningClock(65.0), "1:05.0")
    expectEqual(PhysicalFormat.runningClock(-3), "0:00.0")
}

func testTimer() {
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 0), 60)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 0.1), 60)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 30.0), 30)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 59.9), 1)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 60.0), 0)
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: 61.0), 0)
    // Negative elapsed (shouldn't happen on a real wall clock) must not overshoot past fixedSeconds.
    expectEqual(PhysicalTimer.secondsRemaining(fixedSeconds: 60, elapsed: -5), 60)
    expectEqual(PhysicalTimer.isFinished(fixedSeconds: 60, elapsed: 59.9), false)
    expectEqual(PhysicalTimer.isFinished(fixedSeconds: 60, elapsed: 60.0), true)
    expectEqual(PhysicalTimer.isFinished(fixedSeconds: 60, elapsed: 61.0), true)
}

@main
struct PhysicalTests {
    static func main() {
        testModels()
        testFormat()
        testTimer()
        print("Task 1 (physical) assertions passed")
    }
}
