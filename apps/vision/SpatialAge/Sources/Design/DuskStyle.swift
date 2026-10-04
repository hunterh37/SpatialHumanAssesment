import SwiftUI

/// Dusk components (spec sections 4 to 6): glass, type roles, buttons, controls.
/// Every color comes from `Dusk` via the `Color.dusk*` mirrors in Theme.swift.

// MARK: - Glass

extension View {
    /// Charcoal-tinted system glass with a 1 px glassEdge border and a 1 px top glassHighlight.
    func duskGlass(radius: CGFloat = Dusk.Layout.windowRadius, strong: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(strong ? Color.duskGlassStrong : Color.duskGlass, in: shape)
            .glassBackgroundEffect(in: shape)
            .overlay { DuskEdge(shape: shape) }
    }

    /// Card inside a window: chip fill, glassEdge hairline.
    func duskCard(radius: CGFloat = Dusk.Layout.cardRadius, selected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(selected ? Color.duskChipStrong : Color.duskChip, in: shape)
            .overlay { shape.strokeBorder(Color.duskGlassEdge, lineWidth: 1) }
    }
}

/// 1 px edge plus a 1 px highlight that fades out below the top.
struct DuskEdge<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        ZStack {
            shape.strokeBorder(Color.duskGlassEdge, lineWidth: 1)
            shape.strokeBorder(
                LinearGradient(colors: [Color.duskGlassHighlight, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Type

enum DuskType {
    /// Hero number: thin, rounded, tabular.
    static func hero(_ size: CGFloat = 112) -> Font { .system(size: size, weight: .light, design: .rounded).monospacedDigit() }
    /// Titles carry numbers too ("Level 3", "Round 2 of 4"), so they use tabular figures.
    static let title = Font.largeTitle.weight(.regular).monospacedDigit()
    static let screenTitle = Font.title.weight(.regular).monospacedDigit()
    static let body = Font.body
    static let label = Font.caption.weight(.semibold)
    static let data = Font.body.monospacedDigit()
}

/// Eyebrow label, e.g. "MOVEMENT AGE": small, bold, uppercase, tracked.
struct DuskLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(DuskType.label).tracking(2.5).foregroundStyle(Color.duskInk.opacity(0.68))
    }
}

extension View {
    /// Secondary text on glass: glassInk at reduced opacity.
    func duskSecondary() -> some View { foregroundStyle(Color.duskInk.opacity(0.72)) }
}

// MARK: - Buttons

/// Capsule button in one of the four Dusk types. Gaze: scale 1.035 plus a halo (primary) or chipStrong
/// (secondary); pinch: scale 0.95; disabled: 35% opacity, no glow. Hit area at least 60 pt.
struct DuskButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, tertiary }
    var kind: Kind = .primary
    var large = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
            .padding(.horizontal, kind == .tertiary ? 12 : (large ? 36 : 26))
            .frame(minHeight: Dusk.Layout.minHit)
            .contentShape(.capsule)

        return Group {
            switch kind {
            case .primary:
                label
                    .foregroundStyle(Color.duskOnAccent)
                    .background {
                        ZStack {
                            Capsule().fill(Color.duskAccentGlow).blur(radius: 14)
                                .hoverEffect { e, active, _ in e.opacity(active && enabled ? 1 : 0) }
                            Capsule().fill(Color.duskAccent)
                        }
                    }
            case .secondary:
                label
                    .foregroundStyle(Color.duskInk)
                    .background {
                        ZStack {
                            Capsule().fill(Color.duskChip)
                            Capsule().fill(Color.duskChipStrong)
                                .hoverEffect { e, active, _ in e.opacity(active ? 1 : 0) }
                        }
                    }
                    .overlay { Capsule().strokeBorder(Color.duskGlassEdge, lineWidth: 1) }
            case .tertiary:
                label.foregroundStyle(Color.duskInk.opacity(0.72))
            }
        }
        .scaleEffect(configuration.isPressed ? 0.95 : 1)
        .hoverEffect { e, active, _ in e.scaleEffect(active && enabled ? 1.035 : 1) }
        .hoverEffectGroup()
        .opacity(enabled ? 1 : 0.35)
        .animation(Dusk.Motion.quick, value: configuration.isPressed)
    }
}

/// Circle icon button: chip fill, icon at 1.35x.
struct DuskIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 17 * 1.35, weight: .medium))
            .foregroundStyle(Color.duskInk)
            .frame(width: Dusk.Layout.minHit, height: Dusk.Layout.minHit)
            .background {
                ZStack {
                    Circle().fill(Color.duskChip)
                    Circle().fill(Color.duskChipStrong).hoverEffect { e, active, _ in e.opacity(active ? 1 : 0) }
                }
            }
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .hoverEffect { e, active, _ in e.scaleEffect(active && enabled ? 1.035 : 1) }
            .hoverEffectGroup()
            .opacity(enabled ? 1 : 0.35)
            .animation(Dusk.Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DuskButtonStyle {
    static var duskPrimary: DuskButtonStyle { DuskButtonStyle(kind: .primary) }
    static var duskPrimaryLarge: DuskButtonStyle { DuskButtonStyle(kind: .primary, large: true) }
    static var duskSecondary: DuskButtonStyle { DuskButtonStyle(kind: .secondary) }
    static var duskSecondaryLarge: DuskButtonStyle { DuskButtonStyle(kind: .secondary, large: true) }
    static var duskTertiary: DuskButtonStyle { DuskButtonStyle(kind: .tertiary) }
}

extension ButtonStyle where Self == DuskIconButtonStyle {
    static var duskIcon: DuskIconButtonStyle { DuskIconButtonStyle() }
}

// MARK: - Controls

/// Toggle: track chipStrong, on = accentStrong, white knob. Whole row is the hit area.
struct DuskToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 16) {
                configuration.label.foregroundStyle(Color.duskInk)
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Color.duskAccentStrong : Color.duskChipStrong)
                        .frame(width: 52, height: 32)
                    Circle().fill(.white).frame(width: 26, height: 26).padding(3)
                }
                .animation(Dusk.Motion.quick, value: configuration.isOn)
            }
            .frame(minHeight: Dusk.Layout.minHit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Segmented control: capsule track in chip, selected segment chipStrong.
struct DuskSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(Dusk.Motion.quick) { selection = value } } label: {
                    Text(title).font(.callout.weight(.semibold))
                        .foregroundStyle(Color.duskInk.opacity(selection == value ? 1 : 0.72))
                        .padding(.horizontal, 18)
                        .frame(minHeight: Dusk.Layout.minHit - 8)
                        .background(selection == value ? Color.duskChipStrong : .clear, in: Capsule())
                        // The pill stays 52 pt; the 4 pt of track above and below joins the hit area (60 pt).
                        .padding(.vertical, 4)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
        .padding(.horizontal, 4)
        .background(Color.duskChip, in: Capsule())
    }
}

/// Status chip. Improved: accentSoft with an accentStrong dot. Neutral: 40% dot. Warn: warn dot.
struct DuskChip: View {
    enum Kind { case improved, neutral, warn }
    let text: String
    var kind: Kind = .neutral

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(Color.duskInk)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(kind == .improved ? Color.duskAccentSoft : Color.duskChip, in: Capsule())
    }

    private var dot: Color {
        switch kind {
        case .improved: .duskAccentStrong
        case .neutral: .duskInk.opacity(0.4)
        case .warn: .duskWarn
        }
    }
}

/// 6 pt capsule bar: track chipStrong, fill accentStrong. `xp` fills accent to accentStrong.
struct DuskBar: View {
    let fraction: Double
    var xp = false
    @State private var shown = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.duskChipStrong)
                Capsule()
                    .fill(xp ? AnyShapeStyle(LinearGradient(colors: [.duskAccent, .duskAccentStrong],
                                                            startPoint: .leading, endPoint: .trailing))
                             : AnyShapeStyle(Color.duskAccentStrong))
                    .frame(width: geo.size.width * min(max(shown, 0), 1))
            }
        }
        .frame(height: 6)
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.15)) { shown = fraction } }
        .onChange(of: fraction) { _, f in withAnimation(Dusk.Motion.spring) { shown = f } }
    }
}

/// Rounds won, or HUD progress. Done = glassInk 75%, current = gold, upcoming = chipStrong.
struct DuskDots: View {
    /// Widest the row may get. Long blocks (Gate has 30 trials) shrink the dots and gaps together, so the
    /// row cannot squeeze the text beside it in the HUD capsule.
    static let maxWidth: CGFloat = 220
    let total: Int
    let done: Int
    var current = true
    var size: CGFloat = 8

    var body: some View {
        let d = min(size, Self.maxWidth / CGFloat(max(2 * total - 1, 1)))
        HStack(spacing: d) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Circle().fill(color(i)).frame(width: d, height: d)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total)")
    }

    private func color(_ i: Int) -> Color {
        if i < done { return .duskInk.opacity(0.75) }
        if current && i == done { return Color(uiColor: Theme.gold) }
        return .duskChipStrong
    }
}
