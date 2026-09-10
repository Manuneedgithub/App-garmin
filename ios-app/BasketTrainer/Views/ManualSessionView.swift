import SwiftUI

// ─────────────────────────────────────────────────
// SAISIE MANUELLE — Créer une séance simple depuis l'iPhone
// (Les routines multi-séries se pilotent désormais via les
// entraînements montre prédéfinis, cf. SlotsView.)
// ─────────────────────────────────────────────────

struct ManualSessionView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    @State private var date: Date = Date()

    @State private var exercise:   ExerciseType = .freethrow
    @State private var totalShots: Int = 10
    @State private var madeShots:  Int = 7
    @State private var shotType:   ShotType = .catchAndShoot

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

                ScrollView {
                    VStack(spacing: 28) {

                        simpleForm

                        datePicker

                        saveButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
    }

    // ── Formulaire ──

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
                        ForEach(ShotType.allCases, id: \.self) { t in
                            Text(t.name).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
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
        var s = WorkoutSession(exerciseType: exercise, totalShots: totalShots, madeShots: madeShots)
        s.date     = date
        s.shotType = effectiveShotType
        store.add(s)
        dismiss()
    }
}
