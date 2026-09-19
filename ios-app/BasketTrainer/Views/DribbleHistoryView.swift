import SwiftUI

// ─────────────────────────────────────────────────
// HISTORIQUE DRIBBLE — séances terminées (téléphone ou montre).
// Séparé de l'historique de tirs : pas de tirs, pas de pourcentage.
// ─────────────────────────────────────────────────
struct DribbleHistoryView: View {
    @EnvironmentObject var dribbleStore: DribbleStore

    private var sorted: [DribbleSession] {
        dribbleStore.sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                VStack(spacing: 10) {
                    Text("Aucune séance de dribble")
                        .font(.headline)
                    Text("Les routines terminées apparaissent ici.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(sorted) { session in
                        NavigationLink {
                            DribbleSessionDetailView(session: session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(session.routineName).font(.headline)
                                        if session.sentFromWatch { Text("⌚").font(.caption2) }
                                    }
                                    Text(session.date.formatted(.dateTime.day().month().hour().minute()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(DribbleFormat.duration(session.totalSeconds))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { dribbleStore.deleteSession(sorted[i]) }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Historique dribble")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DribbleSessionDetailView: View {
    let session: DribbleSession

    var body: some View {
        List {
            Section {
                row("Date", session.date.formatted(.dateTime.day().month(.wide).year().hour().minute()))
                row("Durée totale", DribbleFormat.duration(session.totalSeconds))
                row("Source", session.sentFromWatch ? "Montre" : "iPhone")
            }
            Section("Temps par exercice") {
                if session.drillTimes.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                }
                ForEach(session.drillTimes, id: \.drill) { t in
                    row(t.drill, DribbleFormat.duration(t.seconds))
                }
            }
        }
        .navigationTitle(session.routineName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
