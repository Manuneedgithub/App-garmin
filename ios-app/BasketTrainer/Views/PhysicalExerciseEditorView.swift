import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITEUR D'EXERCICE PHYSIQUE — nom, type (chrono ou durée fixe),
// et la durée fixe si applicable. Le type n'est modifiable qu'à la
// création : pour un exercice existant, le picker est désactivé.
// ─────────────────────────────────────────────────
struct PhysicalExerciseEditorView: View {
    @EnvironmentObject var physicalStore: PhysicalStore
    @Environment(\.dismiss) var dismiss

    private let exerciseID: UUID
    private let isNew: Bool
    @State private var name: String
    @State private var kind: PhysicalExerciseKind
    @State private var fixedSeconds: Int

    init(exercise: PhysicalExercise?) {
        exerciseID = exercise?.id ?? UUID()
        isNew = exercise == nil
        _name = State(initialValue: exercise?.name ?? "")
        _kind = State(initialValue: exercise?.kind ?? .chrono)
        _fixedSeconds = State(initialValue: exercise?.fixedSeconds ?? 60)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. 100m, Suicide...", text: $name)
                }

                Section {
                    Picker("Type", selection: $kind) {
                        Text("Chrono").tag(PhysicalExerciseKind.chrono)
                        Text("Durée fixe").tag(PhysicalExerciseKind.duration)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!isNew)

                    if kind == .duration {
                        Stepper(PhysicalFormat.duration(fixedSeconds),
                                value: $fixedSeconds,
                                in: PhysicalLibrary.fixedSecondsRange,
                                step: 5)
                    }
                } header: {
                    Text("Type")
                } footer: {
                    if !isNew {
                        Text("Le type ne peut pas être changé après la création.")
                    } else if kind == .chrono {
                        Text("Tu lanceras un chrono et l'arrêteras à la fin de l'exercice.")
                    } else {
                        Text("Un compte à rebours de cette durée se lance, puis tu indiques le nombre de répétitions faites.")
                    }
                }
            }
            .navigationTitle(isNew ? "Nouvel exercice" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(PhysicalLibrary.maxNameLength))
        let exercise = PhysicalExercise(
            id: exerciseID,
            name: trimmed,
            kind: kind,
            fixedSeconds: kind == .duration ? fixedSeconds : nil
        )
        physicalStore.save(exercise)
        dismiss()
    }
}
