import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @State private var filterCategory: String? = nil
    @State private var searchText = ""
    @State private var showManualEntry = false

    private let categories = ["Lancer Franc", "3 Points", "Mi-distance", "Technique"]

    private var filteredSessions: [WorkoutSession] {
        var sessions = store.sessions.sorted { $0.date > $1.date }

        if let cat = filterCategory {
            sessions = sessions.filter { s in
                if let series = s.series {
                    return series.contains { $0.exerciseType.category == cat }
                }
                return s.exerciseType.category == cat
            }
        }

        if !searchText.isEmpty {
            sessions = sessions.filter { s in
                s.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return sessions
    }

    private var groupedByDate: [(key: String, sessions: [WorkoutSession])] {
        let dict = Dictionary(grouping: filteredSessions) { session -> String in
            let cal = Calendar.current
            if cal.isDateInToday(session.date) { return "Aujourd'hui" }
            if cal.isDateInYesterday(session.date) { return "Hier" }
            return session.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        let keys = dict.keys.sorted { a, b in
            if a == "Aujourd'hui" { return true }
            if b == "Aujourd'hui" { return false }
            if a == "Hier" { return true }
            if b == "Hier" { return false }
            let da = dict[a]!.first!.date
            let db = dict[b]!.first!.date
            return da > db
        }
        return keys.map { (key: $0, sessions: dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

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
            .searchable(text: $searchText, prompt: "Rechercher...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualSessionView()
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Tous", isSelected: filterCategory == nil) {
                    filterCategory = nil
                }
                ForEach(categories, id: \.self) { cat in
                    FilterChip(label: cat, isSelected: filterCategory == cat) {
                        filterCategory = filterCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterChips
                    .padding(.bottom, 8)

                ForEach(groupedByDate, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.key)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        VStack(spacing: 8) {
                            ForEach(group.sessions) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    SessionRowView(session: session)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteSession(session)
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            filterChips
            Spacer()
            Image(systemName: "basketball")
                .font(.system(size: 56))
                .foregroundStyle(.orange.opacity(0.5))
            Text("Aucune séance")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text(filterCategory == nil && searchText.isEmpty
                 ? "Lance un entraînement depuis la montre\nou ajoute-en une manuellement."
                 : "Aucun résultat pour ce filtre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if filterCategory == nil && searchText.isEmpty {
                Button {
                    showManualEntry = true
                } label: {
                    Label("Ajouter manuellement", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }
}

struct FilterChip: View {
    let label:      String
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.orange : Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color(.separator), lineWidth: isSelected ? 0 : 0.5)
                )
        }
    }
}
