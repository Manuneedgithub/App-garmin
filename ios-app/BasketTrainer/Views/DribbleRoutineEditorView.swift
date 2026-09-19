import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITEUR DE ROUTINE DRIBBLE — nom + liste ordonnée d'étapes
// (exercice + durée, ou repos + durée).
// ─────────────────────────────────────────────────
struct DribbleRoutineEditorView: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @Environment(\.dismiss) var dismiss

    private let routineID: UUID
    @State private var name: String
    @State private var steps: [DribbleStep]
    @State private var showDrillPicker = false

    init(routine: DribbleRoutine?) {
        routineID = routine?.id ?? UUID()
        _name  = State(initialValue: routine?.name ?? "")
        _steps = State(initialValue: routine?.steps ?? [])
    }

    private var canAddStep: Bool { steps.count < DribbleLibrary.maxSteps }
    private var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. Routine handle 5 min", text: $name)
                }

                Section {
                    ForEach($steps) { $step in
                        DribbleStepRow(step: $step)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showDrillPicker = true
                    } label: {
                        Label("Ajouter un exercice", systemImage: "plus.circle")
                            .foregroundStyle(.orange)
                    }
                    .disabled(!canAddStep)

                    Button {
                        steps.append(DribbleStep(seconds: 10))
                    } label: {
                        Label("Ajouter un repos", systemImage: "pause.circle")
                            .foregroundStyle(.orange)
                    }
                    .disabled(!canAddStep)
                } header: {
                    Text("Étapes (\(steps.count)/\(DribbleLibrary.maxSteps))")
                } footer: {
                    if !steps.isEmpty {
                        Text("Durée totale : \(DribbleFormat.duration(totalSeconds))")
                    }
                }
            }
            .navigationTitle(routineTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                    EditButton().foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showDrillPicker) {
                DribbleDrillPickerSheet { drillName in
                    steps.append(DribbleStep(drill: drillName, seconds: 30))
                }
            }
        }
    }

    private var routineTitle: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Nouvelle routine" : name
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        dribbleStore.save(DribbleRoutine(id: routineID, name: trimmed, steps: steps))
        dismiss()
    }
}

private struct DribbleStepRow: View {
    @Binding var step: DribbleStep

    var body: some View {
        HStack {
            if let drill = step.drill {
                Image(systemName: "figure.basketball").foregroundStyle(.orange)
                Text(drill).lineLimit(1)
            } else {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
                Text("Repos").foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(DribbleFormat.duration(step.seconds),
                    value: $step.seconds,
                    in: DribbleLibrary.stepSecondsRange,
                    step: 5)
                .fixedSize()
        }
    }
}

// Liste des exercices (fournis + perso) avec création d'un nouvel exercice.
private struct DribbleDrillPickerSheet: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @Environment(\.dismiss) var dismiss
    let onPick: (String) -> Void

    @State private var showNewDrill = false
    @State private var newDrillName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(dribbleStore.allDrills, id: \.self) { drill in
                        Button {
                            onPick(drill)
                            dismiss()
                        } label: {
                            Text(drill).foregroundStyle(.primary)
                        }
                    }
                }
                Section {
                    Button {
                        newDrillName = ""
                        showNewDrill = true
                    } label: {
                        Label("Nouvel exercice…", systemImage: "plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
            .alert("Nouvel exercice", isPresented: $showNewDrill) {
                TextField("Nom (ex. Spider dribble)", text: $newDrillName)
                Button("Annuler", role: .cancel) {}
                Button("Ajouter") {
                    if let name = dribbleStore.resolveDrill(newDrillName) {
                        onPick(name)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
