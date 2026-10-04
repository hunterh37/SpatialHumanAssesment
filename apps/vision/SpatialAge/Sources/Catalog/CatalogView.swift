import ScoreKit
import SwiftUI

/// The catalog. Five cards, one color each, one line each. Play one or play all.
struct CatalogView: View {
    let start: ([Game]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline) {
                Text("Catalog").font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Play all") { start(Game.allCases) }
                    .buttonStyle(.borderedProminent)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 5), spacing: 18) {
                ForEach(Game.allCases, id: \.self) { game in
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
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func dot(_ p: CGPoint, _ r: CGFloat, _ color: UIColor) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(uiColor: color)))
            }
            switch game {
            case .pendulum:
                let pivot = CGPoint(x: c.x, y: 6), bob = CGPoint(x: c.x + 22, y: size.height - 18)
                var cord = Path(); cord.move(to: pivot); cord.addLine(to: bob)
                ctx.stroke(cord, with: .color(.white.opacity(0.7)), lineWidth: 1)
                dot(bob, 11, Theme.gold)
            case .spark:
                dot(c, 14, Theme.go)
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
            }
        }
    }
}
