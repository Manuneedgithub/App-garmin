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

@main
struct DribbleTests {
    static func main() {
        testModels()
        testResolveDrill()
        testFormat()
        print("Task 1 assertions passed")
    }
}
