import SwiftUI

// ─────────────────────────────────────────────────
// HISTORIQUE EXERCICES PHYSIQUES — séances terminées (téléphone ou montre).
// Séparé de l'historique de tirs et de celui de dribble.
// ─────────────────────────────────────────────────
struct PhysicalHistoryView: View {
    @EnvironmentObject var physicalStore: PhysicalStore

    private var sorted: [PhysicalSession] {
        physicalStore.sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                VStack(spacing: 10) {
                    Text("Aucune séance physique")
                        .font(.headline)
                    Text("Les exercices terminés apparaissent ici.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(sorted) { session in
                        NavigationLink {
                            PhysicalSessionDetailView(session: session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(session.exerciseName).font(.headline)
                                        if session.sentFromWatch { Text("⌚").font(.caption2) }
                                    }
                                    Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(session.attempts.count) tentative\(session.attempts.count > 1 ? "s" : "")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { physicalStore.deleteSession(sorted[i]) }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Historique physique")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PhysicalSessionDetailView: View {
    let session: PhysicalSession

    var body: some View {
        List {
            Section {
                row("Date", session.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                row("Type", session.kind == .chrono ? "Chrono" : "Durée fixe")
                row("Source", session.sentFromWatch ? "Montre" : "iPhone")
            }
            Section("Tentatives") {
                if session.attempts.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                }
                ForEach(session.attempts.indices, id: \.self) { i in
                    row("Tentative \(i + 1)", attemptLabel(session.attempts[i]))
                }
            }
        }
        .navigationTitle(session.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func attemptLabel(_ attempt: PhysicalAttempt) -> String {
        if let s = attempt.seconds { return PhysicalFormat.chronoResult(s) }
        if let r = attempt.reps { return PhysicalFormat.repsResult(r) }
        return "—"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
