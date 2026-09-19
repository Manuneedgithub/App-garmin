import SwiftUI
import AudioToolbox
import UIKit

// ─────────────────────────────────────────────────
// MINUTEUR DRIBBLE (iPhone) — joue une routine étape par étape.
// Temps calculé sur l'horloge murale (Date) : pas de dérive si l'app
// est ralentie ou passe en arrière-plan.
// ─────────────────────────────────────────────────
struct DribbleTimerView: View {
    @EnvironmentObject var dribbleStore: DribbleStore
    @Environment(\.dismiss) var dismiss

    let routine: DribbleRoutine

    @State private var startDate = Date()
    @State private var elapsed = 0
    @State private var finished = false
    @State private var showQuitConfirm = false

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var state: DribbleTimerState {
        DribbleTimerEngine.state(for: routine.steps, elapsed: elapsed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                if finished { summaryContent } else { runContent }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        if finished || elapsed == 0 { dismiss() } else { showQuitConfirm = true }
                    }
                    .foregroundStyle(.orange)
                }
            }
            .alert("Quitter la routine ?", isPresented: $showQuitConfirm) {
                Button("Continuer", role: .cancel) {}
                Button("Quitter", role: .destructive) { dismiss() }
            } message: {
                Text("La séance en cours ne sera pas enregistrée.")
            }
        }
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(ticker) { _ in tick() }
    }

    // ── Déroulement ──

    private func tick() {
        guard !finished else { return }
        let now = Int(Date().timeIntervalSince(startDate))
        guard now != elapsed else { return }
        let alerts = DribbleTimerEngine.alerts(for: routine.steps, from: elapsed, to: now)
        // Après un long saut (arrière-plan) on ne joue que la dernière alerte, pas une rafale.
        if let last = alerts.last { fire(last) }
        elapsed = now
        if DribbleTimerEngine.state(for: routine.steps, elapsed: now).isFinished {
            finished = true
        }
    }

    private func fire(_ alert: DribbleAlert) {
        switch alert {
        case .stepChanged, .finished:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
        case .countdown:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AudioServicesPlaySystemSound(1104)
        }
    }

    // ── Écran en cours ──

    private var runContent: some View {
        let st = state
        let steps = routine.steps
        let current: DribbleStep? = st.stepIndex < steps.count ? steps[st.stepIndex] : nil
        let next: DribbleStep? = st.stepIndex + 1 < steps.count ? steps[st.stepIndex + 1] : nil
        let total = max(routine.totalSeconds, 1)

        return VStack(spacing: 28) {
            ProgressView(value: Double(min(elapsed, total)), total: Double(total))
                .tint(.orange)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Text("Étape \(min(st.stepIndex + 1, steps.count)) / \(steps.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 10) {
                Text(current?.drill ?? "Repos")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(current?.isRest == true ? Color.blue : Color.orange)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Text(DribbleFormat.clock(st.secondsLeftInStep))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 10) {
                Text("Ensuite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(next.map { $0.drill ?? "Repos" } ?? "Fin de la routine")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let next {
                    Text(DribbleFormat.duration(next.seconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // ── Résumé ──

    private var summaryContent: some View {
        let times = DribbleTimerEngine.drillTimes(for: routine.steps)
        return ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("🎉").font(.system(size: 44))
                    Text("Routine terminée")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text(DribbleFormat.duration(routine.totalSeconds))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 10) {
                    ForEach(times, id: \.drill) { t in
                        HStack {
                            Text(t.drill)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(DribbleFormat.duration(t.seconds))
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
        dribbleStore.add(DribbleSession(
            routineName: routine.name,
            date: startDate,
            totalSeconds: routine.totalSeconds,
            drillTimes: DribbleTimerEngine.drillTimes(for: routine.steps),
            sentFromWatch: false
        ))
        dismiss()
    }
}
