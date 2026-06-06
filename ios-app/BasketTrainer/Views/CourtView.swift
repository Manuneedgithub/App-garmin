import SwiftUI

private struct CourtSpot {
    let type: ExerciseType
    let nx: CGFloat
    let ny: CGFloat
}

// ny = fraction of court height above baseline (0=baseline, 1=top)
// Maps to canvas: cy = (1 - ny) * h
// Court features: FT line at ny≈0.30, arc top at ny≈0.72, arc corners at ny≈0.45
private let courtSpots: [CourtSpot] = [
    CourtSpot(type: .freethrow,    nx: 0.50, ny: 0.30),  // ligne de lancer franc
    CourtSpot(type: .threeCenter,  nx: 0.50, ny: 0.72),  // 3pts sommet de l'arc
    CourtSpot(type: .threeRight45, nx: 0.75, ny: 0.65),  // 3pts aile droite ~45°
    CourtSpot(type: .threeLeft45,  nx: 0.25, ny: 0.65),  // 3pts aile gauche ~45°
    CourtSpot(type: .threeCornerR, nx: 0.93, ny: 0.20),  // 3pts coin droit
    CourtSpot(type: .threeCornerL, nx: 0.07, ny: 0.20),  // 3pts coin gauche
    CourtSpot(type: .midCenter,    nx: 0.50, ny: 0.50),  // mi-distance centre
    CourtSpot(type: .midRight,     nx: 0.74, ny: 0.38),  // mi-distance droite
    CourtSpot(type: .midLeft,      nx: 0.26, ny: 0.38),  // mi-distance gauche
]

struct CourtView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack {
                        courtShape()

                        ForEach(courtSpots, id: \.type) { spot in
                            let stats   = store.spotStats(for: spot.type)
                            let cx      = spot.nx * w
                            let cy      = (1.0 - spot.ny) * h
                            let hasData = stats.totalShots > 0
                            let color   = hasData ? spotColor(stats.percentage) : Color(.systemFill)

                            NavigationLink(destination: SpotDetailView(stats: stats)) {
                                ZStack {
                                    Circle()
                                        .fill(color.opacity(0.9))
                                        .frame(width: 44, height: 44)
                                    Text(hasData
                                         ? String(format: "%.0f%%", stats.percentage)
                                         : "–")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        legendDot(Color(red: 0.2, green: 0.8, blue: 0.4), "≥70%")
                        legendDot(.orange, "50%")
                        legendDot(Color(red: 1, green: 0.2, blue: 0.2), "<50%")
                    }
                    .font(.caption2)
                }
            }
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

    @ViewBuilder
    private func courtShape() -> some View {
        Canvas { ctx, size in
            let cw = size.width
            let ch = size.height
            let cx = cw / 2

            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.17, green: 0.35, blue: 0.11)))

            var border = Path()
            border.addRect(CGRect(x: 4, y: 4, width: cw - 8, height: ch - 8))
            ctx.stroke(border, with: .color(.white.opacity(0.5)), lineWidth: 1.5)

            let paintW: CGFloat = cw * 0.37
            let paintH: CGFloat = ch * 0.30
            var paint = Path()
            paint.addRect(CGRect(x: cx - paintW/2, y: ch - paintH - 4,
                                 width: paintW, height: paintH))
            ctx.stroke(paint, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            var ftCircle = Path()
            ftCircle.addEllipse(in: CGRect(x: cx - paintW/2, y: ch - paintH - 4 - paintW*0.28,
                                            width: paintW, height: paintW * 0.56))
            ctx.stroke(ftCircle, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            var basket = Path()
            basket.addEllipse(in: CGRect(x: cx - 10, y: ch - 24, width: 20, height: 12))
            ctx.stroke(basket, with: .color(.white), lineWidth: 2)

            var arc = Path()
            arc.move(to: CGPoint(x: 4, y: ch * 0.55))
            arc.addQuadCurve(to: CGPoint(x: cw - 4, y: ch * 0.55),
                             control: CGPoint(x: cx, y: ch * 0.02))
            ctx.stroke(arc, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            var cornerL = Path()
            cornerL.move(to: CGPoint(x: 4, y: ch * 0.55))
            cornerL.addLine(to: CGPoint(x: 4, y: ch - 4))
            ctx.stroke(cornerL, with: .color(.white.opacity(0.4)), lineWidth: 1.5)

            var cornerR = Path()
            cornerR.move(to: CGPoint(x: cw - 4, y: ch * 0.55))
            cornerR.addLine(to: CGPoint(x: cw - 4, y: ch - 4))
            ctx.stroke(cornerR, with: .color(.white.opacity(0.4)), lineWidth: 1.5)
        }
    }
}
