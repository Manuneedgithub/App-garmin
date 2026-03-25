import SwiftUI

// ─────────────────────────────────────────────────
// ÉDITION D'UNE SÉANCE — Modifier une séance existante
// ─────────────────────────────────────────────────
struct EditSessionView: View {
    let session: WorkoutSession
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    @State private var editedSession: WorkoutSession

    init(session: WorkoutSession) {
        self.session = session
        self._editedSession = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        if let series = editedSession.series, series.count > 1 {
                            complexEditor(series)
                        } else {
                            simpleEditor
                        }

                        datePicker

                        saveButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Modifier la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
    }

    // ── Éditeur simple ──

    private var simpleEditor: some View {
        VStack(spacing: 24) {

            // Résumé exercice (non modifiable)
            HStack(spacing: 14) {
                Text(editedSession.exerciseType.emoji)
                    .font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(editedSession.exerciseType.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(editedSession.totalShots) tirs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Tirs réussis
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Tirs réussis", icon: "checkmark.circle")

                VStack(spacing: 12) {
                    HStack {
                        Text("\(editedSession.madeShots) / \(editedSession.totalShots)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 80)
                        Stepper("", value: $editedSession.madeShots, in: 0...editedSession.totalShots)
                            .labelsHidden()
                    }

                    // Barre visuelle
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(pctColor(editedSession.percentage))
                                .frame(width: geo.size.width * CGFloat(editedSession.madeShots) / CGFloat(max(1, editedSession.totalShots)), height: 8)
                                .animation(.easeInOut(duration: 0.2), value: editedSession.madeShots)
                        }
                    }
                    .frame(height: 8)

                    Text(String(format: "%.0f%%", editedSession.percentage))
                        .font(.title3.bold())
                        .foregroundStyle(pctColor(editedSession.percentage))
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // ── Éditeur complexe ──

    private func complexEditor(_ series: [ShotSeries]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Séries", icon: "list.number")

            ForEach(series.indices, id: \.self) { idx in
                let ser = series[idx]
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(ser.exerciseType.emoji) Série \(idx + 1) — \(ser.exerciseType.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(ser.totalShots) tirs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("\(ser.madeShots)/\(ser.totalShots)")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 70)
                        Stepper("", value: Binding(
                            get: { editedSession.series?[idx].madeShots ?? 0 },
                            set: { editedSession.series?[idx].madeShots = $0 }
                        ), in: 0...ser.totalShots)
                            .labelsHidden()
                        Spacer()
                        Text(String(format: "%.0f%%", ser.percentage))
                            .font(.subheadline.bold())
                            .foregroundStyle(pctColor(ser.percentage))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // ── Date ──

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Date", icon: "calendar")
            DatePicker("", selection: $editedSession.date, in: ...Date(),
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // ── Bouton sauvegarder ──

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Enregistrer les modifications")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func save() {
        // Recalculer totalMade et totalShots depuis les séries si complexe
        if var series = editedSession.series, series.count > 1 {
            editedSession.madeShots  = series.reduce(0) { $0 + $1.madeShots }
            editedSession.totalShots = series.reduce(0) { $0 + $1.totalShots }
            editedSession.series     = series
        }
        store.update(editedSession)
        dismiss()
    }

    private func pctColor(_ pct: Double) -> Color {
        if pct >= 70 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }
}
