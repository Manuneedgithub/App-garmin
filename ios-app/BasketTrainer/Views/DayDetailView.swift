import SwiftUI

// ─────────────────────────────────────────────────
// DÉTAIL D'UNE JOURNÉE — résumé + liste des séances/séries
// Ouvert depuis DaySummaryRowView dans HistoryView.
// ─────────────────────────────────────────────────
struct DayDetailView: View {
    let dateLabel: String
    let sessions: [WorkoutSession]

    private var stats: DayStats { sessions.dayStats }
    private var sortedSessions: [WorkoutSession] { sessions.sorted { $0.date > $1.date } }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    summaryHeader

                    VStack(spacing: 8) {
                        ForEach(sortedSessions) { session in
                            NavigationLink(destination: SessionDetailView(session: session)) {
                                SessionRowView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle(dateLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            statTile(value: "\(stats.totalShots)", label: "Tirs")
            Divider().frame(height: 36)
            statTile(value: String(format: "%.0f%%", stats.fgPercentage), label: "FG%",
                     color: percentageColor(stats.fgPercentage))
            Divider().frame(height: 36)
            if let pct3 = stats.threePtPercentage {
                statTile(value: String(format: "%.0f%%", pct3), label: "FG3%",
                         color: percentageColor(pct3))
            } else {
                statTile(value: "—", label: "FG3%")
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statTile(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
