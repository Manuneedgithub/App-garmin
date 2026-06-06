import SwiftUI

struct RoutineBuilderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: SessionStore

    @State private var name = ""
    @State private var seriesList: [TemplateSeries] = [
        TemplateSeries(exerciseType: .freethrow, totalShots: 10)
    ]

    private let maxSeries = 6

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("ex. Matin court", text: $name)
                }
                Section("Séries (\(seriesList.count)/\(maxSeries))") {
                    ForEach(seriesList.indices, id: \.self) { idx in
                        SeriesRow(series: $seriesList[idx])
                    }
                    .onDelete { offsets in
                        seriesList.remove(atOffsets: offsets)
                    }
                    if seriesList.count < maxSeries {
                        Button {
                            seriesList.append(
                                TemplateSeries(exerciseType: .freethrow, totalShots: 10)
                            )
                        } label: {
                            Label("Ajouter une série", systemImage: "plus.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Nouvelle routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sauvegarder") {
                        let template = ComplexTemplate(
                            name: name.isEmpty ? "Routine" : name,
                            series: seriesList
                        )
                        store.addTemplate(template)
                        dismiss()
                    }
                    .disabled(seriesList.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundStyle(seriesList.isEmpty ? .secondary : .orange)
                }
            }
        }
    }
}

struct SeriesRow: View {
    @Binding var series: TemplateSeries
    @State private var showPicker = false

    var body: some View {
        HStack {
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 8) {
                    Text(series.exerciseType.emoji)
                    Text(series.exerciseType.name)
                        .foregroundStyle(.primary)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerSheet(selected: $series.exerciseType)
            }
            Spacer()
            Stepper(
                "\(series.totalShots) tirs",
                value: $series.totalShots,
                in: 1...100
            )
            .fixedSize()
        }
    }
}

struct ExercisePickerSheet: View {
    @Binding var selected: ExerciseType
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(ExerciseType.allCases) { type in
                Button {
                    selected = type
                    dismiss()
                } label: {
                    HStack {
                        Text(type.emoji)
                        Text(type.name).foregroundStyle(.primary)
                        Spacer()
                        if selected == type {
                            Image(systemName: "checkmark").foregroundStyle(.orange)
                        }
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
        }
    }
}
