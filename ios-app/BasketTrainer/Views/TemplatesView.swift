import SwiftUI

// ─────────────────────────────────────────────────
// TEMPLATES — Séances complexes sauvegardées (max 5)
// Permet de relancer rapidement ou de piloter depuis la montre
// ─────────────────────────────────────────────────
struct TemplatesView: View {
    @EnvironmentObject var store:  SessionStore
    @EnvironmentObject var garmin: GarminManager
    let onLaunchManual: (ComplexTemplate) -> Void
    let onAdd: (() -> Void)?

    init(onLaunchManual: @escaping (ComplexTemplate) -> Void, onAdd: (() -> Void)? = nil) {
        self.onLaunchManual = onLaunchManual
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack {
                Label("Templates complexes", systemImage: "rectangle.stack.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                } else {
                    Text("\(store.templates.count)/\(SessionStore.maxTemplates)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.templates.isEmpty {
                emptyState
            } else {
                ForEach(store.templates) { template in
                    TemplateCard(
                        template: template,
                        onLaunchManual: { onLaunchManual(template) },
                        onDelete:       { store.deleteTemplate(template) }
                    )
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(.title2)
                .foregroundStyle(.orange.opacity(0.5))
            Text("Aucun template sauvegardé")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Crée une séance complexe et active\n\"Sauvegarder comme template\".")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// ─────────────────────────────────────────────────
// Carte d'un template
// ─────────────────────────────────────────────────
struct TemplateCard: View {
    let template:       ComplexTemplate
    let onLaunchManual: () -> Void
    let onDelete:       () -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── En-tête ──
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(template.series.count) série\(template.series.count > 1 ? "s" : "") · \(template.series.reduce(0) { $0 + $1.totalShots }) tirs total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(template.series.indices, id: \.self) { idx in
                    let s = template.series[idx]
                    VStack(spacing: 2) {
                        Text(s.exerciseType.emoji).font(.caption)
                        Text("×\(s.totalShots)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if idx < template.series.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onLaunchManual) {
                    Label("Saisir", systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert("Supprimer ce template ?", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive, action: onDelete)
            Button("Annuler", role: .cancel) {}
        }
    }
}

