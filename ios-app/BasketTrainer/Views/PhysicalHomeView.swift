import SwiftUI

// ─────────────────────────────────────────────────
// PHYSIQUE — bibliothèque d'exercices : lancer, modifier, envoyer à la montre.
// ─────────────────────────────────────────────────
private struct PhysicalEditorTarget: Identifiable {
    let id = UUID()
    let exercise: PhysicalExercise?      // nil = nouvel exercice
}

struct PhysicalHomeView: View {
    @EnvironmentObject var physicalStore: PhysicalStore
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var editorTarget: PhysicalEditorTarget? = nil
    @State private var runningExercise: PhysicalExercise? = nil

    var body: some View {
        NavigationStack {
            Group {
                if physicalStore.exercises.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(physicalStore.exercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Physique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        PhysicalHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button {
                        editorTarget = PhysicalEditorTarget(exercise: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                PhysicalExerciseEditorView(exercise: target.exercise)
            }
            .fullScreenCover(item: $runningExercise) { exercise in
                PhysicalRunView(exercise: exercise)
            }
            .alert("Envoi à la montre", isPresented: Binding(
                get: { garmin.lastPhysicalSlotSendMessage != nil },
                set: { if !$0 { garmin.lastPhysicalSlotSendMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garmin.lastPhysicalSlotSendMessage ?? "")
            }
        }
    }

    private func exerciseRow(_ exercise: PhysicalExercise) -> some View {
        HStack(spacing: 12) {
            Button {
                runningExercise = exercise
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(kindLabel(exercise))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }
            .buttonStyle(.borderless)

            Menu {
                Button("Modifier") { editorTarget = PhysicalEditorTarget(exercise: exercise) }
                Menu("Envoyer à la montre") {
                    ForEach(0..<PhysicalStore.watchSlotCount, id: \.self) { i in
                        Button("Emplacement \(i + 1) — \(physicalStore.watchSlots[i]?.name ?? "vide")") {
                            physicalStore.setWatchSlot(i, exercise: exercise)
                            garmin.sendPhysicalSlot(i, exercise: exercise)
                        }
                    }
                }
                Button("Supprimer", role: .destructive) { physicalStore.delete(exercise) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func kindLabel(_ exercise: PhysicalExercise) -> String {
        switch exercise.kind {
        case .chrono:
            return "Chrono"
        case .duration:
            let seconds = exercise.fixedSeconds ?? 0
            return "Durée fixe · \(PhysicalFormat.duration(seconds))"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🏃").font(.system(size: 52))
            Text("Aucun exercice")
                .font(.title3.bold())
            Text("Ajoute un exercice chronométré (25m, 100m, suicide...) ou à durée fixe (1 min aller-retour...).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                editorTarget = PhysicalEditorTarget(exercise: nil)
            } label: {
                Label("Ajouter un exercice", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
    }
}
