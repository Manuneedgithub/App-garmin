import SwiftUI

private struct CourtSpot {
    let type: ExerciseType
    let nx: CGFloat
    let ny: CGFloat
}

// Court is drawn with the basket at the TOP (baseline at top edge),
// matching the reference half-court diagram. ny = screen fraction from
// the bottom (0=bottom edge, 1=top edge); canvas mapping: cy = (1 - ny) * h
// Court features: baseline/basket near ny≈1.0, FT line at ny≈0.70,
// arc corners at ny≈0.55, arc apex (deepest point) at ny≈0.28
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

    // Half-court diagram drawn with the basket at the TOP (baseline at the
    // top edge), wood/parquet floor, white markings — mirrors the reference
    // photo. All y-coordinates are the vertical flip (ch - y) of the
    // previous bottom-basket layout, which is why courtSpots use ny' = 1 - ny.
    @ViewBuilder
    private func courtShape() -> some View {
        Canvas { ctx, size in
            let cw = size.width
            let ch = size.height
            let cx = cw / 2

            // Wood / parquet floor base color
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.80, green: 0.67, blue: 0.46)))

            // Subtle plank lines for wood-grain texture
            let plankCount = 9
            for i in 1..<plankCount {
                let x = cw * CGFloat(i) / CGFloat(plankCount)
                var plank = Path()
                plank.move(to: CGPoint(x: x, y: 4))
                plank.addLine(to: CGPoint(x: x, y: ch - 4))
                ctx.stroke(plank,
                           with: .color(Color(red: 0.70, green: 0.56, blue: 0.36).opacity(0.35)),
                           lineWidth: 1)
            }

            let lineColor = Color.white.opacity(0.85)

            var border = Path()
            border.addRect(CGRect(x: 4, y: 4, width: cw - 8, height: ch - 8))
            ctx.stroke(border, with: .color(lineColor), lineWidth: 1.5)

            // Baseline — top edge, drawn slightly heavier
            var baseline = Path()
            baseline.move(to: CGPoint(x: 4, y: 4))
            baseline.addLine(to: CGPoint(x: cw - 4, y: 4))
            ctx.stroke(baseline, with: .color(lineColor), lineWidth: 2.5)

            // Paint / key — extends down from the baseline
            let paintW: CGFloat = cw * 0.37
            let paintH: CGFloat = ch * 0.30
            var paint = Path()
            paint.addRect(CGRect(x: cx - paintW/2, y: 4, width: paintW, height: paintH))
            ctx.stroke(paint, with: .color(lineColor), lineWidth: 1.5)

            // Free-throw circle — straddles the open (bottom) edge of the paint
            var ftCircle = Path()
            ftCircle.addEllipse(in: CGRect(x: cx - paintW/2, y: 4 + paintH - paintW * 0.28,
                                            width: paintW, height: paintW * 0.56))
            ctx.stroke(ftCircle, with: .color(lineColor), lineWidth: 1.5)

            // Backboard + basket, just below the baseline
            var backboard = Path()
            backboard.move(to: CGPoint(x: cx - 16, y: 12))
            backboard.addLine(to: CGPoint(x: cx + 16, y: 12))
            ctx.stroke(backboard, with: .color(.white), lineWidth: 2.5)

            var basket = Path()
            basket.addEllipse(in: CGRect(x: cx - 10, y: 18, width: 20, height: 12))
            ctx.stroke(basket, with: .color(.white), lineWidth: 2)

            // 3-point arc — corners near the baseline, apex toward mid-court
            var arc = Path()
            arc.move(to: CGPoint(x: 4, y: ch * 0.45))
            arc.addQuadCurve(to: CGPoint(x: cw - 4, y: ch * 0.45),
                             control: CGPoint(x: cx, y: ch * 0.98))
            ctx.stroke(arc, with: .color(lineColor), lineWidth: 1.5)

            var cornerL = Path()
            cornerL.move(to: CGPoint(x: 4, y: ch * 0.45))
            cornerL.addLine(to: CGPoint(x: 4, y: 4))
            ctx.stroke(cornerL, with: .color(lineColor), lineWidth: 1.5)

            var cornerR = Path()
            cornerR.move(to: CGPoint(x: cw - 4, y: ch * 0.45))
            cornerR.addLine(to: CGPoint(x: cw - 4, y: 4))
            ctx.stroke(cornerR, with: .color(lineColor), lineWidth: 1.5)

            // Center-court circle — only its top arc peeks in at the bottom edge
            let centerR: CGFloat = cw * 0.22
            var centerCircle = Path()
            centerCircle.addEllipse(in: CGRect(x: cx - centerR, y: ch - centerR * 0.6,
                                                width: centerR * 2, height: centerR * 2))
            ctx.stroke(centerCircle, with: .color(lineColor), lineWidth: 1.5)
        }
    }
}
