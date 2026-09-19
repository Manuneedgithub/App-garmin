import Foundation

// Minimal assertion helper — precondition (not assert) so it still fires under -O.
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: UInt = #line) {
    precondition(a == b, "line \(line): \(a) != \(b) \(msg)")
}

func drill(_ name: String, _ seconds: Int) -> DribbleStep { DribbleStep(drill: name, seconds: seconds) }
func rest(_ seconds: Int) -> DribbleStep { DribbleStep(seconds: seconds) }

// The routine from the feature request: 30 s cross, 10 s rest, 30 s behind the back, 20 s rest, 1 min between.
let exampleSteps: [DribbleStep] = [
    drill("Cross", 30), rest(10), drill("Behind the back", 30), rest(20), drill("Between the legs", 60),
]

func testModels() {
    expectEqual(rest(10).isRest, true)
    expectEqual(drill("Cross", 30).isRest, false)
    let routine = DribbleRoutine(name: "Ma routine", steps: exampleSteps)
    expectEqual(routine.totalSeconds, 150)
    expectEqual(DribbleRoutine(name: "vide", steps: []).totalSeconds, 0)
    expectEqual(DribbleLibrary.builtInDrills.count, 8)
    expectEqual(DribbleLibrary.builtInDrills.first, "Cross")
    expectEqual(DribbleLibrary.maxSteps, 20)

    // Codable round trip keeps ids and the rest/drill distinction.
    let data = try! JSONEncoder().encode(routine)
    let decoded = try! JSONDecoder().decode(DribbleRoutine.self, from: data)
    expectEqual(decoded, routine)

    let session = DribbleSession(routineName: "Ma routine", date: Date(timeIntervalSince1970: 1_000),
                                 totalSeconds: 150, drillTimes: [DribbleDrillTime(drill: "Cross", seconds: 30)],
                                 sentFromWatch: true)
    let sData = try! JSONEncoder().encode(session)
    let sBack = try! JSONDecoder().decode(DribbleSession.self, from: sData)
    expectEqual(sBack.routineName, "Ma routine")
    expectEqual(sBack.drillTimes, [DribbleDrillTime(drill: "Cross", seconds: 30)])
    expectEqual(sBack.sentFromWatch, true)
}

func testResolveDrill() {
    let known = DribbleLibrary.builtInDrills + ["Wrap around"]
    // empty / whitespace-only → nil
    precondition(DribbleLibrary.resolveDrill("", known: known) == nil)
    precondition(DribbleLibrary.resolveDrill("   \n", known: known) == nil)
    // existing name, different case/spacing → the canonical existing name, not new
    let existing = DribbleLibrary.resolveDrill("  cross ", known: known)
    expectEqual(existing?.name, "Cross")
    expectEqual(existing?.isNew, false)
    let custom = DribbleLibrary.resolveDrill("wrap AROUND", known: known)
    expectEqual(custom?.name, "Wrap around")
    expectEqual(custom?.isNew, false)
    // genuinely new name → trimmed, flagged new
    let fresh = DribbleLibrary.resolveDrill("  Spider dribble ", known: known)
    expectEqual(fresh?.name, "Spider dribble")
    expectEqual(fresh?.isNew, true)
    // capped at 30 characters
    let long = DribbleLibrary.resolveDrill(String(repeating: "x", count: 50), known: known)
    expectEqual(long?.name.count, 30)
    expectEqual(long?.isNew, true)
}

func testFormat() {
    expectEqual(DribbleFormat.duration(45), "45 s")
    expectEqual(DribbleFormat.duration(60), "1 min")
    expectEqual(DribbleFormat.duration(90), "1 min 30 s")
    expectEqual(DribbleFormat.duration(150), "2 min 30 s")
    expectEqual(DribbleFormat.clock(0), "0:00")
    expectEqual(DribbleFormat.clock(5), "0:05")
    expectEqual(DribbleFormat.clock(65), "1:05")
    expectEqual(DribbleFormat.clock(-3), "0:00")
}

func testState() {
    // Example routine: Cross 0–30, rest 30–40, BTB 40–70, rest 70–90, Between 90–150.
    func s(_ e: Int) -> DribbleTimerState { DribbleTimerEngine.state(for: exampleSteps, elapsed: e) }
    expectEqual(s(0),   DribbleTimerState(stepIndex: 0, secondsLeftInStep: 30, isFinished: false))
    expectEqual(s(29),  DribbleTimerState(stepIndex: 0, secondsLeftInStep: 1,  isFinished: false))
    expectEqual(s(30),  DribbleTimerState(stepIndex: 1, secondsLeftInStep: 10, isFinished: false))
    expectEqual(s(39),  DribbleTimerState(stepIndex: 1, secondsLeftInStep: 1,  isFinished: false))
    expectEqual(s(40),  DribbleTimerState(stepIndex: 2, secondsLeftInStep: 30, isFinished: false))
    expectEqual(s(70),  DribbleTimerState(stepIndex: 3, secondsLeftInStep: 20, isFinished: false))
    expectEqual(s(90),  DribbleTimerState(stepIndex: 4, secondsLeftInStep: 60, isFinished: false))
    expectEqual(s(149), DribbleTimerState(stepIndex: 4, secondsLeftInStep: 1,  isFinished: false))
    // finished exactly at the total, and stays finished
    expectEqual(s(150), DribbleTimerState(stepIndex: 5, secondsLeftInStep: 0, isFinished: true))
    expectEqual(s(9999), DribbleTimerState(stepIndex: 5, secondsLeftInStep: 0, isFinished: true))
    // negative elapsed behaves like 0
    expectEqual(s(-5), s(0))
    // empty routine is immediately finished
    expectEqual(DribbleTimerEngine.state(for: [], elapsed: 0),
                DribbleTimerState(stepIndex: 0, secondsLeftInStep: 0, isFinished: true))
}

func testAlerts() {
    func a(_ from: Int, _ to: Int, _ steps: [DribbleStep] = exampleSteps) -> [DribbleAlert] {
        DribbleTimerEngine.alerts(for: steps, from: from, to: to)
    }
    // First step: countdown 3-2-1 then the change to step 1, all within 0→30.
    expectEqual(a(0, 30), [.countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
                           .stepChanged(newIndex: 1)])
    // One second at a time: nothing until 27, then exactly one alert per second.
    expectEqual(a(0, 26), [])
    expectEqual(a(26, 27), [.countdown(secondsLeft: 3)])
    expectEqual(a(29, 30), [.stepChanged(newIndex: 1)])
    expectEqual(a(30, 31), [])
    // Big jump (app was backgrounded): every crossed boundary reported once, ascending.
    expectEqual(a(25, 41), [
        .countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
        .stepChanged(newIndex: 1),
        .countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
        .stepChanged(newIndex: 2),
    ])
    // Whole routine: 5 steps × (3 countdowns + 1 boundary) = 20 alerts, 4 stepChanged, ends with finished.
    let all = a(0, 150)
    expectEqual(all.count, 20)
    expectEqual(all.filter { if case .stepChanged = $0 { return true } else { return false } }.count, 4)
    expectEqual(all.last, .finished)
    // finished exactly once, whatever the partition, and never after the end
    expectEqual(a(0, 500).filter { $0 == .finished }.count, 1)
    expectEqual(a(150, 200), [])
    expectEqual(a(0, 75).count + a(75, 150).count, 20)
    // Short steps (≤ 3 s) never emit a countdown.
    let short = [drill("A", 3), drill("B", 5)]
    expectEqual(a(0, 8, short), [
        .stepChanged(newIndex: 1),
        .countdown(secondsLeft: 3), .countdown(secondsLeft: 2), .countdown(secondsLeft: 1),
        .finished,
    ])
    // Degenerate ranges
    expectEqual(a(10, 10), [])
    expectEqual(a(20, 10), [])
    expectEqual(a(0, 5, []), [])
    expectEqual(a(-5, 30).count, a(0, 30).count)
}

func testDrillTimes() {
    // Rests excluded; repeated drill summed; order of first appearance.
    let steps = [drill("Cross", 30), rest(10), drill("Cross", 20), drill("Behind the back", 15), rest(5)]
    expectEqual(DribbleTimerEngine.drillTimes(for: steps), [
        DribbleDrillTime(drill: "Cross", seconds: 50),
        DribbleDrillTime(drill: "Behind the back", seconds: 15),
    ])
    expectEqual(DribbleTimerEngine.drillTimes(for: exampleSteps), [
        DribbleDrillTime(drill: "Cross", seconds: 30),
        DribbleDrillTime(drill: "Behind the back", seconds: 30),
        DribbleDrillTime(drill: "Between the legs", seconds: 60),
    ])
    expectEqual(DribbleTimerEngine.drillTimes(for: [rest(10)]), [])
    expectEqual(DribbleTimerEngine.drillTimes(for: []), [])
}

@main
struct DribbleTests {
    static func main() {
        testModels()
        testResolveDrill()
        testFormat()
        testState()
        testAlerts()
        testDrillTimes()
        print("Task 1-3 assertions passed")
    }
}
