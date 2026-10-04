import ScoreKit
import SwiftUI

/// Session result (Dusk spec section 7). Movement age first, then the five domains, then the games.
/// Numbers only where they mean something.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    let again: () -> Void

    var body: some View {
        if let r = model.report {
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 12) {
                    DuskLabel("Movement age")
                    Text(r.spatialAge.map { String(format: "%.1f", $0) } ?? "–")
                        .font(DuskType.hero(120))
                        .contentTransition(.numericText())
                    if let gap = r.ageGap, let chrono = r.chronologicalAge, abs(gap) >= 0.05 {
                        DuskChip(text: String(format: "%.1f years %@ than %.0f", abs(gap), gap < 0 ? "younger" : "older", chrono),
                                 kind: gap < 0 ? .improved : .neutral)
                    }
                    if let lo = r.spatialAgeLow, let hi = r.spatialAgeHigh {
                        Text(String(format: "80%% interval %.0f to %.0f", lo, hi)).monospacedDigit().duskSecondary()
                    }
                    if let pace = model.pace {
                        Text(String(format: "Pace %.2fx over %d sessions", pace.pace, pace.sessions))
                            .monospacedDigit().duskSecondary()
                    }
                    if !r.quality.usable {
                        DuskChip(text: "Tracking lost: " + r.quality.flags.joined(separator: ", "), kind: .warn)
                    }
                    Text("A game score, not a medical test.").font(.footnote).duskSecondary()
                    Spacer(minLength: 0)
                    HStack(spacing: Dusk.Layout.spacing) {
                        Button("Play again", action: again).buttonStyle(.duskSecondary)
                        Button("Next player", action: next).buttonStyle(.duskPrimaryLarge)
                    }
                    if let status = model.uploadStatus { Text(status).font(.footnote).duskSecondary() }
                }
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(r.domains, id: \.domain) { d in
                        DomainBar(title: d.title, score: d.score)
                    }
                    Divider().overlay(Color.duskLine)
                    ForEach(r.games.filter(\.played), id: \.game) { g in
                        HStack {
                            Text(g.game.duskTitle)
                            Spacer()
                            if let id = g.headline, let m = r.metrics.first(where: { $0.id == id }) {
                                Text(Self.format(m)).font(DuskType.data).duskSecondary()
                            }
                        }
                    }
                }
                .padding(26)
                .frame(width: 420)
                .duskCard()
            }
        } else {
            ProgressView().tint(Color.duskAccentStrong)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(score.rounded()))").font(DuskType.data).duskSecondary()
            }
            DuskBar(fraction: score / 100)
        }
    }
}
