import SwiftUI

/// Games screen corner card: what is playing and a play/pause icon button (Dusk spec section 7). The icon button is the
/// standard circle, chip fill, 1.35x icon, 60 pt hit area. Hidden when the bundle holds no tracks.
/// `MusicBed` saves the choice in UserDefaults `music.enabled`.
struct MusicMiniPlayer: View {
    @Environment(AppModel.self) private var model
    /// Tighter padding and type for the Games title row.
    var compact = false

    var body: some View {
        let music = model.music
        if music.isAvailable {
            HStack(spacing: Dusk.Layout.spacing) {
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    DuskLabel("Music")
                    Text(music.title).font(compact ? .headline : .title3).lineLimit(1)
                    Text(status).font(.callout).duskSecondary()
                }
                Spacer(minLength: 0)
                Button(verb, systemImage: music.enabled ? "pause.fill" : "play.fill") { music.toggle() }
                    .buttonStyle(.duskIcon)
                    .accessibilityLabel(verb)
            }
            .padding(compact ? 12 : 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .duskCard()
            .animation(Dusk.Motion.quick, value: music.enabled)
        }
    }

    /// What the button does next.
    private var verb: String { model.music.enabled ? "Pause music" : "Play music" }

    /// The bed stays quiet while Sky Plank is on, so say so instead of leaving a silent "Playing".
    private var status: String {
        if !model.music.enabled { return "Paused" }
        return model.skyPlank ? "Quiet during Sky Plank" : "Playing"
    }
}
