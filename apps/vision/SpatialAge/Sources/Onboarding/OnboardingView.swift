import ScoreKit
import SwiftUI

/// First-run setup, one question per screen (docs/index.html on main, Dusk spec v1.0).
/// Welcome, consent, seven questions with progress dots, then a review with per-field Edit.
/// One primary button per screen; Back is an icon button; Skip is tertiary.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, consent, name, age, sex, height, weight, hand, posture, review
        /// Steps that count toward the seven progress dots.
        static let questions: ClosedRange<Int> = Step.name.rawValue...Step.posture.rawValue
        var isQuestion: Bool { Self.questions.contains(rawValue) }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var forward = true
    /// Set while a question was opened from the review's Edit button; Continue reads "Save" and returns.
    @State private var fromReview = false
    @State private var draft: OnboardingDraft
    @FocusState private var nameFocused: Bool

    init(start: Step = .welcome, draft: OnboardingDraft = OnboardingDraft()) {
        _step = State(initialValue: start)
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            foot
        }
        .padding(.horizontal, 44)
        .padding(.top, 32)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .duskGlass()
        .clipped()
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button("Back", systemImage: "chevron.left", action: back)
                .buttonStyle(.duskIcon)
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            if step.isQuestion {
                DuskDots(total: 7, done: step.rawValue - Step.name.rawValue, size: 10)
            }
            Spacer()
            Text(step.isQuestion ? "\(step.rawValue - 1)/7" : "")
                .font(.callout.monospaced())
                .foregroundStyle(Color.duskInk.opacity(0.6))
                .frame(width: Dusk.Layout.minHit, alignment: .trailing)
        }
    }

    private var foot: some View {
        VStack(spacing: 6) {
            Button(fromReview && step != .review ? "Save" : primaryTitle, action: next)
                .buttonStyle(.duskPrimaryLarge)
                .frame(minWidth: 300)
                .disabled(!canContinue)
            if step == .weight {
                Button("Skip this question") {
                    draft.weightSkipped = true
                    advance()
                }
                .buttonStyle(.duskTertiary)
            }
        }
        .padding(.top, 12)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Begin"
        case .consent: "I agree"
        case .review: "Go to home"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .name: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .sex: draft.sex != nil
        case .hand: draft.hand != nil
        case .posture: draft.posture != nil
        default: true
        }
    }

    private var greeting: String {
        let n = draft.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "" : ", \(n)"
    }

    // MARK: Screens

    @ViewBuilder private var content: some View {
        VStack(spacing: 22) {
            switch step {
            case .welcome:
                DuskLabel(DuskCopy.brand)
                Text(DuskCopy.homeTitle).font(OnboardingType.hero).multilineTextAlignment(.center)
                why("First, a few quick questions so we can compare your games fairly. It takes about a minute.")

            case .consent:
                question("Before you start", "How your answers are used")
                ConsentList(lines: [
                    "Your answers and movements are used only to estimate your movement age.",
                    "Results are saved under a random code, never your name.",
                    "Passthrough stays available. You can skip a game or stop at any time.",
                ])
                .frame(maxWidth: 640)

            case .name:
                question("Your name", "What should we call you?")
                TextField("First name", text: $draft.name)
                    .font(OnboardingType.field)
                    .multilineTextAlignment(.center)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .submitLabel(.continue)
                    .onSubmit { if canContinue { next() } }
                    .onChange(of: draft.name) { _, v in if v.count > 24 { draft.name = String(v.prefix(24)) } }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 560, minHeight: 84)
                    .background(nameFocused ? Color.duskChipStrong : Color.duskChip, in: Capsule())
                    .overlay { Capsule().strokeBorder(nameFocused ? Color.duskAccentStrong : Color.duskGlassEdge, lineWidth: 1) }
                    .onAppear { nameFocused = true }
                Text("Look at the box and speak, or type.").font(.callout).foregroundStyle(Color.duskInk.opacity(0.6))
                why("Used to greet you today. It isn't saved.")

            case .age:
                question("Age", "How old are you\(greeting)?")
                BigStepper(minus: "Younger", plus: "Older",
                           canMinus: draft.age > 18, canPlus: draft.age < 100) { d in
                    draft.age = min(100, max(18, draft.age + Double(d)))
                } value: {
                    ValueText(number: "\(Int(draft.age))", unit: "YRS")
                }
                Slider(value: $draft.age, in: 18...100, step: 1)
                    .tint(Color.duskAccentStrong)
                    .frame(maxWidth: 480)
                    .accessibilityLabel("Age")
                why("Your movement age is compared with this.")

            case .sex:
                question("Sex", "What is your sex?")
                OptionGrid(columns: 2) {
                    ForEach(Participant.Sex.allCases, id: \.self) { s in
                        OptionCard(title: Self.sexTitle(s), selected: draft.sex == s) { draft.sex = s }
                    }
                }
                why("Typical scores differ, so we compare you with the right group.")

            case .height:
                question("Height", "How tall are you?")
                DuskSegmented(selection: $draft.heightImperial, options: [(true, "ft / in"), (false, "cm")])
                BigStepper(minus: "Shorter", plus: "Taller", canMinus: true, canPlus: true) { draft.stepHeight($0) } value: {
                    if draft.heightImperial {
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            ValueText(number: "\(draft.inches / 12)", unit: "FT")
                            ValueText(number: "\(draft.inches % 12)", unit: "IN")
                        }
                    } else {
                        ValueText(number: "\(Int(draft.heightCm.rounded()))", unit: "CM")
                    }
                }
                why("We place reach targets where your arms can get to them.")

            case .weight:
                question("Weight · optional", "What do you weigh?")
                DuskSegmented(selection: $draft.weightImperial, options: [(true, "lb"), (false, "kg")])
                BigStepper(minus: "Less", plus: "More", canMinus: true, canPlus: true) { draft.stepWeight($0) } value: {
                    ValueText(number: draft.weightImperial ? "\(draft.pounds)" : "\(Int(draft.weightKg.rounded()))",
                              unit: draft.weightImperial ? "LB" : "KG")
                }
                why("Kept with your clinic record. Skip it if you'd rather not say.")

            case .hand:
                question("Main hand", "Which hand do you use most?")
                OptionGrid(columns: 3) {
                    OptionCard(title: "Left", selected: draft.hand == .left, icon: AnyView(HandGlyph(left: true))) { draft.hand = .left }
                    OptionCard(title: "Both", selected: draft.hand == .ambi,
                               icon: AnyView(HStack(spacing: 0) { HandGlyph(left: true); HandGlyph(left: false) })) { draft.hand = .ambi }
                    OptionCard(title: "Right", selected: draft.hand == .right, icon: AnyView(HandGlyph(left: false))) { draft.hand = .right }
                }
                why("Reach games start on this side.")

            case .posture:
                question("How you'll play", "Standing or seated?")
                OptionGrid(columns: 2) {
                    OptionCard(title: "Standing", subtitle: "All eight games", selected: draft.posture == .standing) {
                        draft.posture = .standing
                    }
                    OptionCard(title: "Seated", subtitle: "Six games, no balance games", selected: draft.posture == .seated) {
                        draft.posture = .seated
                    }
                }
                why("Choose seated if standing in place for six minutes is uncomfortable. You can change this later.")

            case .review:
                question("Review", "You're set\(greeting)")
                ReviewGrid(draft: draft, sexTitle: draft.sex.map(Self.sexTitle) ?? "Not shared") { edit($0) }
                    .frame(maxWidth: 780)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func question(_ eyebrow: String, _ title: String) -> some View {
        VStack(spacing: 14) {
            DuskLabel(eyebrow)
            Text(title).font(OnboardingType.question).multilineTextAlignment(.center)
        }
    }

    private func why(_ text: String) -> some View {
        Text(text).font(.title3).duskSecondary().multilineTextAlignment(.center).frame(maxWidth: 620)
    }

    static func sexTitle(_ s: Participant.Sex) -> String {
        switch s {
        case .female: "Female"
        case .male: "Male"
        case .other: "Other"
        case .unspecified: "Prefer not to say"
        }
    }

    // MARK: Navigation

    private func go(_ s: Step, forward f: Bool) {
        forward = f
        withAnimation(reduceMotion ? nil : Dusk.Motion.spring) { step = s }
    }

    private func next() {
        if step == .review { return model.completeOnboarding(draft.profile) }
        if step == .weight { draft.weightSkipped = false }
        advance()
    }

    private func advance() {
        if fromReview { fromReview = false; return go(.review, forward: true) }
        if let n = Step(rawValue: step.rawValue + 1) { go(n, forward: true) }
    }

    private func back() {
        if fromReview { fromReview = false; return go(.review, forward: false) }
        if let p = Step(rawValue: step.rawValue - 1) { go(p, forward: false) }
    }

    private func edit(_ s: Step) {
        fromReview = true
        go(s, forward: false)
    }
}

// MARK: - Type

enum OnboardingType {
    static let hero = Font.system(size: 76, weight: .thin, design: .rounded)
    static let question = Font.system(size: 52, weight: .light, design: .rounded)
    static let field = Font.system(size: 40, weight: .light, design: .rounded)
    static let value = Font.system(size: 120, weight: .thin, design: .rounded).monospacedDigit()
}

// MARK: - Pieces

/// Big tabular value with a small tracked unit, e.g. 62 YRS.
private struct ValueText: View {
    let number: String
    let unit: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number).font(OnboardingType.value).contentTransition(.numericText())
            Text(unit).font(DuskType.label).tracking(2.5).foregroundStyle(Color.duskInk.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Round minus and plus buttons around a large value.
private struct BigStepper<Value: View>: View {
    let minus: String
    let plus: String
    let canMinus: Bool
    let canPlus: Bool
    let step: (Int) -> Void
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 36) {
            round("minus", minus, enabled: canMinus) { step(-1) }
            value().frame(minWidth: 300)
            round("plus", plus, enabled: canPlus) { step(1) }
        }
        .animation(Dusk.Motion.quick, value: canMinus)
    }

    private func round(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, systemImage: symbol, action: action)
            .buttonStyle(RoundStepStyle())
            .disabled(!enabled)
            .buttonRepeatBehavior(.enabled)
    }
}

/// 80 pt circle with a glassEdge ring, chip fill, chipStrong on gaze.
private struct RoundStepStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(Color.duskInk)
            .frame(width: 80, height: 80)
            .background {
                ZStack {
                    Circle().fill(Color.duskChip)
                    Circle().fill(Color.duskChipStrong).hoverEffect { e, active, _ in e.opacity(active ? 1 : 0) }
                }
            }
            .overlay { Circle().strokeBorder(Color.duskGlassEdge, lineWidth: 1) }
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .hoverEffect { e, active, _ in e.scaleEffect(active && enabled ? 1.035 : 1) }
            .hoverEffectGroup()
            .opacity(enabled ? 1 : 0.35)
            .animation(Dusk.Motion.quick, value: configuration.isPressed)
    }
}

private struct OptionGrid<Content: View>: View {
    let columns: Int
    @ViewBuilder let content: () -> Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Dusk.Layout.spacing), count: columns),
                  spacing: Dusk.Layout.spacing, content: content)
            .frame(maxWidth: columns == 3 ? 720 : 640)
    }
}

/// Choice card: chip fill; selected = chipStrong, accentStrong border, peach check badge.
private struct OptionCard: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    var icon: AnyView?
    let pick: () -> Void

    init(title: String, subtitle: String? = nil, selected: Bool, icon: AnyView? = nil, pick: @escaping () -> Void) {
        self.title = title; self.subtitle = subtitle; self.selected = selected; self.icon = icon; self.pick = pick
    }

    var body: some View {
        Button { withAnimation(Dusk.Motion.quick, pick) } label: {
            VStack(spacing: 8) {
                if let icon { icon.frame(height: 52) }
                Text(title).font(.title3.weight(.medium)).foregroundStyle(Color.duskInk)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(Color.duskInk.opacity(0.65)) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(selected ? Color.duskChipStrong : Color.duskChip,
                        in: .rect(cornerRadius: Dusk.Layout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Dusk.Layout.cardRadius, style: .continuous)
                    .strokeBorder(selected ? Color.duskAccentStrong : .clear, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.duskOnAccent)
                        .frame(width: 28, height: 28)
                        .background(Color.duskAccent, in: Circle())
                        .padding(12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(.rect(cornerRadius: Dusk.Layout.cardRadius))
        }
        .buttonStyle(.plain)
        .hoverEffect { e, active, _ in e.scaleEffect(active ? 1.035 : 1) }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HandGlyph: View {
    let left: Bool
    var body: some View {
        Image(systemName: "hand.raised")
            .font(.system(size: 40, weight: .light))
            .scaleEffect(x: left ? -1 : 1)
            .foregroundStyle(Color.duskInk)
    }
}

/// Numbered consent lines separated by hairlines.
private struct ConsentList: View {
    let lines: [String]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                if i > 0 { Divider().overlay(Color.duskLine) }
                HStack(spacing: 18) {
                    Text("\(i + 1)")
                        .font(.callout.monospaced().weight(.medium))
                        .frame(width: 36, height: 36)
                        .background(Color.duskChipStrong, in: Circle())
                    Text(line).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
            }
        }
    }
}

/// Two-column summary with an Edit button per row, the saved code, and "Name: Not saved".
private struct ReviewGrid: View {
    let draft: OnboardingDraft
    let sexTitle: String
    let edit: (OnboardingView.Step) -> Void

    var body: some View {
        let hand: String = switch draft.hand {
        case .left: "Left"
        case .right: "Right"
        case .ambi: "Both"
        case nil: "Not shared"
        }
        Grid(horizontalSpacing: 40, verticalSpacing: 0) {
            GridRow { row("Age", "\(Int(draft.age))", .age); row("Sex", sexTitle, .sex) }
            GridRow { row("Height", draft.heightText, .height); row("Weight", draft.weightText, .weight) }
            GridRow { row("Main hand", hand, .hand); row("Play", draft.posture == .seated ? "Seated" : "Standing", .posture) }
            GridRow {
                cell("Saved as") {
                    Text(draft.code)
                        .font(.callout.monospaced().weight(.medium)).tracking(1)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.duskChip, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.duskGlassEdge, lineWidth: 1) }
                }
                cell("Name") { Text("Not saved").foregroundStyle(Color.duskInk.opacity(0.65)) }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ step: OnboardingView.Step) -> some View {
        cell(title) {
            HStack(spacing: 6) {
                Text(value).fontWeight(.medium).monospacedDigit()
                Button("Edit") { edit(step) }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.duskAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: Dusk.Layout.minHit)
                    .contentShape(.capsule)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Edit \(title)")
            }
        }
    }

    private func cell(_ title: String, @ViewBuilder _ value: () -> some View) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.duskLine)
            HStack {
                Text(title).foregroundStyle(Color.duskInk.opacity(0.65))
                Spacer()
                value()
            }
            .font(.title3)
            .frame(minHeight: 64)
        }
    }
}

#Preview(windowStyle: .plain) {
    OnboardingView().environment(AppModel()).frame(width: 1240, height: 800)
}
