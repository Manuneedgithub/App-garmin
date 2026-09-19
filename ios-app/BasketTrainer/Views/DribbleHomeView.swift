import SwiftUI

// ─────────────────────────────────────────────────
// DRIBBLE — bibliothèque de routines : lancer, modifier, envoyer à la montre.
// ─────────────────────────────────────────────────
private struct DribbleEditorTarget: Identifiable {
    let id = UUID()
    let routine: DribbleRoutine?      // nil = nouvelle routine
}

struct DribbleHomeView: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var editorTarget: DribbleEditorTarget? = nil
    @State private var runningRoutine: DribbleRoutine? = nil

    var body: some View {
        NavigationStack {
            Group {
                if dribbleStore.routines.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(dribbleStore.routines) { routine in
                            routineRow(routine)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dribble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        DribbleHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button {
                        editorTarget = DribbleEditorTarget(routine: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                DribbleRoutineEditorView(routine: target.routine)
            }
            .fullScreenCover(item: $runningRoutine) { routine in
                DribbleTimerView(routine: routine)
            }
            .alert("Envoi à la montre", isPresented: Binding(
                get: { garmin.lastDribbleSlotSendMessage != nil },
                set: { if !$0 { garmin.lastDribbleSlotSendMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garmin.lastDribbleSlotSendMessage ?? "")
            }
        }
    }

    private func routineRow(_ routine: DribbleRoutine) -> some View {
        HStack(spacing: 12) {
            Button {
                runningRoutine = routine
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(routine.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(routine.steps.count) étapes · \(DribbleFormat.duration(routine.totalSeconds))")
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
                Button("Modifier") { editorTarget = DribbleEditorTarget(routine: routine) }
                Menu("Envoyer à la montre") {
                    ForEach(0..<DribbleStore.watchSlotCount, id: \.self) { i in
                        Button("Emplacement \(i + 1) — \(dribbleStore.watchSlots[i]?.name ?? "vide")") {
                            dribbleStore.setWatchSlot(i, routine: routine)
                            garmin.sendDribbleSlot(i, routine: routine)
                        }
                    }
                }
                Button("Supprimer", role: .destructive) { dribbleStore.delete(routine) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🏀").font(.system(size: 52))
            Text("Aucune routine")
                .font(.title3.bold())
            Text("Enchaîne des exercices de dribble et des repos, par exemple 30 s cross, 10 s repos, 30 s behind the back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                editorTarget = DribbleEditorTarget(routine: nil)
            } label: {
                Label("Créer une routine", systemImage: "plus.circle.fill")
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
