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
}

struct StatsView: View {
    @EnvironmentObject var store: SessionStore
    @State private var period: StatsPeriod = .all

    private var filteredSessions: [WorkoutSession] {
        guard let start = period.startDate() else { return store.sessions }
        return store.sessions.filter { $0.date >= start }
    }

    private var filteredTotalShots: Int { filteredSessions.reduce(0) { $0 + $1.totalShots } }
    private var filteredOverallPct: Double {
        let made  = filteredSessions.reduce(0) { $0 + $1.madeShots }
        let total = filteredTotalShots
        return total == 0 ? 0 : Double(made) / Double(total) * 100
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // ── Sélecteur de période ──
                        periodPicker

                        // ── Résumé global ──
                        globalSummary

                        // ── Graphique progression globale ──
                        if filteredSessions.count >= 2 {
                            progressChart
                        }

                        // ── Hot Zones ──
                        HotZonesView(sessions: filteredSessions)

                        // ── Stats par exercice ──
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

    // ── Composants ──

    private var periodPicker: some View {
        Picker("Période", selection: $period) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    private var globalSummary: some View {
        VStack(spacing: 16) {
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
                GlobalStatCard(value: String(format: "%.1f%%", filteredOverallPct),
                               label: "Réussite globale",
                               icon: "percent",
                               color: colorForPct(filteredOverallPct))
                GlobalStatCard(value: "\(store.allStats(from: filteredSessions).count)",
                               label: "Exercices pratiqués",
                               icon: "list.bullet",
                               color: .purple)
            }
        }
    }

    // Graphique des 15 dernières séances (taux de réussite)
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
                    LineMark(
                        x: .value("Séance", point.index),
                        y: .value("Réussite", point.pct)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Séance", point.index),
                        y: .value("Réussite", point.pct)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Séance", point.index),
                        y: .value("Réussite", point.pct)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(30)
                }

                // Ligne de référence 70%
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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

    // Liste des stats par exercice
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
                ForEach(stats, id: \.exerciseType) { s in
                    ExerciseStatRow(stats: s)
                }
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
        case 70...: return Color(red: 0.10, green: 0.82, blue: 0.25)
        case 55...: return Color(red: 1.00, green: 0.78, blue: 0.00)
        case 40...: return Color(red: 1.00, green: 0.45, blue: 0.00)
        default:    return Color(red: 0.92, green: 0.15, blue: 0.15)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hot Zones")
                .font(.headline)
                .foregroundStyle(.white)

            // Légende
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

            // Terrain + zones
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

    // ── Dessin du terrain ──
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

            // Barre de progression
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
