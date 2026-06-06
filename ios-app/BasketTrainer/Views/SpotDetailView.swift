import SwiftUI

struct SpotDetailView: View {
    let stats: SpotStats

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("\(stats.totalMade) / \(stats.totalShots)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text(String(format: "%.0f%%", stats.percentage))
                        .font(.title2.bold())
                        .foregroundStyle(spotColor(stats.percentage))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemFill))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(spotColor(stats.percentage))
                                .frame(width: geo.size.width * CGFloat(stats.percentage / 100),
                                       height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if !stats.byType.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Par type de tir")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(ShotType.allCases, id: \.self) { t in
                            if let entry = stats.byType[t] {
                                shotTypeRow(type: t, shots: entry.shots, made: entry.made)
                            }
                        }
                    }
                } else {
                    Text("Pas encore de sessions avec type de tir pour ce spot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding(20)
        }
        .navigationTitle(stats.exerciseType.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shotTypeRow(type: ShotType, shots: Int, made: Int) -> some View {
        let pct = shots == 0 ? 0.0 : Double(made) / Double(shots) * 100
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(type.name).font(.subheadline)
                Spacer()
                Text("\(made)/\(shots)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", pct))
                    .font(.subheadline.bold())
                    .foregroundStyle(spotColor(pct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(spotColor(pct))
                        .frame(width: geo.size.width * CGFloat(pct / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spotColor(_ pct: Double) -> Color {
        if pct >= 70 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if pct >= 50 { return .orange }
        return Color(red: 1.0, green: 0.2, blue: 0.2)
    }
}
