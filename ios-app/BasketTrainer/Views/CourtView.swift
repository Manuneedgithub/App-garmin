import SwiftUI
import UIKit

private struct CourtSpot {
    let type: ExerciseType
    let nx: CGFloat
    let ny: CGFloat
}

// Default layout for the main shooting court — used whenever no override
// exists yet (first launch, or any spot the user hasn't repositioned).
// ny = fraction of the court rect from the bottom (0=bottom edge, 1=top
// edge); mapping: cy = rect.minY + (1 - ny) * rect.height. The rect — not
// the raw canvas — is what's proportioned like the photo, so spots line up
// with its markings regardless of the screen's aspect ratio. Drag-and-
// reposition (below) lets the user correct any spot that doesn't quite
// land on this photo's actual lines.
private let shootingSpots: [CourtSpot] = [
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

// Technique spots — Flotteur et Form Shot Side to Side se travaillent tous
// les deux près du cercle, donc ils démarrent côte à côte dans la raquette.
private let techniqueSpots: [CourtSpot] = [
    CourtSpot(type: .floater,            nx: 0.38, ny: 0.85),
    CourtSpot(type: .formShotSideToSide, nx: 0.62, ny: 0.85),
]

// Période de filtrage des repères — même esprit que StatsPeriod (StatsView),
// mais avec les bornes demandées pour le terrain : aujourd'hui, 7 jours,
// 1 mois, tout.
private enum CourtPeriod: String, CaseIterable {
    case today = "Auj."
    case week  = "7j"
    case month = "1 mois"
    case all   = "Tout"

    func startDate() -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today: return cal.startOfDay(for: now)
        case .week:  return cal.date(byAdding: .day,   value: -7, to: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now)
        case .all:   return nil
        }
    }
}

private struct CourtPage {
    let title:    String
    let subtitle: String
    let spots:    [CourtSpot]
}

// Trois terrains défilables : zones de tir, zones technique, et un terrain
// vierge réservé pour une future catégorie d'exercice.
private let courtPages: [CourtPage] = [
    CourtPage(title: "Zones de tir",
              subtitle: "Lancer franc · 3 points · mi-distance",
              spots: shootingSpots),
    CourtPage(title: "Technique",
              subtitle: "Flotteur · Form Shot Side to Side",
              spots: techniqueSpots),
    CourtPage(title: "Réservé",
              subtitle: "Bientôt disponible",
              spots: []),
]

// Looké une seule fois au niveau du fichier — la taille de la photo ne
// change jamais, donc chaque page partage le même calcul sans requêter
// UIImage(named:) à répétition.
private let courtImageSize: CGSize = UIImage(named: "CourtDiagram")?.size ?? CGSize(width: 1, height: 1)
private let courtAspectRatio: CGFloat = courtImageSize.height == 0
    ? 1 : courtImageSize.width / courtImageSize.height

// Les proportions de la photo définissent le rectangle affiché — même
// approche centrée et verrouillée en aspect ratio que l'ancien terrain
// dessiné (jamais étiré), mais calculée depuis les dimensions réelles de
// la photo puisque les repères doivent coïncider avec SES lignes.
private func courtRect(in size: CGSize) -> CGRect {
    var w = size.width
    var h = w / courtAspectRatio
    if h > size.height {
        h = size.height
        w = h * courtAspectRatio
    }
    return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
}

struct CourtView: View {
    @EnvironmentObject var store: SessionStore

    @State private var period: CourtPeriod = .all
    @State private var isEditing = false
    @State private var dragOffsets: [ExerciseType: CGSize] = [:]
    @State private var showResetConfirmation = false

    // store.spotStats(for:) parcourt toutes les séances à chaque appel. Le
    // recalculer pour chaque repère dans `body` faisait saccader le drag,
    // car `onChanged` modifie `dragOffsets` des dizaines de fois par seconde
    // et chaque modification ré-évalue `body`. Ce cache lie le recalcul aux
    // changements de séances plutôt qu'aux frames du drag.
    @State private var spotStatsCache: [ExerciseType: SpotStats] = [:]

    private var filteredSessions: [WorkoutSession] {
        guard let start = period.startDate() else { return store.sessions }
        return store.sessions.filter { $0.date >= start }
    }

    private var periodPicker: some View {
        Picker("Période", selection: $period) {
            ForEach(CourtPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        periodPicker
                        ForEach(courtPages.indices, id: \.self) { index in
                            CourtPageCard(
                                page: courtPages[index],
                                isEditing: isEditing,
                                dragOffsets: $dragOffsets,
                                spotStatsCache: spotStatsCache
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
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
            }
            .alert("Réinitialiser les positions ?", isPresented: $showResetConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Réinitialiser", role: .destructive) {
                    store.resetSpotPositions(for: courtPages.flatMap { $0.spots.map { $0.type } })
                }
            } message: {
                Text("Tous les repères retrouveront leur position d'origine sur chaque terrain.")
            }
            .onAppear(perform: refreshSpotStatsCache)
            .onReceive(store.$sessions) { _ in refreshSpotStatsCache() }
            .onChange(of: period) { _ in refreshSpotStatsCache() }
        }
    }

    private func refreshSpotStatsCache() {
        let allSpots   = courtPages.flatMap { $0.spots }
        let inPeriod   = filteredSessions
        spotStatsCache = Dictionary(uniqueKeysWithValues:
            allSpots.map { ($0.type, store.spotStats(for: $0.type, in: inPeriod)) })
    }
}

// Une page-terrain : carte avec titre, légende et photo + repères — dans
// le même habillage (fond systemBackground, coins arrondis 16) que les
// autres sections de l'app (cf. StatsView).
private struct CourtPageCard: View {
    @EnvironmentObject var store: SessionStore

    let page: CourtPage
    let isEditing: Bool
    @Binding var dragOffsets: [ExerciseType: CGSize]
    let spotStatsCache: [ExerciseType: SpotStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(page.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !page.spots.isEmpty {
                legend
            }

            GeometryReader { geo in
                let rect = courtRect(in: geo.size)

                ZStack {
                    Image("CourtDiagram")
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    ForEach(page.spots, id: \.type) { spot in
                        let stats   = spotStatsCache[spot.type]
                            ?? SpotStats(exerciseType: spot.type, totalShots: 0, totalMade: 0, byType: [:])
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
            .aspectRatio(courtAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(Color(red: 0.2, green: 0.8, blue: 0.4), "≥70%")
            legendDot(.orange, "50%")
            legendDot(Color(red: 1, green: 0.2, blue: 0.2), "<50%")
            Spacer()
        }
        .font(.caption2)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
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

    private func spotColor(_ pct: Double) -> Color {
        if pct >= 70 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if pct >= 50 { return .orange }
        return Color(red: 1, green: 0.2, blue: 0.2)
    }
}
