import SwiftUI

// ─────────────────────────────────────────────────
// AIDE — Installation & connexion de la montre Garmin
// Ouvert depuis le bouton "Connecter" de l'accueil.
// ─────────────────────────────────────────────────
struct WatchSetupView: View {
    @EnvironmentObject var garmin: GarminManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        header

                        VStack(spacing: 14) {
                            SetupStep(
                                number: 1,
                                icon: "link.circle.fill",
                                title: "Associer la montre",
                                text: "Ouvre l'app Garmin Connect sur ton iPhone et associe ta Forerunner 255 à ton compte, si ce n'est pas déjà fait."
                            )
                            SetupStep(
                                number: 2,
                                icon: "arrow.down.doc.fill",
                                title: "Installer Basket Trainer sur la montre",
                                text: "Cette app n'est pas sur le Connect IQ Store — elle doit être copiée manuellement. Compile le projet (VS Code → \"Monkey C: Build for Device\"), puis copie le fichier .prg obtenu dans le dossier GARMIN/APPS de la montre connectée en USB."
                            )
                            SetupStep(
                                number: 3,
                                icon: "applewatch",
                                title: "Ouvrir l'app sur la montre",
                                text: "Lance \"Basket Trainer\" au moins une fois depuis le menu de la montre, pour qu'elle commence à écouter les messages venant du téléphone."
                            )
                            SetupStep(
                                number: 4,
                                icon: "wifi",
                                title: "Vérifier le Bluetooth",
                                text: "Assure-toi que le Bluetooth est activé sur l'iPhone et que la montre reste à proximité pendant la connexion."
                            )
                        }

                        statusRow

                        Spacer(minLength: 20)

                        connectButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Connexion montre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }.foregroundStyle(.orange)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Connecter ta Forerunner 255")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text("Suis ces étapes une première fois — la connexion se refera ensuite automatiquement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(garmin.connectedDevice != nil ? Color.green : Color(.tertiaryLabel))
                .frame(width: 8, height: 8)
            Text(garmin.connectedDevice != nil ? "Montre connectée" : "Montre non connectée")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var connectButton: some View {
        Button {
            garmin.connectWatch()
        } label: {
            HStack {
                Image(systemName: "applewatch")
                Text("Connecter")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
