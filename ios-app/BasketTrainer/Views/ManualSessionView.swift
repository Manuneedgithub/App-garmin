import SwiftUI

// ─────────────────────────────────────────────────
// SAISIE MANUELLE — Créer une séance depuis l'iPhone
// Simple (un exercice) ou Complexe (plusieurs séries)
// ─────────────────────────────────────────────────

enum SessionMode: String, CaseIterable {
    case simple  = "Simple"
    case complex = "Complexe"
}

struct ManualSessionView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    var prefillTemplate: ComplexTemplate? = nil

    @State private var mode: SessionMode
    @State private var date: Date = Date()

    // ── Simple ──
    @State private var exercise:   ExerciseType = .freethrow
    @State private var totalShots: Int = 10
    @State private var madeShots:  Int = 7

    // ── Complexe ──
    @State private var series: [ShotSeries]

    // ── Template ──
    @State private var saveAsTemplate: Bool = false
    @State private var templateName:   String = ""

    private let shotOptions = [5, 10, 15, 20, 25, 30]

    init(prefillTemplate: ComplexTemplate? = nil) {
        self.prefillTemplate = prefillTemplate
        if let t = prefillTemplate {
            _mode = State(initialValue: .complex)
            _series = State(initialValue: t.series.map {
                ShotSeries(exerciseType: $0.exerciseType, totalShots: $0.totalShots, madeShots: 0)
            })
            _templateName = State(initialValue: t.name)
        } else {
            _mode = State(initialValue: .simple)
            _series = State(initialValue: [
                ShotSeries(exerciseType: .freethrow, totalShots: 10, madeShots: 7)
            ])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        modePicker

                        if mode == .simple {
                            simpleForm
                        } else {
                            complexForm
                        }

                        datePicker

                        if mode == .complex {
                            templateSection
                        }

                        saveButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(prefillTemplate != nil ? "Relancer template" : "Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
    }

    // ── Sélecteur de mode ──

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(SessionMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    // ── Formulaire simple ──

    private var simpleForm: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Exercice", icon: "figure.basketball")
                VStack(spacing: 8) {
                    ForEach(ExerciseType.allCases) { ex in
                        ExerciseOptionRow(exercise: ex, isSelected: exercise == ex)
                            .onTapGesture {
                                exercise  = ex
                                madeShots = min(madeShots, totalShots)
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Nombre de tirs", icon: "basketball")
                HStack(spacing: 10) {
                    ForEach(shotOptions, id: \.self) { n in
                        ShotCountChip(count: n, isSelected: totalShots == n)
                            .onTapGesture {
                                totalShots = n
                                madeShots  = min(madeShots, n)
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Tirs réussis", icon: "checkmark.circle")
                HStack {
                    Text("\(madeShots) / \(totalShots)")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .frame(width: 80)
                    Stepper("", value: $madeShots, in: 0...totalShots)
                        .labelsHidden()
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // ── Formulaire complexe ──

    private var complexForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Séries", icon: "list.number")

            ForEach(series.indices, id: \.self) { idx in
                SeriesEditorRow(
                    series: $series[idx],
                    index: idx + 1,
                    onDelete: series.count > 1 ? { series.remove(at: idx) } : nil
                )
            }

            Button {
                series.append(ShotSeries(exerciseType: .freethrow, totalShots: 10, madeShots: 7))
            } label: {
                Label("Ajouter une série", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // ── Date ──

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Date", icon: "calendar")
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // ── Template ──

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $saveAsTemplate) {
                Label("Sauvegarder comme template", systemImage: "rectangle.stack.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .tint(.orange)
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if saveAsTemplate {
                let canAdd = store.templates.count < SessionStore.maxTemplates
                if !canAdd {
                    Label("Limite atteinte (\(SessionStore.maxTemplates)/\(SessionStore.maxTemplates)). Supprime un template existant.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("Nom du template (ex: Entraînement 3pts)", text: $templateName)
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // ── Bouton sauvegarder ──

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Enregistrer la séance")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func save() {
        if mode == .simple {
            var s = WorkoutSession(exerciseType: exercise, totalShots: totalShots, madeShots: madeShots)
            s.date = date
            store.add(s)
        } else {
            let s = WorkoutSession.makeComplex(series: series, date: date)
            store.add(s)

            if saveAsTemplate && !templateName.trimmingCharacters(in: .whitespaces).isEmpty {
                let t = ComplexTemplate(
                    name: templateName.trimmingCharacters(in: .whitespaces),
                    series: series.map { TemplateSeries(exerciseType: $0.exerciseType, totalShots: $0.totalShots, targetMade: $0.targetMade) }
                )
                store.addTemplate(t)
            }
        }
        dismiss()
    }
}

// ─────────────────────────────────────────────────
// Éditeur d'une série (pour séance complexe)
// ─────────────────────────────────────────────────
struct SeriesEditorRow: View {
    @Binding var series: ShotSeries
    let index:    Int
    let onDelete: (() -> Void)?

    private let shotOptions = [5, 10, 15, 20, 25, 30]
    @State private var hasTarget: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Série \(index)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
            }

            // Exercice
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExerciseType.allCases) { ex in
                        Button {
                            series.exerciseType = ex
                        } label: {
                            Text(ex.emoji + " " + ex.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(series.exerciseType == ex ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(series.exerciseType == ex ? Color.orange : Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Nombre de tirs
            HStack(spacing: 6) {
                ForEach(shotOptions, id: \.self) { n in
                    Button {
                        series.totalShots = n
                        series.madeShots  = min(series.madeShots, n)
                    } label: {
                        Text("\(n)")
                            .font(.caption.bold())
                            .foregroundStyle(series.totalShots == n ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(series.totalShots == n ? Color.orange : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Tirs réussis
            HStack {
                Text("Réussis : \(series.madeShots)/\(series.totalShots)")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Stepper("", value: $series.madeShots, in: 0...series.totalShots)
                    .labelsHidden()
            }

            // Objectif paniers (optionnel)
            Toggle("Mode objectif", isOn: $hasTarget)
                .font(.subheadline)
                .onAppear { hasTarget = series.targetMade != nil }
                .onChange(of: hasTarget) { enabled in
                    series.targetMade = enabled ? series.madeShots : nil
                }

            if hasTarget {
                HStack {
                    Text("Objectif paniers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("\(series.targetMade ?? 1)",
                            value: Binding(
                                get: { series.targetMade ?? 1 },
                                set: { series.targetMade = $0 }
                            ),
                            in: 1...100)
                    .labelsHidden()
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
