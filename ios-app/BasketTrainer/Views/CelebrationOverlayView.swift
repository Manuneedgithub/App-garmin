import SwiftUI

struct CelebrationOverlayView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        if let id = store.pendingCelebrations.first {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text(id.category.icon).font(.system(size: 56))
                    Text("Trophée débloqué !")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(TrophyTier.names[id.tierIndex]) · \(id.category.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Touchez pour continuer")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 4)
                }
                .padding(28)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .contentShape(Rectangle())
            .onTapGesture { store.dismissTopCelebration() }
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.pendingCelebrations.first)
        }
    }
}
