import SwiftUI

private struct SlotEditRequest: Identifiable {
    let id: Int
}

struct SlotsView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var editRequest: SlotEditRequest? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<SessionStore.maxWatchSlots, id: \.self) { i in
                        SlotCard(
                            index: i,
                            template: store.watchSlots[i],
                            isConnected: garmin.connectedDevice != nil,
                            onEdit: { editRequest = SlotEditRequest(id: i) },
                            onSend: {
                                if let t = store.watchSlots[i] {
                                    garmin.sendSlot(i, template: t)
                                }
                            }
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Entraînements montre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
            .sheet(item: $editRequest) { req in
                SlotEditorView(index: req.id, existing: store.watchSlots[req.id])
                    .environmentObject(store)
            }
            .alert("Envoi à la montre", isPresented: Binding(
                get: { garmin.lastSlotSendMessage != nil },
                set: { if !$0 { garmin.lastSlotSendMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garmin.lastSlotSendMessage ?? "")
            }
        }
    }
}

private struct SlotCard: View {
    let index:       Int
    let template:    ComplexTemplate?
    let isConnected: Bool
    let onEdit:      () -> Void
    let onSend:      () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Entraînement \(index + 1)")
                    .font(.headline)
                Spacer()
                if let t = template {
                    Text("\(t.series.count) séries")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }

            if let t = template {
                ForEach(t.series.indices, id: \.self) { j in
                    HStack(spacing: 6) {
                        Text(t.series[j].exerciseType.emoji)
                        Text(t.series[j].exerciseType.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(t.series[j].totalShots) tirs")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(t.series[j].shotType.name)
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                Text("(vide — appuyer sur Modifier pour configurer)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Modifier", action: onEdit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)

                Spacer()

                Button(action: onSend) {
                    Label("Envoyer", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(template != nil && isConnected ? Color.orange : Color(.systemFill))
                        .clipShape(Capsule())
                }
                .disabled(template == nil || !isConnected)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SlotEditorView: View {
    let index: Int
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    @State private var seriesList: [TemplateSeries]
    private let maxSeries = 6

    init(index: Int, existing: ComplexTemplate?) {
        self.index = index
        _seriesList = State(initialValue:
            existing?.series ?? [TemplateSeries(exerciseType: .freethrow, totalShots: 10)]
        )
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Effacer le slot") {
                        store.setWatchSlot(index, template: nil)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Entraînement \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sauvegarder") {
                        let t = ComplexTemplate(
                            name: "Entraînement \(index + 1)",
                            series: seriesList
                        )
                        store.setWatchSlot(index, template: t)
                        dismiss()
                    }
                    .disabled(seriesList.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.orange)
                }
            }
        }
    }
}
