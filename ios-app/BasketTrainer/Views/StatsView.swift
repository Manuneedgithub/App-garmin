import SwiftUI
import Charts

// ─────────────────────────────────────────────────
// STATS — Vue globale par exercice
// ─────────────────────────────────────────────────

enum StatsPeriod: String, CaseIterable {
    case all    = "Tout"
    case month  = "Mois"
    case week   = "Semaine"
    case today  = "Auj"

    func startDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:   return nil
        case .month: return cal.date(from: cal.dateComponents([.year, .month], from: now))
        case .week:  return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        case .today: return cal.startOfDay(for: now)
        }
    }

    // Début de la période précédente (pour la comparaison)
    func previousStartDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return nil
        case .month:
            let s = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return cal.date(byAdding: .month, value: -1, to: s)
        case .week:
            let s = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return cal.date(byAdding: .weekOfYear, value: -1, to: s)
        case .today:
            return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var store: SessionStore
    @State private var period: StatsPeriod = .all

    // ── Sessions filtrées ──
    private var filteredSessions: [WorkoutSession] {
        guard let start = period.startDate() else { return store.sessions }
        return store.sessions.filter { $0.date >= start }
    }

    private var previousSessions: [WorkoutSession] {
        guard let prevStart = period.previousStartDate(),
              let currStart = period.startDate() else { return [] }
        return store.sessions.filter { $0.date >= prevStart && $0.date < currStart }
    }

    // ── Métriques globales ──
    private var filteredTotalShots: Int { filteredSessions.reduce(0) { $0 + $1.totalShots } }

    private var filteredOverallPct: Double {
        let made  = filteredSessions.reduce(0) { $0 + $1.madeShots }
        let total = filteredTotalShots
        return total == 0 ? 0 : Double(made) / Double(total) * 100
    }

    private var previousOverallPct: Double {
        let made  = previousSessions.reduce(0) { $0 + $1.madeShots }
        let total = previousSessions.reduce(0) { $0 + $1.totalShots }
        return total == 0 ? 0 : Double(made) / Double(total) * 100
    }

    private var pctChange: Double? {
        guard period != .all, !previousSessions.isEmpty else { return nil }
        return filteredOverallPct - previousOverallPct
    }

    // ── Série d'entraînement ──
    private var currentStreak: Int {
        let cal = Calendar.current
        let days = Set(store.sessions.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
        var streak = 0
        var expected = cal.startOfDay(for: Date())
        for d in days {
            if d == expected {
                streak += 1
                expected = cal.date(byAdding: .day, value: -1, to: expected)!
            } else if d < expected {
                break
            }
        }
        return streak
    }

    private var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(store.sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, current = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev {
                let next = cal.date(byAdding: .day, value: 1, to: p)!
                current = cal.isDate(next, inSameDayAs: d) ? current + 1 : 1
            } else {
                current = 1
            }
            best = max(best, current)
            prev = d
        }
        return best
    }

    // ── Records personnels ──
    private struct PersonalBest {
        let exerciseType: ExerciseType
        let percentage: Double
        let shots: Int
        let date: Date
    }

    private var personalBests: [PersonalBest] {
        var records: [ExerciseType: PersonalBest] = [:]
        for session in store.sessions {
            if let series = session.series {
                for s in series where s.totalShots >= 10 {
                    let ex = s.exerciseType
                    if records[ex] == nil || s.percentage > records[ex]!.percentage {
                        records[ex] = PersonalBest(exerciseType: ex, percentage: s.percentage,
                                                    shots: s.totalShots, date: session.date)
                    }
                }
            } else if session.totalShots >= 10 {
                let ex = session.exerciseType
                if records[ex] == nil || session.percentage > records[ex]!.percentage {
                    records[ex] = PersonalBest(exerciseType: ex, percentage: session.percentage,
                                                shots: session.totalShots, date: session.date)
                }
            }
        }
        return records.values.sorted { $0.percentage > $1.percentage }
    }

    // ── Analyse fatigue (1ère moitié vs 2ème moitié des tirs) ──
    private var fatigueData: (first: Double, second: Double)? {
        let eligible = filteredSessions.filter { !$0.isComplex && $0.results.count >= 10 }
        guard !eligible.isEmpty else { return nil }
        var firstMade = 0, firstTotal = 0
        var secondMade = 0, secondTotal = 0
        for s in eligible {
            let half = s.results.count / 2
            let first  = s.results.prefix(half)
            let second = s.results.suffix(half)
            firstMade  += first.filter { $0 }.count;  firstTotal  += first.count
            secondMade += second.filter { $0 }.count; secondTotal += second.count
        }
        guard firstTotal > 0, secondTotal > 0 else { return nil }
        return (Double(firstMade) / Double(firstTotal) * 100,
                Double(secondMade) / Double(secondTotal) * 100)
    }

    // ─────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        periodPicker
                        globalSummary
                        if filteredSessions.count >= 2 {
                            progressChart
                        }
                        calendarHeatmap
                        HotZonesView(sessions: filteredSessions)
                        if !personalBests.isEmpty {
                            recordsSection
                        }
                        if let fatigue = fatigueData {
                            fatigueSection(fatigue)
                        }
                        exerciseStatsList
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Statistiques")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // ─────────────────────────────────────────────────
    // COMPOSANTS
    // ─────────────────────────────────────────────────

    private var periodPicker: some View {
        Picker("Période", selection: $period) {
            ForEach(StatsPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    // ── Résumé global ──
    private var globalSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlobalStatCard(value: "\(filteredSessions.count)",
                               label: "Séances",
                               icon: "figure.basketball",
                               color: .orange)
                GlobalStatCard(value: "\(filteredTotalShots)",
                               label: "Tirs totaux",
                               icon: "basketball",
                               color: .blue)
            }
            HStack(spacing: 12) {
                // Réussite globale + flèche tendance
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f%%", filteredOverallPct))
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        if let change = pctChange {
                            HStack(spacing: 2) {
                                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.caption2.bold())
                                Text(String(format: "%.1f%%", abs(change)))
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(change >= 0 ? .green : .red)
                        }
                    }
                    Text("Réussite globale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if pctChange != nil {
                        Text("vs période précédente")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "percent")
                        .font(.title2)
                        .foregroundStyle(colorForPct(filteredOverallPct))
                        .padding(12)
                }

                // Série d'entraînement
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(currentStreak)")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text(currentStreak <= 1 ? "jour" : "jours")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Série actuelle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if longestStreak > 0 {
                        Text("Record : \(longestStreak) j")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    Text(currentStreak >= 7 ? "🔥" : currentStreak >= 3 ? "⚡" : "💤")
                        .font(.title2)
                        .padding(10)
                }
            }
        }
    }

    // ── Graphique progression ──
    private var progressChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progression (15 dernières séances)")
                .font(.headline)
                .foregroundStyle(.white)

            let data = filteredSessions
                .sorted { $0.date < $1.date }
                .suffix(15)
                .enumerated()
                .map { (index: $0.offset + 1, pct: $0.element.percentage) }

            Chart {
                ForEach(data, id: \.index) { point in
                    LineMark(x: .value("Séance", point.index), y: .value("Réussite", point.pct))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Séance", point.index), y: .value("Réussite", point.pct))
                        .foregroundStyle(LinearGradient(
                            colors: [.orange.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Séance", point.index), y: .value("Réussite", point.pct))
                        .foregroundStyle(.orange)
                        .symbolSize(30)
                }
                RuleMark(y: .value("Objectif", 70))
                    .foregroundStyle(.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("70%").font(.caption2).foregroundStyle(.green.opacity(0.7))
                    }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)%")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 160)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // ── Heatmap calendrier (10 dernières semaines) ──
    private var calendarHeatmap: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisWeekStart = cal.date(from: cal.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: today))!
        let startDay = cal.date(byAdding: .weekOfYear, value: -9, to: thisWeekStart)!
        let grouped  = Dictionary(grouping: store.sessions) { cal.startOfDay(for: $0.date) }
        let allDays: [Date] = (0..<70).compactMap { cal.date(byAdding: .day, value: $0, to: startDay) }
        let weeks: [[Date]] = stride(from: 0, to: allDays.count, by: 7)
            .map { i in Array(allDays[i..<min(i + 7, allDays.count)]) }
        let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Calendrier d'entraînement")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 4) {
                // Étiquettes jours
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(dayLetters[i])
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 14)
                    }
                }

                // Grille
                HStack(spacing: 4) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 4) {
                            ForEach(week, id: \.self) { day in
                                let count = grouped[day]?.count ?? 0
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(count: count, isFuture: day > today))
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                }
            }

            // Légende
            HStack(spacing: 6) {
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0...3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(count: i, isFuture: false))
                        .frame(width: 10, height: 10)
                }
                Text("3+")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func heatColor(count: Int, isFuture: Bool) -> Color {
        if isFuture || count == 0 { return Color.white.opacity(0.08) }
        switch count {
        case 1:  return Color.orange.opacity(0.40)
        case 2:  return Color.orange.opacity(0.70)
        default: return Color.orange
        }
    }

    // ── Records personnels ──
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Records personnels")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Meilleures séances par exercice (≥ 10 tirs, tous temps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(personalBests.prefix(6), id: \.exerciseType) { record in
                HStack(spacing: 12) {
                    Text(record.exerciseType.emoji)
                        .font(.title3)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.exerciseType.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(record.shots) tirs · \(record.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.0f%%", record.percentage))
                            .font(.title3.bold())
                            .foregroundStyle(colorForPct(record.percentage))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // ── Résistance à la fatigue ──
    @ViewBuilder
    private func fatigueSection(_ data: (first: Double, second: Double)) -> some View {
        let diff = data.second - data.first
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Résistance à la fatigue")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("1ère vs 2ème moitié des séances (≥ 10 tirs)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: diff >= 0 ? "bolt.fill" : "battery.25")
                    .foregroundStyle(diff >= 0 ? .green : .orange)
                    .font(.title3)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(String(format: "%.0f%%", data.first))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Début")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    if abs(diff) >= 0.5 {
                        Text(String(format: "%+.1f%%", diff))
                            .font(.caption2.bold())
                            .foregroundStyle(diff >= 0 ? .green : .red)
                    }
                }

                VStack(spacing: 4) {
                    Text(String(format: "%.0f%%", data.second))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Fin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                FatigueBar(label: "Début", pct: data.first, color: .blue)
                FatigueBar(label: "Fin",   pct: data.second, color: diff >= 0 ? .green : .red)
            }

            Text(fatigueComment(diff: diff))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func fatigueComment(diff: Double) -> String {
        if diff >= 5  { return "Tu performes mieux en fin de séance — excellent mental !" }
        if diff >= 2  { return "Bonne résistance à la fatigue." }
        if diff >= -2 { return "Résistance stable — la fatigue t'affecte peu." }
        if diff >= -5 { return "Légère baisse en fin de séance, c'est normal après un effort." }
        return "Fatigue marquée en fin de séance — essaie de raccourcir les séries."
    }

    // ── Stats par exercice ──
    private var exerciseStatsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Par exercice")
                .font(.headline)
                .foregroundStyle(.white)

            let stats = store.allStats(from: filteredSessions)
            if stats.isEmpty {
                Text(period == .all
                     ? "Lance des séances pour voir tes stats ici."
                     : "Aucune séance sur cette période.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(stats, id: \.exerciseType) { ExerciseStatRow(stats: $0) }
            }
        }
    }

    private func colorForPct(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}

// ─────────────────────────────────────────────────
// BARRE FATIGUE
// ─────────────────────────────────────────────────
struct FatigueBar: View {
    let label: String
    let pct:   Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(pct / 100, 1.0), height: 8)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0f%%", pct))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// ─────────────────────────────────────────────────
// HOT ZONES — Terrain de basket avec zones colorées
// ─────────────────────────────────────────────────
struct HotZonesView: View {
    let sessions: [WorkoutSession]

    private struct Zone {
        let exercise: ExerciseType
        let x: CGFloat
        let y: CGFloat
    }

    private let zones: [Zone] = [
        Zone(exercise: .freethrow,    x: 0.50, y: 0.54),
        Zone(exercise: .midCenter,    x: 0.50, y: 0.68),
        Zone(exercise: .midRight,     x: 0.71, y: 0.60),
        Zone(exercise: .midLeft,      x: 0.29, y: 0.60),
        Zone(exercise: .threeCenter,  x: 0.50, y: 0.26),
        Zone(exercise: .threeRight45, x: 0.79, y: 0.43),
        Zone(exercise: .threeLeft45,  x: 0.21, y: 0.43),
        Zone(exercise: .threeCornerR, x: 0.91, y: 0.75),
        Zone(exercise: .threeCornerL, x: 0.09, y: 0.75),
    ]

    private func pct(for ex: ExerciseType) -> Double? {
        var total = 0, made = 0
        for s in sessions {
            if let series = s.series {
                for ser in series where ser.exerciseType == ex {
                    total += ser.totalShots
                    made  += ser.madeShots
                }
            } else if s.exerciseType == ex {
                total += s.totalShots
                made  += s.madeShots
            }
        }
        return total > 0 ? Double(made) / Double(total) * 100 : nil
    }

    private func zoneColor(_ p: Double?) -> Color {
        guard let p else { return .white.opacity(0.18) }
        switch p {
        case 70.0...: return Color(red: 0.10, green: 0.82, blue: 0.25)
        case 55.0...: return Color(red: 1.00, green: 0.78, blue: 0.00)
        case 40.0...: return Color(red: 1.00, green: 0.45, blue: 0.00)
        default:      return Color(red: 0.92, green: 0.15, blue: 0.15)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hot Zones")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                ForEach([
                    ("≥70%", Color(red: 0.10, green: 0.82, blue: 0.25)),
                    ("55%",  Color(red: 1.00, green: 0.78, blue: 0.00)),
                    ("40%",  Color(red: 1.00, green: 0.45, blue: 0.00)),
                    ("<40%", Color(red: 0.92, green: 0.15, blue: 0.15)),
                ], id: \.0) { label, color in
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Canvas { ctx, size in drawCourt(ctx, size) }
                    ForEach(zones, id: \.exercise) { zone in
                        let p = pct(for: zone.exercise)
                        ZStack {
                            Circle()
                                .fill(zoneColor(p).opacity(0.88))
                                .frame(width: 38, height: 38)
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                .frame(width: 38, height: 38)
                            if let p {
                                Text("\(Int(p))%")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "minus")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .position(x: zone.x * w, y: zone.y * h)
                    }
                }
            }
            .aspectRatio(50.0 / 47.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func drawCourt(_ ctx: GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let line = GraphicsContext.Shading.color(Color.white.opacity(0.75))
        let lw: CGFloat = 1.5

        ctx.fill(Path(CGRect(origin: .zero, size: sz)),
                 with: .color(Color(red: 0.68, green: 0.43, blue: 0.14)))

        let baseline = h * 0.94
        ctx.stroke(Path(CGRect(origin: .zero, size: sz)), with: line, lineWidth: lw)
        var bl = Path(); bl.move(to: .init(x: 0, y: baseline)); bl.addLine(to: .init(x: w, y: baseline))
        ctx.stroke(bl, with: line, lineWidth: lw)

        let kx = w * 0.34, kw = w * 0.32, ftY = h * 0.56
        var key = Path(); key.addRect(CGRect(x: kx, y: ftY, width: kw, height: baseline - ftY))
        ctx.fill(key, with: .color(Color(red: 0.50, green: 0.28, blue: 0.08)))
        ctx.stroke(key, with: line, lineWidth: lw)

        let ftR = w * 0.16
        ctx.stroke(Path(ellipseIn: .init(x: w*0.5-ftR, y: ftY-ftR, width: ftR*2, height: ftR*2)),
                   with: line, lineWidth: lw)

        let bx = w * 0.5, by = h * 0.86
        let br: CGFloat = 7
        ctx.stroke(Path(ellipseIn: .init(x: bx-br, y: by-br, width: br*2, height: br*2)),
                   with: line, lineWidth: 2)
        var bb = Path(); bb.move(to: .init(x: bx-w*0.08, y: by-13)); bb.addLine(to: .init(x: bx+w*0.08, y: by-13))
        ctx.stroke(bb, with: line, lineWidth: 2.5)

        let arcR = w * 0.46
        let cxL = w * 0.055, cxR = w * 0.945
        let dx  = cxL - bx
        let arcMeetY = by - sqrt(max(0, arcR*arcR - dx*dx))

        var cL = Path(); cL.move(to: .init(x: cxL, y: baseline)); cL.addLine(to: .init(x: cxL, y: arcMeetY))
        ctx.stroke(cL, with: line, lineWidth: lw)
        var cR = Path(); cR.move(to: .init(x: cxR, y: baseline)); cR.addLine(to: .init(x: cxR, y: arcMeetY))
        ctx.stroke(cR, with: line, lineWidth: lw)

        let aStart = Angle.radians(atan2(Double(arcMeetY - by), Double(cxL - bx)))
        let aEnd   = Angle.radians(atan2(Double(arcMeetY - by), Double(cxR - bx)))
        var arc = Path()
        arc.addArc(center: .init(x: bx, y: by), radius: arcR,
                   startAngle: aStart, endAngle: aEnd, clockwise: false)
        ctx.stroke(arc, with: line, lineWidth: lw)

        let raR = w * 0.08
        var ra = Path()
        ra.addArc(center: .init(x: bx, y: by), radius: raR,
                  startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        ctx.stroke(ra, with: line, lineWidth: lw)
    }
}

// ─────────────────────────────────────────────────
// Carte stat globale
// ─────────────────────────────────────────────────
struct GlobalStatCard: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ─────────────────────────────────────────────────
// Ligne de stat d'un exercice avec barre de progression
// ─────────────────────────────────────────────────
struct ExerciseStatRow: View {
    let stats: ExerciseStats

    private var pctColor: Color {
        if stats.avgPercentage >= 70 { return .green }
        if stats.avgPercentage >= 50 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(stats.exerciseType.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.exerciseType.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(stats.totalSessions) séance\(stats.totalSessions > 1 ? "s" : "") · \(stats.totalShots) tirs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", stats.avgPercentage))
                    .font(.title3.bold())
                    .foregroundStyle(pctColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pctColor)
                        .frame(width: geo.size.width * (stats.avgPercentage / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
