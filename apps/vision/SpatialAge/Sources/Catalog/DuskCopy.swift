import ScoreKit

/// Screen copy. Game titles, instructions and measures are the as-built Games-deck copy in ScoreKit's `Game`,
/// which is newer than the Dusk spec table in section 7. The screens and the HUD show it as is: edit the words
/// in `Game.swift`, never here, so the cards, the HUD and the reports cannot drift apart.
extension Game {
    /// The eight games in Dusk spec order, for the Games grid (4 x 2) and "Play all".
    static let dusk: [Game] = [.pendulum, .spark, .gate, .constellation, .orbit, .reach, .wall, .dots]

    /// Display name. Forwards to the as-built title.
    var duskTitle: String { title }
    /// One instruction line. Forwards to the as-built instruction.
    var duskInstruction: String { instruction }
    /// What the game measures, shown as an uppercase label. Forwards to the as-built text.
    var duskMeasures: String { measures }
}

enum DuskCopy {
    static let brand = "Better Years"
    static let homeTitle = "How old do you move?"
    static let homeLine = "Eight short games read your reaction, reach, balance and memory. About six minutes, standing in place."
    static let gamesTitle = "Pick one, or play all eight"
    static let beforeYouStart = [
        "Stand in a clear space with room to reach in every direction.",
        "Keep your feet planted and your hands in view.",
        "Follow the one line at the top. A miss is fine; keep going.",
    ]
    static let consentLine = "Short reach and memory games in full immersion. No names are stored, only a participant code. This is a game score, not a medical test."
}
