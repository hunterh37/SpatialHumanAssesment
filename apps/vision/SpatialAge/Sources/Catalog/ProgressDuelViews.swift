import Charts
import ScoreKit
import SwiftUI

/// Progress tab (Dusk spec section 7): level and XP bar, movement age trend with a shaded test-retest
/// noise band, and chips for the domains that improved beyond retest noise.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @State private var history: [ScoreReport] = []

    /// 10 XP per scored game, a level every 100 XP.
    static let xpPerGame = 10, xpPerLevel = 100

    var body: some View {
        let xp = history.reduce(0) { $0 + $1.games.filter(\.played).count } * Self.xpPerGame
        let level = xp / Self.xpPerLevel + 1
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    DuskLabel("Progress · \(model.participant.code)")
                    Text("Level \(level)").font(DuskType.title)
                }
                Spacer()
                Text("\(xp % Self.xpPerLevel) / \(Self.xpPerLevel) XP").font(DuskType.data).duskSecondary()
            }
            DuskBar(fraction: Double(xp % Self.xpPerLevel) / Double(Self.xpPerLevel), xp: true)

            VStack(alignment: .leading, spacing: 12) {
                DuskLabel("Movement age")
                if history.compactMap(\.spatialAge).isEmpty {
                    Text("No sessions yet for this code. Play a game to start the trend.").duskSecondary()
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                } else {
                    trend.frame(height: 240)
                }
            }
            .padding(24)
            .duskCard()

            VStack(alignment: .leading, spacing: 12) {
                DuskLabel("Since first visit")
                FlowChips(chips: domainChips)
            }
            Spacer(minLength: 0)
        }
        .task(id: model.participant.code) { history = model.history() }
    }

    private var trend: some View {
        let points = history.filter { $0.spatialAge != nil }
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { i, r in
                if let lo = r.spatialAgeLow, let hi = r.spatialAgeHigh {
                    AreaMark(x: .value("Visit", i + 1), yStart: .value("Low", lo), yEnd: .value("High", hi))
                        .foregroundStyle(Color.duskAccentSoft)
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { i, r in
                LineMark(x: .value("Visit", i + 1), y: .value("Movement age", r.spatialAge ?? 0))
                    .foregroundStyle(Color.duskAccentStrong)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Visit", i + 1), y: .value("Movement age", r.spatialAge ?? 0))
                    .foregroundStyle(Color.duskAccentStrong)
                    .symbolSize(i == points.count - 1 ? 90 : 30)
            }
            if let chrono = points.last?.chronologicalAge {
                RuleMark(y: .value("Age", chrono))
                    .foregroundStyle(Color.duskMute)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Age \(Int(chrono))").font(.caption).foregroundStyle(Color.duskMute)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(points.count, 6))) { _ in
                AxisGridLine().foregroundStyle(Color.duskLine)
                AxisValueLabel().foregroundStyle(Color.duskMute)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.duskLine)
                AxisValueLabel().foregroundStyle(Color.duskMute)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    /// A domain counts as improved only when its age dropped by more than the 90% retest noise of the
    /// two estimates (1.645 x the combined SD). Everything else is within noise.
    private var domainChips: [DuskChip] {
        guard history.count > 1, let first = history.first, let last = history.last else {
            return [DuskChip(text: "Two visits are needed to compare")]
        }
        // Explicit types: the inferred version times out the Swift 6.2 type checker on some Macs.
        return Domain.allCases.compactMap { (d: Domain) -> DuskChip? in
            guard let a = first.domains.first(where: { $0.domain == d }),
                  let b = last.domains.first(where: { $0.domain == d }),
                  let ageA = a.age, let ageB = b.age else { return nil }
            let sdA: Double = a.ageSD ?? 5, sdB: Double = b.ageSD ?? 5
            let noise: Double = 1.645 * (sdA * sdA + sdB * sdB).squareRoot()
            let drop: Double = ageA - ageB
            if drop > noise {
                return DuskChip(text: String(format: "%@ +%.0f improved", d.title, drop), kind: .improved)
            }
            return DuskChip(text: "\(d.title) within noise")
        }
    }
}

/// Chips in rows that wrap.
struct FlowChips: View {
    let chips: [DuskChip]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { ForEach(Array(chips.enumerated()), id: \.offset) { $0.element } }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(chips.enumerated()), id: \.offset) { $0.element }
            }
        }
    }
}

/// Duel tab (Dusk spec section 7): "Round N of 4", two player panels with rounds won as dots, primary
/// "Start round N · game", tertiary "End duel". Two players take turns on this headset; a round goes to
/// the higher game score.
struct DuelView: View {
    @Environment(AppModel.self) private var model
    let start: ([Game]) -> Void
    @State private var second = Participant(code: Participant.randomCode(), ageYears: 30)

    var body: some View {
        if let duel = model.duel { active(duel) } else { setup }
    }

    private var setup: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                DuskLabel("Duel")
                Text("Two players, four rounds").font(DuskType.title)
                Text("Take turns on this headset. Each round is one game; the higher game score wins it.")
                    .duskSecondary().multilineTextAlignment(.center).frame(maxWidth: 520)
            }
            HStack(spacing: Dusk.Layout.spacing) {
                panel(title: "Player 1", code: model.participant.code) {
                    Text("Age \(Int(model.participant.ageYears))").monospacedDigit().duskSecondary()
                }
                panel(title: "Player 2", code: second.code) {
                    AgeStepper(age: $second.ageYears)
                }
            }
            .frame(maxWidth: 760)
            Button("Start the duel") { model.startDuel(second: second) }
                .buttonStyle(.duskPrimaryLarge)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func active(_ duel: AppModel.Duel) -> some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                DuskLabel("Duel")
                Text(duel.over ? "Duel over" : "Round \(duel.round) of \(AppModel.Duel.rounds)").font(DuskType.title)
                Text(subtitle(duel)).duskSecondary()
            }
            HStack(spacing: Dusk.Layout.spacing) {
                ForEach(0..<2, id: \.self) { i in
                    panel(title: "Player \(i + 1)", code: duel.players[i].code,
                          active: !duel.over && duel.turn == i) {
                        DuskDots(total: AppModel.Duel.rounds, done: duel.wins[i], current: false, size: 12)
                    }
                }
            }
            .frame(maxWidth: 760)
            if let notice = model.notice { DuskChip(text: notice) }
            if duel.over {
                Button("End duel") { model.endDuel() }.buttonStyle(.duskPrimaryLarge)
            } else {
                Button("Start round \(duel.round) · \(duel.game.duskTitle)") { start([duel.game]) }
                    .buttonStyle(.duskPrimaryLarge)
                Button("End duel") { model.endDuel() }.buttonStyle(.duskTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func subtitle(_ duel: AppModel.Duel) -> String {
        if duel.over {
            if duel.wins[0] == duel.wins[1] { return "Level, \(duel.wins[0]) rounds each." }
            let w = duel.wins[0] > duel.wins[1] ? 0 : 1
            return "\(duel.players[w].code) wins \(duel.wins[w]) to \(duel.wins[1 - w])."
        }
        return "\(duel.players[duel.turn].code) plays next. \(duel.game.duskInstruction)"
    }

    private func panel(title: String, code: String, active: Bool = false,
                       @ViewBuilder _ detail: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DuskLabel(title)
            Text(code).font(.system(size: 34, weight: .light, design: .monospaced))
            detail()
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .duskCard(selected: active)
    }
}
