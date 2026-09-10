import SwiftUI

// ─────────────────────────────────────────────────
// ENTRAÎNEMENT COMPLET EN DIRECT — routine multi-séries jouée et suivie
// tir par tir directement sur l'iPhone. Mutualisé avec les entraînements
// montre (SlotsView.swift) : peut partir de zéro, ou charger un des
// entraînements déjà enregistrés dans SessionStore.watchSlots — même
// modèle de données (ComplexTemplate/TemplateSeries), que la séance soit
// ensuite jouée sur la montre ou suivie ici.
// ─────────────────────────────────────────────────

private enum LiveRoutinePhase {
    case configure
    case tracking
    case seriesDone
    case summary
}

struct LiveRoutineView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    @State private var phase: LiveRoutinePhase = .configure
    @State private var seriesList: [TemplateSeries] = [TemplateSeries(exerciseType: .freethrow, totalShots: 10)]
    @State private var currentSeriesIndex = 0
    @State private var currentResults: [Bool] = []
    @State private var completedSeries: [ShotSeries] = []
    @State private var startTime: Date = Date()
    @State private var showDiscardConfirm = false

    private let maxSeries = 6

    private var hasProgress: Bool { !completedSeries.isEmpty || !currentResults.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                switch phase {
                case .configure:  configureContent
                case .tracking:   trackingContent
                case .seriesDone: seriesDoneContent
                case .summary:    summaryContent
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(phase == .configure ? "Annuler" : "Quitter") {
                        if phase != .configure && hasProgress {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }.foregroundStyle(.orange)
                }
            }
            .alert("Quitter la routine ?", isPresented: $showDiscardConfirm) {
                Button("Annuler", role: .cancel) {}
                if phase != .summary {
                    Button("Voir le résumé partiel") { withAnimation { phase = .summary } }
                }
                Button("Tout abandonner", role: .destructive) { dismiss() }
            } message: {
                Text("Les séries déjà jouées peuvent être conservées dans un résumé partiel, ou tout perdre.")
            }
        }
    }

    private var title: String {
        switch phase {
        case .configure:  return "Entraînement complet"
        case .tracking:   return currentSeries.exerciseType.name
        case .seriesDone: return "Série terminée"
        case .summary:    return "Résumé"
        }
    }

    // ── Configuration ──

    private var savedTemplates: [(index: Int, template: ComplexTemplate)] {
        store.watchSlots.enumerated().compactMap { idx, t in t.map { (idx, $0) } }
    }

    private var configureContent: some View {
        Form {
            if !savedTemplates.isEmpty {
                Section("Charger un entraînement enregistré") {
                    ForEach(savedTemplates, id: \.index) { _, template in
                        Button {
                            seriesList = template.series
                        } label: {
                            HStack {
                                Text(template.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(template.series.count) série\(template.series.count > 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Séries (\(seriesList.count)/\(maxSeries))") {
                ForEach(seriesList.indices, id: \.self) { idx in
                    SeriesRow(series: $seriesList[idx])
                }
                .onDelete { offsets in seriesList.remove(atOffsets: offsets) }
                if seriesList.count < maxSeries {
                    Button {
                        seriesList.append(TemplateSeries(exerciseType: .freethrow, totalShots: 10))
                    } label: {
                        Label("Ajouter une série", systemImage: "plus.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Button {
                    currentSeriesIndex = 0
                    currentResults = []
                    completedSeries = []
                    startTime = Date()
                    withAnimation { phase = .tracking }
                } label: {
                    Text("Commencer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color.orange)
                .disabled(seriesList.isEmpty)
            }
        }
    }

    // ── Suivi de la série en cours ──

    private var currentSeries: TemplateSeries { seriesList[currentSeriesIndex] }
    private var madeCount: Int { currentResults.filter { $0 }.count }
    private var currentIndex: Int { currentResults.count }
    private var percentage: Double { currentResults.isEmpty ? 0 : Double(madeCount) / Double(currentResults.count) * 100 }

    private var trackingContent: some View {
        VStack(spacing: 20) {
            Text("Série \(currentSeriesIndex + 1) / \(seriesList.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 6) {
                Text("\(currentIndex) / \(currentSeries.totalShots)")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(String(format: "%.0f%%", percentage))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(percentageColor(percentage))
            }

            if !currentResults.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(currentResults.enumerated()), id: \.offset) { i, made in
                        ShotDot(index: i + 1, made: made)
                    }
                }
                .padding(.horizontal, 30)
            }

            Spacer()

            HStack(spacing: 16) {
                routineShotButton(made: false)
                routineShotButton(made: true)
            }
            .padding(.horizontal, 20)

            Button {
                withAnimation { _ = currentResults.popLast() }
            } label: {
                Label("Annuler le dernier tir", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(currentResults.isEmpty ? 0 : 1)
            .disabled(currentResults.isEmpty)
        }
        .padding(.bottom, 20)
    }

    private func routineShotButton(made: Bool) -> some View {
        Button {
            recordShot(made: made)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: made ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 40))
                Text(made ? "Réussi" : "Raté")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(made ? Color.green : Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func recordShot(made: Bool) {
        withAnimation { currentResults.append(made) }
        guard currentResults.count >= currentSeries.totalShots else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var finished = ShotSeries(exerciseType: currentSeries.exerciseType,
                                       totalShots: currentResults.count,
                                       madeShots: madeCount,
                                       results: currentResults)
            finished.shotType = currentSeries.shotType
            completedSeries.append(finished)
            withAnimation { phase = .seriesDone }
        }
    }

    // ── Transition entre deux séries ──

    private var isLastSeries: Bool { currentSeriesIndex >= seriesList.count - 1 }

    private var seriesDoneContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let last = completedSeries.last {
                    VStack(spacing: 6) {
                        Text("Série \(currentSeriesIndex + 1) / \(seriesList.count) terminée")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(last.exerciseType.emoji).font(.system(size: 36))
                        Text(last.exerciseType.name).font(.headline).foregroundStyle(.primary)
                        Text("\(last.madeShots) / \(last.totalShots)")
                            .font(.system(size: 36, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text(String(format: "%.0f%%", last.percentage))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(percentageColor(last.percentage))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                if !isLastSeries {
                    let next = seriesList[currentSeriesIndex + 1]
                    HStack(spacing: 10) {
                        Text(next.exerciseType.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prochaine série").font(.caption).foregroundStyle(.secondary)
                            Text("\(next.exerciseType.name) · \(next.totalShots) tirs")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("Dernière série !")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Button {
                    if isLastSeries {
                        withAnimation { phase = .summary }
                    } else {
                        currentSeriesIndex += 1
                        currentResults = []
                        withAnimation { phase = .tracking }
                    }
                } label: {
                    Text(isLastSeries ? "Voir le résumé" : "Continuer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // ── Résumé final ──

    private var combinedMade: Int { completedSeries.reduce(0) { $0 + $1.madeShots } }
    private var combinedTotal: Int { completedSeries.reduce(0) { $0 + $1.totalShots } }
    private var combinedPercentage: Double { combinedTotal == 0 ? 0 : Double(combinedMade) / Double(combinedTotal) * 100 }

    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("🗂️").font(.system(size: 44))
                    Text("\(completedSeries.count) série\(completedSeries.count > 1 ? "s" : "")")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("\(combinedMade) / \(combinedTotal)")
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(String(format: "%.0f%%", combinedPercentage))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(percentageColor(combinedPercentage))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 10) {
                    ForEach(Array(completedSeries.enumerated()), id: \.offset) { idx, series in
                        HStack {
                            Text(series.exerciseType.emoji)
                            Text("Série \(idx + 1) — \(series.exerciseType.name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(series.madeShots)/\(series.totalShots)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text(String(format: "%.0f%%", series.percentage))
                                .font(.caption.bold())
                                .foregroundStyle(percentageColor(series.percentage))
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    save()
                } label: {
                    Text("Enregistrer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(completedSeries.isEmpty)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func save() {
        guard !completedSeries.isEmpty else { return }
        let allResults = completedSeries.flatMap { $0.results }
        var s = WorkoutSession(exerciseType: completedSeries[0].exerciseType,
                                totalShots: combinedTotal,
                                madeShots: combinedMade,
                                results: allResults,
                                date: startTime)
        s.series = completedSeries
        store.add(s)
        dismiss()
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
