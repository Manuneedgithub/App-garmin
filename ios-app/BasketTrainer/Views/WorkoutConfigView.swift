import SwiftUI

// ─────────────────────────────────────────────────
// CONFIG ENTRAÎNEMENT — Envoi depuis l'iPhone
// (La montre peut aussi faire ça en autonome)
// ─────────────────────────────────────────────────
struct WorkoutConfigView: View {
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedExercise: ExerciseType = .freethrow
    @State private var shotCount: Int = 10
    @State private var didSend = false

    private let shotOptions = [5, 10, 15, 20, 25, 30]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        // ── Choix exercice ──
                        sectionExercise

                        // ── Choix nb tirs ──
                        sectionShotCount

                        // ── Bouton envoyer ──
                        sendButton

                        if didSend {
                            sentConfirmation
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Configurer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // ── Sections ──

    private var sectionExercise: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Exercice", icon: "figure.basketball")

            VStack(spacing: 8) {
                ForEach(ExerciseType.allCases) { exercise in
                    ExerciseOptionRow(
                        exercise: exercise,
                        isSelected: selectedExercise == exercise
                    )
                    .onTapGesture { selectedExercise = exercise }
                }
            }
        }
    }

    private var sectionShotCount: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Nombre de tirs", icon: "basketball")

            HStack(spacing: 10) {
                ForEach(shotOptions, id: \.self) { n in
                    ShotCountChip(count: n, isSelected: shotCount == n)
                        .onTapGesture { shotCount = n }
                }
            }
        }
    }

    private var sendButton: some View {
        Button {
            garmin.sendWorkoutConfig(exerciseId: selectedExercise.rawValue, totalShots: shotCount)
            withAnimation { didSend = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { didSend = false }
            }
        } label: {
            HStack {
                Image(systemName: "applewatch")
                Text("Envoyer sur la montre")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(garmin.isConnected ? Color.orange : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!garmin.isConnected)
    }

    private var sentConfirmation: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Envoyé ! Lance l'app sur ta montre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// ─────────────────────────────────────────────────
// Sous-composants
// ─────────────────────────────────────────────────

struct SectionLabel: View {
    let title: String
    let icon:  String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.white)
    }
}

struct ExerciseOptionRow: View {
    let exercise:   ExerciseType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(exercise.emoji)
                .font(.title3)
            Text(exercise.name)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .black : .white)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.orange : Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ShotCountChip: View {
    let count:      Int
    let isSelected: Bool

    var body: some View {
        Text("\(count)")
            .font(.subheadline.bold())
            .foregroundStyle(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.orange : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
