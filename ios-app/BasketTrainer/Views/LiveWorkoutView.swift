import SwiftUI

// ─────────────────────────────────────────────────
// ENTRAÎNEMENT EN DIRECT — utilisable sans la montre :
// configuration → suivi tir par tir → résumé + sauvegarde.
// Contrairement à ManualSessionView (saisie agrégée a posteriori),
// ceci produit un vrai tableau `results` tir par tir.
// ─────────────────────────────────────────────────

private enum LiveWorkoutPhase {
    case setup
    case tracking
    case summary
}

// Mode "Nombre de tirs" (s'arrête après N tirs) vs "Objectif de paniers"
// (s'arrête dès que N paniers sont rentrés, tirs illimités) — même
// distinction que "Tirs libres"/"Objectif simple" sur la montre.
private enum WorkoutMode: String, CaseIterable, Identifiable {
    case shotCount = "Nombre de tirs"
    case goal      = "Objectif de paniers"
    var id: String { rawValue }
}

struct LiveWorkoutView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    @State private var phase: LiveWorkoutPhase = .setup
    @State private var exercise: ExerciseType = .freethrow
    @State private var mode: WorkoutMode = .shotCount
    @State private var totalShots: Int = 10
    @State private var targetMade: Int = 10
    @State private var shotType: ShotType = .catchAndShoot
    @State private var results: [Bool] = []
    @State private var startTime: Date = Date()
    @State private var showDiscardConfirm = false

    private let shotOptions = [5, 10, 15, 20, 25, 30]

    // Certains exercices (lancer franc, familles de lay up) n'ont qu'un
    // seul type de tir logique — voir ExerciseType.forcedShotType.
    private var effectiveShotType: ShotType {
        exercise.forcedShotType ?? shotType
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                switch phase {
                case .setup:    setupContent
                case .tracking: trackingContent
                case .summary:  summaryContent
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(phase == .setup ? "Annuler" : "Quitter") {
                        if phase == .tracking && !results.isEmpty {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }.foregroundStyle(.orange)
                }
            }
            .alert("Abandonner la séance ?", isPresented: $showDiscardConfirm) {
                Button("Annuler", role: .cancel) {}
                Button("Abandonner", role: .destructive) { dismiss() }
            } message: {
                Text("Les tirs déjà enregistrés seront perdus.")
            }
        }
    }

    private var title: String {
        switch phase {
        case .setup:    return "Nouvel entraînement"
        case .tracking: return exercise.name
        case .summary:  return "Résumé"
        }
    }

    // ── Configuration ──

    private var setupContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Exercice", icon: "figure.basketball")
                    VStack(spacing: 8) {
                        ForEach(ExerciseType.allCases) { ex in
                            ExerciseOptionRow(exercise: ex, isSelected: exercise == ex)
                                .onTapGesture { exercise = ex }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Mode", icon: "target")
                    Picker("Mode", selection: $mode) {
                        ForEach(WorkoutMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: mode == .shotCount ? "Nombre de tirs" : "Objectif de paniers",
                                 icon: "basketball")
                    HStack(spacing: 10) {
                        ForEach(shotOptions, id: \.self) { n in
                            ShotCountChip(count: n, isSelected: (mode == .shotCount ? totalShots : targetMade) == n)
                                .onTapGesture {
                                    if mode == .shotCount { totalShots = n } else { targetMade = n }
                                }
                        }
                    }
                }

                if let forced = exercise.forcedShotType {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("\(exercise.name) : toujours \(forced.name.lowercased())")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Type de tir", icon: "figure.basketball")
                        Picker("Type de tir", selection: $shotType) {
                            ForEach(ShotType.allCases, id: \.self) { t in Text(t.name).tag(t) }
                        }
                        .pickerStyle(.segmented)
                        .padding(16)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                Button {
                    results = []
                    startTime = Date()
                    withAnimation { phase = .tracking }
                } label: {
                    Text("Commencer")
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

    // ── Suivi tir par tir ──

    private var madeCount: Int { results.filter { $0 }.count }
    private var currentIndex: Int { results.count }
    private var percentage: Double { results.isEmpty ? 0 : Double(madeCount) / Double(results.count) * 100 }

    private var trackingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 6) {
                Text(mode == .shotCount ? "\(currentIndex) / \(totalShots)" : "\(madeCount) / \(targetMade)")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if mode == .goal {
                    Text("\(currentIndex) tir\(currentIndex > 1 ? "s" : "") pris")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f%%", percentage))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(percentageColor(percentage))
            }

            if !results.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(results.enumerated()), id: \.offset) { i, made in
                        ShotDot(index: i + 1, made: made)
                    }
                }
                .padding(.horizontal, 30)
            }

            Spacer()

            HStack(spacing: 16) {
                shotButton(made: false)
                shotButton(made: true)
            }
            .padding(.horizontal, 20)

            Button {
                withAnimation { _ = results.popLast() }
            } label: {
                Label("Annuler le dernier tir", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(results.isEmpty ? 0 : 1)
            .disabled(results.isEmpty)
        }
        .padding(.bottom, 20)
    }

    private func shotButton(made: Bool) -> some View {
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
        withAnimation { results.append(made) }
        let finished = mode == .shotCount ? results.count >= totalShots : madeCount >= targetMade
        if finished {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { phase = .summary }
            }
        }
    }

    // ── Résumé ──

    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(exercise.emoji).font(.system(size: 44))
                    Text(exercise.name).font(.title3.bold()).foregroundStyle(.primary)
                    Text("\(madeCount) / \(currentIndex)")
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(String(format: "%.0f%%", percentage))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(percentageColor(percentage))
                    if mode == .goal {
                        Text("Objectif de \(targetMade) atteint 🎯")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(results.enumerated()), id: \.offset) { i, made in
                        ShotDot(index: i + 1, made: made)
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

                Button {
                    withAnimation { phase = .setup }
                } label: {
                    Text("Recommencer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func save() {
        var s = WorkoutSession(exerciseType: exercise, totalShots: currentIndex,
                                madeShots: madeCount, results: results, date: startTime)
        s.shotType = effectiveShotType
        if mode == .goal {
            var series = ShotSeries(exerciseType: exercise, totalShots: currentIndex,
                                     madeShots: madeCount, results: results)
            series.targetMade = targetMade
            series.shotType = effectiveShotType
            s.series = [series]
        }
        store.add(s)
        dismiss()
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
