import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITEUR DE SPOT PERSONNALISÉ — création et modification
// ─────────────────────────────────────────────────

struct CustomSpotEditorView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    let editingSpot: CustomSpot?     // nil = création, sinon = modification
    let courtIndex: Int

    @State private var name: String
    @State private var emoji: String
    @State private var showDeleteConfirmation = false

    init(editingSpot: CustomSpot?, courtIndex: Int) {
        self.editingSpot = editingSpot
        self.courtIndex  = courtIndex
        _name  = State(initialValue: editingSpot?.name  ?? "")
        _emoji = State(initialValue: editingSpot?.emoji ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. Angle gauche profond", text: $name)
                }
                Section("Icône") {
                    TextField("Emoji", text: $emoji)
                        .onChange(of: emoji) { _ in emoji = String(emoji.suffix(1)) }
                }
                if editingSpot != nil {
                    Section {
                        Button("Supprimer ce spot", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(editingSpot == nil ? "Nouveau spot" : "Modifier le spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .foregroundStyle(.orange)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || emoji.isEmpty)
                }
            }
            .alert("Supprimer ce spot ?", isPresented: $showDeleteConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Supprimer", role: .destructive) { delete() }
            } message: {
                Text("Les séances déjà enregistrées resteront dans l'historique, mais ce spot ne sera plus affiché sur le terrain ni sur la montre une fois synchronisé.")
            }
        }
    }

    private func save() {
        guard let id = editingSpot?.id ?? store.nextAvailableCustomSpotID() else { return }
        let position = editingSpot?.position ?? SpotPosition(nx: 0.5, ny: 0.5)
        store.saveCustomSpot(CustomSpot(id: id, name: name, emoji: emoji,
                                        courtIndex: courtIndex, position: position))
        dismiss()
    }

    private func delete() {
        guard let spot = editingSpot else { return }
        store.deleteCustomSpot(id: spot.id)
        dismiss()
    }
}
