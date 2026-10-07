import SwiftUI
import AudioToolbox
import UIKit

// ─────────────────────────────────────────────────
// EXERCICE PHYSIQUE (iPhone) — chrono (temps mesuré) ou minuteur à
// durée fixe (répétitions comptées). Horloge murale (Date), comme
// les routines de dribble : pas de dérive si l'app ralentit.
// ─────────────────────────────────────────────────
struct PhysicalRunView: View {
    @EnvironmentObject var physicalStore: PhysicalStore
    @Environment(\.dismiss) var dismiss

    let exercise: PhysicalExercise

    private enum Phase: Equatable {
        case idle            // prêt pour la prochaine tentative
        case runningChrono   // chrono en cours
        case countdown       // compte à rebours (durée fixe)
        case enteringReps    // compte à rebours terminé, saisie des répétitions
        case summary         // séance terminée, récapitulatif + enregistrement
    }

    @State private var phase: Phase = .idle
    @State private var attempts: [PhysicalAttempt] = []
    @State private var sessionStart = Date()
    @State private var attemptStart = Date()
    @State private var elapsed: Double = 0
    @State private var repsInput = 0
    @State private var showQuitConfirm = false

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                switch phase {
                case .idle:            idleContent
                case .runningChrono:   chronoContent
                case .countdown:       countdownContent
                case .enteringReps:    repsContent
                case .summary:         summaryContent
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        if attempts.isEmpty { dismiss() } else { showQuitConfirm = true }
                    }
                    .foregroundStyle(.orange)
                }
            }
            .alert("Quitter sans enregistrer ?", isPresented: $showQuitConfirm) {
                Button("Continuer", role: .cancel) {}
                Button("Quitter", role: .destructive) { dismiss() }
            } message: {
                Text("Les tentatives déjà faites ne seront pas enregistrées.")
            }
        }
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(ticker) { _ in tick() }
    }

    // ── Déroulement ──

    private func tick() {
        guard phase == .runningChrono || phase == .countdown else { return }
        elapsed = Date().timeIntervalSince(attemptStart)
        if phase == .countdown, let fixed = exercise.fixedSeconds,
           PhysicalTimer.isFinished(fixedSeconds: fixed, elapsed: elapsed) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
            repsInput = 0
            phase = .enteringReps
        }
    }

    private func startAttempt() {
        if attempts.isEmpty { sessionStart = Date() }
        attemptStart = Date()
        elapsed = 0
        phase = exercise.kind == .duration ? .countdown : .runningChrono
    }

    private func stopChrono() {
        let exact = Date().timeIntervalSince(attemptStart)
        attempts.append(PhysicalAttempt(seconds: exact, reps: nil))
        phase = .idle
    }

    private func confirmReps() {
        attempts.append(PhysicalAttempt(seconds: nil, reps: repsInput))
        phase = .idle
    }

    // ── Écrans ──

    private var idleContent: some View {
        VStack(spacing: 28) {
            attemptsList
            Spacer()
            VStack(spacing: 10) {
                Text(exercise.kind == .chrono ? "Prêt pour le chrono" : "Prêt pour le minuteur")
                    .font(.headline)
                if exercise.kind == .duration, let fixed = exercise.fixedSeconds {
                    Text(PhysicalFormat.duration(fixed))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                startAttempt()
            } label: {
                Text(attempts.isEmpty ? "Démarrer" : "Nouvelle tentative")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)

            if !attempts.isEmpty {
                Button("Terminer") { phase = .summary }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 20)
        }
        .padding(.top, 16)
    }

    private var chronoContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(PhysicalFormat.runningClock(elapsed))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Spacer()
            Button {
                stopChrono()
            } label: {
                Text("Arrêter")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var countdownContent: some View {
        let fixed = exercise.fixedSeconds ?? 0
        let remaining = PhysicalTimer.secondsRemaining(fixedSeconds: fixed, elapsed: elapsed)
        return VStack(spacing: 28) {
            Spacer()
            Text("\(remaining)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(remaining <= 3 ? Color.red : Color.primary)
            Text("secondes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var repsContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Combien de répétitions ?")
                .font(.headline)
            Text("\(repsInput)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
            Stepper("", value: $repsInput, in: 0...PhysicalLibrary.maxRepsPerAttempt)
                .labelsHidden()
            Spacer()
            Button {
                confirmReps()
            } label: {
                Text("Valider")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var attemptsList: some View {
        Group {
            if !attempts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tentatives")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    ForEach(attempts.indices, id: \.self) { i in
                        HStack {
                            Text("#\(i + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(attemptLabel(attempts[i]))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func attemptLabel(_ attempt: PhysicalAttempt) -> String {
        if let s = attempt.seconds { return PhysicalFormat.chronoResult(s) }
        if let r = attempt.reps { return PhysicalFormat.repsResult(r) }
        return "—"
    }

    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("🎉").font(.system(size: 44))
                    Text("Séance terminée")
                        .font(.title3.bold())
                    Text("\(attempts.count) tentative\(attempts.count > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 10) {
                    ForEach(attempts.indices, id: \.self) { i in
                        HStack {
                            Text("Tentative \(i + 1)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(attemptLabel(attempts[i]))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    save()
                } label: {
                    Text("Enregistrer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func save() {
        physicalStore.add(PhysicalSession(
            exerciseName: exercise.name,
            kind: exercise.kind,
            date: sessionStart,
            attempts: attempts,
            sentFromWatch: false
        ))
        dismiss()
    }
}
