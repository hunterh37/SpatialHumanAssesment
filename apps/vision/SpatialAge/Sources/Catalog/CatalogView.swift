import ScoreKit
import SwiftUI

/// The catalog: the five games of the Games Ideas deck, in deck order. Play one or play all.
struct CatalogView: View {
    let start: ([Game]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline) {
                Text("Catalog").font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Play all") { start(Game.catalog) }
                    .buttonStyle(.borderedProminent)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 5), spacing: 18) {
                ForEach(Game.catalog, id: \.self) { game in
                    GameCard(game: game) { start([game]) }
                }
            }
        }
    }
}

struct GameCard: View {
    let game: Game
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 14) {
                GameGlyph(game: game).frame(height: 96)
                Text(game.title).font(.title3.weight(.semibold))
                Text(game.instruction).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(game.measures.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: .rect(cornerRadius: 28))
        .hoverEffect(.lift)
    }
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
                ctx.stroke(branch, with: .color(.white.opacity(0.7)), lineWidth: 2)
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
                    ctx.stroke(arc, with: .color(.white.opacity(0.7 - 0.18 * Double(k))), lineWidth: 1.5)
                }
                dot(leaf, 9, Theme.gold)
            case .gate:
                dot(CGPoint(x: c.x - 22, y: c.y), 13, Theme.go)
                dot(CGPoint(x: c.x + 22, y: c.y), 13, Theme.nogo)
            case .constellation:
                for i in 0..<9 {
                    let a = Double(i) / 8 * .pi
                    let p = CGPoint(x: c.x - 44 * cos(a), y: c.y + 10 - 30 * sin(a) + CGFloat(i % 2) * 8)
                    dot(p, i == 4 ? 7 : 4, i == 4 ? Theme.gold : Theme.mute)
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
                dot(CGPoint(x: c.x - 31, y: c.y - 21), 3.5, Theme.paper)
                dot(CGPoint(x: c.x - 21, y: c.y - 21), 3.5, Theme.paper)
                var arm = Path(); arm.move(to: CGPoint(x: c.x - 44, y: c.y + 22)); arm.addLine(to: CGPoint(x: c.x + 24, y: c.y + 10))
                ctx.stroke(arm, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
                ctx.fill(Path(roundedRect: CGRect(x: c.x + 28, y: c.y + 1, width: 16, height: 16), cornerRadius: 3),
                         with: .color(Color(uiColor: Theme.gold)))
            case .wall:
                // Wall with a body cut-out.
                let wall = CGRect(x: c.x - 46, y: c.y - 40, width: 92, height: 80)
                ctx.fill(Path(roundedRect: wall, cornerRadius: 4), with: .color(Color(uiColor: Theme.stone).opacity(0.6)))
                let ink = GraphicsContext.Shading.color(Color(uiColor: Theme.ink))
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
                dot(CGPoint(x: c.x, y: c.y + 26), 5, Theme.paper)
            }
    }
}
