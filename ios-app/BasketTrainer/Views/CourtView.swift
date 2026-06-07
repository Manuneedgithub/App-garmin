import SwiftUI
import UIKit

private struct CourtSpot {
    let type: ExerciseType
    let nx: CGFloat
    let ny: CGFloat
}

// Default layout — used whenever no override exists yet (first launch, or
// any spot the user hasn't repositioned). ny = fraction of the court rect
// from the bottom (0=bottom edge, 1=top edge); mapping: cy = rect.minY
// + (1 - ny) * rect.height. The rect — not the raw canvas — is what's
// proportioned like the photo, so spots line up with its markings
// regardless of the screen's aspect ratio. Drag-and-reposition (below)
// lets the user correct any spot that doesn't quite land on this photo's
// actual lines.
private let courtSpots: [CourtSpot] = [
    CourtSpot(type: .freethrow,    nx: 0.50, ny: 0.70),  // ligne de lancer franc
    CourtSpot(type: .threeCenter,  nx: 0.50, ny: 0.28),  // 3pts sommet de l'arc
    CourtSpot(type: .threeRight45, nx: 0.75, ny: 0.35),  // 3pts aile droite ~45°
    CourtSpot(type: .threeLeft45,  nx: 0.25, ny: 0.35),  // 3pts aile gauche ~45°
    CourtSpot(type: .threeCornerR, nx: 0.93, ny: 0.80),  // 3pts coin droit
    CourtSpot(type: .threeCornerL, nx: 0.07, ny: 0.80),  // 3pts coin gauche
    CourtSpot(type: .midCenter,    nx: 0.50, ny: 0.50),  // mi-distance centre
    CourtSpot(type: .midRight,     nx: 0.74, ny: 0.62),  // mi-distance droite
    CourtSpot(type: .midLeft,      nx: 0.26, ny: 0.62),  // mi-distance gauche
]

struct CourtView: View {
    @EnvironmentObject var store: SessionStore

    @State private var isEditing = false
    @State private var dragOffsets: [ExerciseType: CGSize] = [:]
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let rect = courtRect(in: geo.size)

                    ZStack {
                        Image("CourtDiagram")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        ForEach(courtSpots, id: \.type) { spot in
                            let stats   = store.spotStats(for: spot.type)
                            let pos     = resolvedPosition(for: spot)
                            let baseX   = rect.minX + pos.nx * rect.width
                            let baseY   = rect.minY + (1.0 - pos.ny) * rect.height
                            let offset  = dragOffsets[spot.type] ?? .zero
                            let cx      = baseX + offset.width
                            let cy      = baseY + offset.height
                            let hasData = stats.totalShots > 0
                            let color   = hasData ? spotColor(stats.percentage) : Color(.systemFill)
                            let label   = hasData ? String(format: "%.0f%%", stats.percentage) : "–"

                            Group {
                                if isEditing {
                                    spotBubble(color: color, label: label)
                                        .overlay(
                                            Circle().strokeBorder(Color.orange,
                                                style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                        )
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    dragOffsets[spot.type] = value.translation
                                                }
                                                .onEnded { value in
                                                    let finalX = baseX + value.translation.width
                                                    let finalY = baseY + value.translation.height
                                                    let nx = min(max((finalX - rect.minX) / rect.width, 0), 1)
                                                    let ny = min(max(1 - (finalY - rect.minY) / rect.height, 0), 1)
                                                    store.setSpotPosition(spot.type, nx: nx, ny: ny)
                                                    dragOffsets[spot.type] = nil
                                                }
                                        )
                                } else {
                                    NavigationLink(destination: SpotDetailView(stats: stats)) {
                                        spotBubble(color: color, label: label)
                                    }
                                }
                            }
                            .position(x: cx, y: cy)
                        }
                    }
                }
            }
            .navigationTitle("Terrain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Button(isEditing ? "Terminé" : "Modifier") {
                            isEditing.toggle()
                        }
                        .foregroundStyle(.orange)

                        if isEditing {
                            Button("Réinitialiser") {
                                showResetConfirmation = true
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        legendDot(Color(red: 0.2, green: 0.8, blue: 0.4), "≥70%")
                        legendDot(.orange, "50%")
                        legendDot(Color(red: 1, green: 0.2, blue: 0.2), "<50%")
                    }
                    .font(.caption2)
                }
            }
            .alert("Réinitialiser les positions ?", isPresented: $showResetConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Réinitialiser", role: .destructive) {
                    store.resetSpotPositions()
                }
            } message: {
                Text("Les repères retrouveront leur position d'origine sur le terrain.")
            }
        }
    }

    private func resolvedPosition(for spot: CourtSpot) -> SpotPosition {
        store.spotPositionOverrides[spot.type] ?? SpotPosition(nx: spot.nx, ny: spot.ny)
    }

    @ViewBuilder
    private func spotBubble(color: Color, label: String) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 44, height: 44)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func spotColor(_ pct: Double) -> Color {
        if pct >= 70 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if pct >= 50 { return .orange }
        return Color(red: 1, green: 0.2, blue: 0.2)
    }

    // The image's own proportions define the displayed rect — same
    // centered, aspect-locked approach as the previous drawn-court fix
    // (never stretched), but the aspect ratio now comes from the photo's
    // actual pixel dimensions rather than a hardcoded court constant,
    // because the spots must line up with what's printed on THIS photo.
    private func courtRect(in size: CGSize) -> CGRect {
        let imgSize = UIImage(named: "CourtDiagram")?.size ?? size
        let aspect: CGFloat = imgSize.height == 0 ? 1 : imgSize.width / imgSize.height
        var w = size.width
        var h = w / aspect
        if h > size.height {
            h = size.height
            w = h * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}
