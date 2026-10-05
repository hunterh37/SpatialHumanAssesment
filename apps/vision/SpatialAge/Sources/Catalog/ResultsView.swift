import AVFoundation
import ScoreKit
import SwiftUI

/// Session result in two beats. Spec: Dusk design spec v1.0, section 7 (Results).
/// 1. Reveal: the BetterYears Age tumbles down to its value while a five-part ring fills, one arc per domain.
/// 2. Scoreboard: the age glides to the left and the five domain bars grow in, graded against the participant's own age.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    let again: () -> Void

    enum Beat { case reveal, board }
    @State private var stage: Beat = .reveal
    @Namespace private var hero

    var body: some View {
        Group {
            if let r = model.report {
                switch stage {
                case .reveal:
                    AgeReveal(report: r, ns: hero) {
                        withAnimation(.spring(duration: 0.75, bounce: 0.15)) { stage = .board }
                    }
                case .board:
                    Scoreboard(report: r, pace: model.pace, uploadStatus: model.uploadStatus, ns: hero,
                               next: model.demo && !model.demoRemaining.isEmpty ? next : nil, again: again)
                }
            } else {
                ProgressView()
            }
        }
        .onChange(of: model.report?.sessionId) { stage = .reveal }
    }
}

// MARK: - Beat 1: reveal

struct AgeReveal: View {
    let report: ScoreReport
    let ns: Namespace.ID
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?
    @State private var progress = 0.0
    @State private var landed = false
    @State private var breathe = false
    @State private var bloomOn = false
    @State private var bloomOut = false

    /// Time from first number to landing, and how long the landed number holds before the scoreboard.
    static let tumble = 3.6
    /// Product name for the headline age (team decision, overrides "movement age" in Dusk spec v1.0).
    static let ageLabel = "Better Years Age"
    static let hold = 2.6

    var body: some View {
        ZStack {
            Circle()
                .fill(Dusk.color(Dusk.accentGlow))
                .frame(width: 356, height: 356)
                .scaleEffect(breathe ? 1 : 0.92)
                .opacity(landed ? 0 : (breathe ? 0.14 : 0.05))
            DomainRing(progress: progress)
                .frame(width: 380, height: 380)
            Circle()
                .stroke(Dusk.color(Dusk.accent), lineWidth: 2)
                .frame(width: 340, height: 340)
                .scaleEffect(bloomOut ? 1.25 : 0.72)
                .opacity(bloomOn && !bloomOut ? 0.7 : 0)

            VStack(spacing: 16) {
                ResultsLabel(text: landed ? Self.ageLabel : "Analyzing your results")
                    .matchedGeometryEffect(id: "label", in: ns)
                Text(heroText)
                    .font(.system(size: 128, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Dusk.color(Dusk.fg))
                    .contentTransition(.numericText(value: shown ?? 0))
                    .matchedGeometryEffect(id: "number", in: ns)
                Text(readingLine)
                    .foregroundStyle(Dusk.color(Dusk.mute))
                    .frame(height: 22)
                if landed {
                    AgeChip(report: report)
                        .matchedGeometryEffect(id: "chip", in: ns)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Button("View details", action: done)
                .buttonStyle(.plain)
                .padding(.horizontal, 20).frame(minHeight: 60)
                .contentShape(Capsule())
                .hoverEffect(.highlight)
                .opacity(0.72)
        }
        .task { await run() }
    }

    private var heroText: String {
        guard let v = shown else { return "–" }
        return "\(Int(v.rounded()))"
    }

    private var readingLine: String {
        guard progress < 1 else { return " " }
        let all = Domain.allCases
        return "Analyzing " + all[min(all.count - 1, Int(progress * Double(all.count)))].title.lowercased()
    }

    private func run() async {
        // Whole years only: the landed number is the rounded age.
        guard let end = report.spatialAge?.rounded() else { done(); return }
        if reduceMotion {
            shown = end; progress = 1; landed = true
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { done() }
            return
        }
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { breathe = true }

        // Start well above, then ease out so the last few numbers slow down before landing (the Wii Fit drumroll).
        let start = ((report.chronologicalAge ?? end) + 18).rounded()
        let clock = ContinuousClock(), t0 = clock.now
        var last = Int.min
        while !Task.isCancelled {
            let p = min(1, max(0, (clock.now - t0) / .seconds(Self.tumble)))
            let eased = 1 - pow(1 - p, 3)
            let v = Int((start + (end - start) * eased).rounded())
            withAnimation(.easeOut(duration: 0.3)) { progress = p }
            if v != last, p < 1 {
                withAnimation(.snappy(duration: 0.14)) { shown = Double(v) }
                last = v
            }
            if p >= 1 { break }
            try? await Task.sleep(for: .milliseconds(60))
        }
        guard !Task.isCancelled else { return }

        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { shown = end; landed = true; breathe = false }
        bloomOn = true
        UISound.land()
        try? await Task.sleep(for: .milliseconds(30))
        withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 1.4)) { bloomOut = true }

        try? await Task.sleep(for: .seconds(Self.hold))
        if !Task.isCancelled { done() }
    }
}

/// Five arcs around the number, one per domain, lit in order as the reading progresses.
struct DomainRing: View {
    let progress: Double
    private let count = Domain.allCases.count
    private let gap = 10.0 / 360

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let from = Double(i) / Double(count) + gap / 2
                let to = Double(i + 1) / Double(count) - gap / 2
                let on = progress >= 1 || i < Int(progress * Double(count))
                Circle()
                    .trim(from: from, to: to)
                    .stroke(Dusk.color(on ? Dusk.accentStrong : Dusk.chipStrong),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: on)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Beat 2: scoreboard

struct Scoreboard: View {
    let report: ScoreReport
    let pace: PaceOfAging.Pace?
    let uploadStatus: String?
    let ns: Namespace.ID
    /// Starts the next game of the intro demo sequence. Nil hides the button.
    let next: (() -> Void)?
    let again: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 14) {
                ResultsLabel(text: AgeReveal.ageLabel)
                    .matchedGeometryEffect(id: "label", in: ns)
                Text(report.spatialAge.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 104, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Dusk.color(Dusk.fg))
                    .matchedGeometryEffect(id: "number", in: ns)
                AgeChip(report: report)
                    .matchedGeometryEffect(id: "chip", in: ns)
                VStack(alignment: .leading, spacing: 4) {
                    if let lo = report.spatialAgeLow, let hi = report.spatialAgeHigh {
                        // ScoreKit's low and high are the 80 percent interval (z = 1.2816).
                        Text(String(format: "80%% interval %.0f to %.0f", lo, hi)).monospacedDigit()
                    }
                    if let pace {
                        Text(String(format: "Pace %.2fx over %d sessions", pace.pace, pace.sessions)).monospacedDigit()
                    }
                    Text(report.participantCode).monospaced().font(.footnote)
                }
                .foregroundStyle(Dusk.color(Dusk.mute))
                if !report.quality.usable {
                    Label("Low data quality: " + report.quality.flags.joined(separator: ", "),
                          systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(Dusk.color(Dusk.warn))
                }
                Spacer(minLength: 28)
                // Demo sequence: secondary "Play again", primary "Next game" until the last game.
                HStack(spacing: Dusk.Layout.spacing) {
                    if let next {
                        Button("Play again", action: again).buttonStyle(.duskSecondary)
                        Button("Next game", action: next).buttonStyle(.duskPrimary)
                    } else {
                        Button("Play again", action: again).buttonStyle(.duskPrimary)
                    }
                }
                if let uploadStatus {
                    Text(uploadStatus).font(.footnote).foregroundStyle(Dusk.color(Dusk.mute))
                }
            }
            .frame(width: 340, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Detailed Score").font(.system(size: 30, weight: .light, design: .rounded))
                    Spacer()
                    GradeLegend()
                }
                .padding(.bottom, 14)
                ForEach(Array(report.domains.enumerated()), id: \.element.domain) { i, d in
                    DomainRow(domain: d, chronologicalAge: report.chronologicalAge, index: i)
                }
                if let best = report.domains.filter({ $0.age != nil }).min(by: { $0.age! < $1.age! }), let age = best.age {
                    Text("Your \(best.title.lowercased()) is comparable to a typical \(Int(age.rounded()))-year-old.")
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Dusk.color(Dusk.chip), in: RoundedRectangle(cornerRadius: 22))
                        .padding(.top, 14)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Dusk.color(Dusk.glassInk))
    }
}

/// One domain: name, what it measures, a graded bar with its 0 to 100 score, and its comparable age.
struct DomainRow: View {
    let domain: ScoreReport.DomainResult
    let chronologicalAge: Double?
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0
    @State private var visible = false

    private var grade: Grade { Grade(domainAge: domain.age, chronologicalAge: chronologicalAge, score: domain.score) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Dusk.color(Dusk.glassEdge).opacity(0.6)).frame(height: 1)
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.title).font(.headline)
                    Text(Self.subtitle(domain.domain)).font(.subheadline).foregroundStyle(Dusk.color(Dusk.mute))
                }
                .frame(width: 170, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Dusk.color(Dusk.chipStrong))
                        Capsule().fill(Dusk.color(grade.color))
                            .frame(width: geo.size.width * min(max(shown, 0), 100) / 100)
                    }
                }
                .frame(height: 14)
                Text("\(Int(shown.rounded()))")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shown))
                    .frame(width: 52, alignment: .trailing)
            }
            HStack {
                Circle().fill(Dusk.color(grade.color)).frame(width: 7, height: 7)
                Text(grade.label)
                Spacer()
                if let age = domain.age {
                    Text("comparable age \(Int(age.rounded()))").monospaced().foregroundStyle(Dusk.color(Dusk.mute))
                }
            }
            .font(.footnote)
            .padding(.leading, 190)
            .padding(.bottom, 6)
        }
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(domain.title), \(Int(domain.score.rounded())) out of 100, \(grade.label)")
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.45 + Double(index) * 0.16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) { visible = true }
            withAnimation(reduceMotion ? nil : .spring(duration: 1.1, bounce: 0.25)) { shown = domain.score }
        }
    }

    static func subtitle(_ d: Domain) -> String {
        switch d {
        case .speed: "Reaction time and reach"
        case .decision: "Accuracy under time pressure"
        case .control: "Movement precision"
        case .memory: "Spatial working memory"
        case .consistency: "Variability across trials"
        }
    }
}

/// Reached from "Play again" on the result. Same player, a recent player on this headset, or a new one.
struct PlayerSwitchView: View {
    @Environment(AppModel.self) private var model
    @State private var recent: [Participant] = []

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                DuskLabel("Play again")
                Text("Who plays next?").font(DuskType.title)
            }
            HStack(spacing: Dusk.Layout.spacing) {
                card(model.participant, title: "Same player", selected: true)
                ForEach(recent, id: \.code) { card($0, title: "Recent") }
            }
            .frame(maxWidth: 900)
            HStack(spacing: Dusk.Layout.spacing) {
                Button("Back to result") { model.phase = .results }.buttonStyle(.duskTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .task { recent = model.recentPlayers() }
    }

    private func card(_ p: Participant, title: String, selected: Bool = false) -> some View {
        Button { model.switchPlayer(to: p) } label: {
            VStack(alignment: .leading, spacing: 12) {
                DuskLabel(title)
                Text(p.code).font(.system(size: 30, weight: .light, design: .monospaced))
                Text("Age \(Int(p.ageYears))").duskSecondary()
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .duskCard(selected: selected)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Dusk.Layout.cardRadius, style: .continuous))
            .hoverEffect()
        }
        .buttonStyle(.plain)
    }
}

/// Red, yellow, green. Graded against the participant's own age, so a strong 70-year-old sees green.
/// Bar length stays the 0 to 100 score against the age-25 reference.
enum Grade {
    case good, mid, low

    /// Domain age minus chronological age, in years.
    static let goodBelow = -2.0
    static let lowAbove = 2.0

    init(domainAge: Double?, chronologicalAge: Double?, score: Double) {
        if let a = domainAge, let c = chronologicalAge {
            let gap = a - c
            self = gap <= Self.goodBelow ? .good : gap < Self.lowAbove ? .mid : .low
        } else {
            self = score >= 67 ? .good : score >= 34 ? .mid : .low
        }
    }

    var label: String {
        switch self {
        case .good: "Above typical for age"
        case .mid: "Typical for age"
        case .low: "Area to improve"
        }
    }

    var color: UIColor {
        switch self {
        case .good: Dusk.gradeGood
        case .mid: Dusk.gradeMid
        case .low: Dusk.gradeLow
        }
    }
}

struct GradeLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([Grade.good, .mid, .low], id: \.label) { g in
                HStack(spacing: 6) {
                    Circle().fill(Dusk.color(g.color)).frame(width: 8, height: 8)
                    Text(g.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Dusk.color(Dusk.mute))
    }
}

// MARK: - Shared pieces

struct ResultsLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(3)
            .foregroundStyle(Dusk.color(Dusk.mute))
    }
}

/// "4 years younger than 52", in whole years so it matches the rounded headline. Spec: accentSoft chip with an accentStrong dot.
struct AgeChip: View {
    let report: ScoreReport

    var body: some View {
        if let age = report.spatialAge, let chrono = report.chronologicalAge {
            let years = Int(age.rounded()) - Int(chrono.rounded())
            let younger = years < 0, older = years > 0
            HStack(spacing: 8) {
                Circle().fill(Dusk.color(older ? Dusk.mute : Dusk.accentStrong)).frame(width: 7, height: 7)
                Text(younger || older
                     ? "\(abs(years)) \(abs(years) == 1 ? "year" : "years") \(younger ? "younger" : "older") than \(Int(chrono.rounded()))"
                     : "In line with age \(Int(chrono.rounded()))")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Dusk.color(older ? Dusk.chip : Dusk.accentSoft), in: Capsule())
        }
    }
}

/// Window (non-spatial) sounds for the results screen. Same soft sine voice as `Tone`, pentatonic.
@MainActor
enum UISound {
    private static var cache: [String: Data] = [:]
    private static var live: [AVAudioPlayer] = []

    private static func play(_ key: String, _ partials: [(Double, Double)], duration: Double, volume: Float) {
        let data = cache[key] ?? Tone.wav(partials: partials, duration: duration)
        cache[key] = data
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.volume = volume
        p.play()
        live.removeAll { !$0.isPlaying }
        live.append(p)
    }

    /// One soft chime when the age lands. No per-tick or per-row sounds: the screen should feel calm, not arcade.
    static func land() {
        play("land", [(523, 1), (784, 0.6)], duration: 1.2, volume: 0.3)
    }
}
