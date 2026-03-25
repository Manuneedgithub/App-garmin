import SwiftUI

// ─────────────────────────────────────────────────
// HISTORIQUE — Toutes les séances, filtrables
// ─────────────────────────────────────────────────
struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @State private var filterType: ExerciseType? = nil
    @State private var showFilterSheet = false

    private var filteredSessions: [WorkoutSession] {
        let sorted = store.sessions.sorted { $0.date > $1.date }
        guard let filter = filterType else { return sorted }
        return sorted.filter { $0.exerciseType == filter }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if filteredSessions.isEmpty {
                        emptyState
                    } else {
                        sessionList
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterButton
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(selectedType: $filterType)
            }
        }
    }

    // ── Composants ──

    private var sessionList: some View {
        List {
            ForEach(groupedByDate.keys.sorted().reversed(), id: \.self) { key in
                Section {
                    ForEach(groupedByDate[key]!) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { offsets in deleteFrom(key: key, offsets: offsets) }
                } header: {
                    Text(key)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "basketball")
                .font(.system(size: 56))
                .foregroundStyle(.orange.opacity(0.5))
            Text("Aucune séance")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(filterType == nil
                 ? "Lance un entraînement depuis la montre."
                 : "Aucune séance pour cet exercice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: filterType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    // ── Logique ──

    // Groupe les séances par date (format "Mardi 25 mars")
    private var groupedByDate: [String: [WorkoutSession]] {
        Dictionary(grouping: filteredSessions) { session in
            session.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
    }

    private func deleteFrom(key: String, offsets: IndexSet) {
        guard let group = groupedByDate[key] else { return }
        offsets.map { group[$0] }.forEach { store.deleteSession($0) }
    }
}

// ─────────────────────────────────────────────────
// Sheet de filtrage par type d'exercice
// ─────────────────────────────────────────────────
struct FilterSheet: View {
    @Binding var selectedType: ExerciseType?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    // Option "Tous"
                    Button {
                        selectedType = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("🏀  Tous les exercices")
                                .foregroundStyle(.white)
                            Spacer()
                            if selectedType == nil {
                                Image(systemName: "checkmark").foregroundStyle(.orange)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    ForEach(ExerciseType.allCases) { type in
                        Button {
                            selectedType = type
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(type.emoji)  \(type.name)")
                                    .foregroundStyle(.white)
                                Spacer()
                                if selectedType == type {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Filtrer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
    }
}
