import ScoreKit
import SwiftUI

/// Games tab (Dusk spec section 7): centered title and primary "Play all", hand anatomy picker top left, music top right, above a 4 x 2 grid of the eight games.
/// A card opens that game's intro.
struct GamesView: View {
    @Environment(AppModel.self) private var model
    let start: ([Game]) -> Void

    var body: some View {
        if let game = model.intro {
            GameIntroView(game: game, start: start)
                .transition(.opacity)
        } else {
            VStack(spacing: 16) {
                // The one primary action on this screen sits on the center line, under the title.
                VStack(spacing: 8) {
                    Text(DuskCopy.gamesTitle).font(DuskType.title)
                    Button("Play all") { start(model.games) }.buttonStyle(.duskPrimary)
                }
                .frame(maxWidth: .infinity)
                // Hand anatomy viewer (X-ray / Muscle) in the top corner, beside the centered title.
                .overlay(alignment: .topLeading) { AnatomyToggle().frame(width: 300) }
                .overlay(alignment: .topTrailing) { MusicMiniPlayer(compact: true).frame(width: 300) }
                if let notice = model.notice { DuskChip(text: notice) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Dusk.Layout.spacing), count: 4),
                          spacing: Dusk.Layout.spacing) {
                    ForEach(model.games, id: \.self) { game in
                        GameCard(game: game) { withAnimation(Dusk.Motion.spring) { model.intro = game } }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }
}

/// One game: glyph, title, one instruction line, uppercase measures label. Lifts on gaze.
/// Fixed height, sized for three lines of instruction and three of label, so the grid reads as a clean 4 x 2
/// and the two rows fit the 800 pt window.
struct GameCard: View {
    static let height: CGFloat = 272
    let game: Game
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                GameGlyph(game: game).frame(height: 84)
                Text(game.duskTitle).font(.title3)
                Text(game.duskInstruction).font(.callout).duskSecondary()
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                DuskLabel(game.duskMeasures)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.height)
            .contentShape(.rect(cornerRadius: Dusk.Layout.cardRadius))
        }
        .buttonStyle(.plain)
        .duskCard()
        .hoverEffect(.lift)
    }
}

/// Game intro (Dusk spec section 7): back icon, measures label, title, one line, then the centered primary
/// "Start", the practice toggle and tertiary "Skip this game"; "Before you start" sits in a side panel.
/// "Practice round first" is `AppModel.practiceFirst` (on by default). `ImmersiveView` passes it to
/// `Director`, which runs the existing unscored familiarization block before the scored one when it is on.
struct GameIntroView: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let start: ([Game]) -> Void

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .center, spacing: 40) {
            VStack(spacing: Dusk.Layout.spacing) {
                HStack {
                    Button("Back", systemImage: "chevron.left") { close() }.buttonStyle(.duskIcon)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    DuskLabel(game.duskMeasures)
                    Text(game.duskTitle).font(DuskType.title)
                    Text(game.duskInstruction).font(.title3).duskSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                GameGlyph(game: game).frame(width: 160, height: 96)
                Button("Start") { start([game]) }.buttonStyle(.duskPrimaryLarge)
                Toggle("Practice round first", isOn: $model.practiceFirst)
                    .toggleStyle(DuskToggleStyle())
                    .frame(maxWidth: 360)
                Button("Skip this game") { close() }.buttonStyle(.duskTertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                DuskLabel("Before you start")
                ForEach(Array(DuskCopy.beforeYouStart.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(i + 1)").font(.title3.weight(.light)).monospacedDigit()
                            .foregroundStyle(Color.duskAccentStrong)
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(26)
            .frame(width: 340, alignment: .leading)
            .duskCard()
        }
    }

    private func close() { withAnimation(Dusk.Motion.spring) { model.intro = nil } }
}

/// Minimal mark per game, drawn from the same shapes the game uses.
struct GameGlyph: View {
    let game: Game

    var body: some View {
        Canvas { ctx, size in Self.draw(game, &ctx, size) }
    }

    /// Drawn in a typed function: one closure holding every glyph was too slow for the type checker.
    static func draw(_ game: Game, _ ctx: inout GraphicsContext, _ size: CGSize) {
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func dot(_ p: CGPoint, _ r: CGFloat, _ color: UIColor) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(uiColor: color)))
            }
            switch game {
            case .pendulum:
                // Branch with hanging leaves, one falling.
                var branch = Path(); branch.move(to: CGPoint(x: c.x - 52, y: 14)); branch.addLine(to: CGPoint(x: c.x + 52, y: 14))
                ctx.stroke(branch, with: .color(Color.duskInk.opacity(0.7)), lineWidth: 2)
                for i in 0..<7 where i != 4 {
                    dot(CGPoint(x: c.x - 45 + CGFloat(i) * 15, y: 24), 5, Theme.gold)
                }
                dot(CGPoint(x: c.x + 15, y: size.height - 16), 7, Theme.gold)
            case .spark:
                // Sound arcs toward a falling leaf.
                let leaf = CGPoint(x: c.x + 22, y: c.y + 4)
                for k in 1...3 {
                    var arc = Path()
                    arc.addArc(center: leaf, radius: CGFloat(10 + 9 * k), startAngle: .degrees(150), endAngle: .degrees(210),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(Color.duskInk.opacity(0.7 - 0.18 * Double(k))), lineWidth: 1.5)
                }
                dot(leaf, 9, Theme.gold)
            case .gate:
                dot(CGPoint(x: c.x - 22, y: c.y), 13, Theme.go)
                dot(CGPoint(x: c.x + 22, y: c.y), 13, Theme.nogo)
            case .constellation:
                for i in 0..<9 {
                    let a = Double(i) / 8 * .pi
                    let p = CGPoint(x: c.x - 44 * cos(a), y: c.y + 10 - 30 * sin(a) + CGFloat(i % 2) * 8)
                    dot(p, i == 4 ? 7 : 4, i == 4 ? Theme.gold : Dusk.mute)
                }
            case .orbit:
                var path = Path()
                for i in 0...80 {
                    let t = Double(i) / 80 * 2 * .pi
                    let p = CGPoint(x: c.x + 40 * sin(t), y: c.y + 26 * sin(2 * t + 0.6))
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                ctx.stroke(path, with: .color(Color(uiColor: Theme.teal).opacity(0.35)), lineWidth: 1)
                dot(CGPoint(x: c.x + 40 * sin(1.1), y: c.y + 26 * sin(2.2 + 0.6)), 9, Theme.teal)
            case .reach:
                // Reaching arm, the cube, and the creature passing behind.
                dot(CGPoint(x: c.x - 26, y: c.y - 18), 16, Theme.creature)
                dot(CGPoint(x: c.x - 31, y: c.y - 21), 3.5, Dusk.glassInk)
                dot(CGPoint(x: c.x - 21, y: c.y - 21), 3.5, Dusk.glassInk)
                var arm = Path(); arm.move(to: CGPoint(x: c.x - 44, y: c.y + 22)); arm.addLine(to: CGPoint(x: c.x + 24, y: c.y + 10))
                ctx.stroke(arm, with: .color(Color.duskInk.opacity(0.7)), lineWidth: 1.5)
                ctx.fill(Path(roundedRect: CGRect(x: c.x + 28, y: c.y + 1, width: 16, height: 16), cornerRadius: 3),
                         with: .color(Color(uiColor: Theme.gold)))
            case .wall:
                // Wall with a body cut-out.
                let wall = CGRect(x: c.x - 46, y: c.y - 40, width: 92, height: 80)
                ctx.fill(Path(roundedRect: wall, cornerRadius: 4), with: .color(Color(uiColor: Theme.stone).opacity(0.6)))
                let ink = GraphicsContext.Shading.color(Color.duskBg)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 34, width: 14, height: 14)), with: ink)
                ctx.fill(Path(roundedRect: CGRect(x: c.x - 9, y: c.y - 18, width: 18, height: 30), cornerRadius: 4), with: ink)
                var arms = Path()
                arms.move(to: CGPoint(x: c.x - 34, y: c.y - 30)); arms.addLine(to: CGPoint(x: c.x - 6, y: c.y - 14))
                arms.move(to: CGPoint(x: c.x + 34, y: c.y - 30)); arms.addLine(to: CGPoint(x: c.x + 6, y: c.y - 14))
                arms.move(to: CGPoint(x: c.x - 5, y: c.y + 10)); arms.addLine(to: CGPoint(x: c.x - 9, y: c.y + 38))
                arms.move(to: CGPoint(x: c.x + 5, y: c.y + 10)); arms.addLine(to: CGPoint(x: c.x + 9, y: c.y + 38))
                ctx.stroke(arms, with: ink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                dot(CGPoint(x: c.x - 34, y: c.y - 30), 6, Theme.go)
                dot(CGPoint(x: c.x + 34, y: c.y - 30), 6, Theme.go)
            case .dots:
                // Balls of mixed color and size around the participant.
                let colors = [Theme.go, Theme.nogo, Theme.go, Theme.gold, Theme.teal, Theme.go, Theme.nogo]
                for i in 0..<7 {
                    let a = Double(i) / 6 * .pi
                    let p = CGPoint(x: c.x - 44 * cos(a), y: c.y + 14 - 30 * sin(a))
                    dot(p, i % 2 == 0 ? 8 : 5, colors[i])
                }
                dot(CGPoint(x: c.x, y: c.y + 26), 5, Dusk.glassInk)
            }
    }
}
