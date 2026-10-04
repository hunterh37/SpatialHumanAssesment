import ScoreKit
import SwiftUI

/// Session result. Spatial Age first, then the five domains, then the games. Numbers only where they mean something.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    let again: () -> Void

    var body: some View {
        if let r = model.report {
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SPATIAL AGE").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.secondary)
                    Text(r.spatialAge.map { String(format: "%.1f", $0) } ?? "–")
                        .font(.system(size: 112, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    if let gap = r.ageGap, let chrono = r.chronologicalAge {
                        Text(String(format: "%+.1f years vs %.0f", gap, chrono))
                            .font(.title3).foregroundStyle(gap <= 0 ? Theme.color(Theme.teal) : Theme.color(Theme.nogo))
                    }
                    if let lo = r.spatialAgeLow, let hi = r.spatialAgeHigh {
                        Text(String(format: "80%% interval %.0f to %.0f", lo, hi)).foregroundStyle(.secondary)
                    }
                    if let pace = model.pace {
                        Text(String(format: "Pace %.2fx over %d sessions", pace.pace, pace.sessions))
                            .foregroundStyle(.secondary)
                    }
                    if !r.quality.usable {
                        Text("Low data quality: " + r.quality.flags.joined(separator: ", "))
                            .font(.footnote).foregroundStyle(Theme.color(Theme.nogo))
                    }
                    Spacer()
                    HStack {
                        Button("Play again", action: again)
                        Button("Next participant", action: next).buttonStyle(.borderedProminent)
                    }
                    if let status = model.uploadStatus { Text(status).font(.footnote).foregroundStyle(.tertiary) }
                }
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(r.domains, id: \.domain) { d in
                        DomainBar(title: d.title, score: d.score)
                    }
                    Divider()
                    ForEach(r.games.filter(\.played), id: \.game) { g in
                        HStack {
                            Text(g.title)
                            Spacer()
                            if let id = g.headline, let m = r.metrics.first(where: { $0.id == id }) {
                                Text(Self.format(m)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: 380)
            }
        } else {
            ProgressView()
        }
    }

    static func format(_ m: ScoreReport.MetricResult) -> String {
        switch m.unit {
        case "s": String(format: "%.0f ms", m.value * 1000)
        case "cm": String(format: "%.1f cm", m.value)
        case "ratio": String(format: "%.0f%%", m.value * 100)
        default: String(format: "%.1f", m.value)
        }
    }
}

struct DomainBar: View {
    let title: String
    let score: Double
    @State private var shown = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(score.rounded()))").monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(Theme.color(Theme.paper)).frame(width: geo.size.width * shown / 100)
                }
            }
            .frame(height: 6)
        }
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.15)) { shown = score } }
    }
}
