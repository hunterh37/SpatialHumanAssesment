import ScoreKit

/// Screen copy from the Dusk spec, section 7. Game cards use this copy exactly.
/// ScoreKit's `title`, `instruction` and `measures` stay as they are for reports and stored sessions.
extension Game {
    /// The eight games in Dusk spec order, for the Games grid (4 x 2) and "Play all".
    static let dusk: [Game] = [.pendulum, .spark, .gate, .constellation, .orbit, .reach, .wall, .dots]

    var duskTitle: String {
        switch self {
        case .pendulum: "Pendulum"
        case .spark: "Spark"
        case .gate: "Gate"
        case .constellation: "Constellation"
        case .orbit: "Orbit"
        case .reach: "Reach and Grab"
        case .wall: "Hole in the Wall"
        case .dots: "Color Dots"
        }
    }

    var duskInstruction: String {
        switch self {
        case .pendulum: "Catch the weight when the cord lets go."
        case .spark: "Touch each light as it appears."
        case .gate: "Touch blue. Leave orange."
        case .constellation: "Watch the stars light, then touch them in order."
        case .orbit: "Keep your fingertip inside the moving light."
        case .reach: "Keep your feet planted. Reach out and touch each object."
        case .wall: "Fit your hands into the holes and hold still as the wall passes."
        case .dots: "Watch which dots light up, then touch only those."
        }
    }

    var duskMeasures: String {
        switch self {
        case .pendulum: "Catch latency and drop distance"
        case .spark: "Reaction and reach"
        case .gate: "Decision time and inhibition"
        case .constellation: "Spatial working memory"
        case .orbit: "Tracking error and lag"
        case .reach: "Reach distance and lean"
        case .wall: "Sway and hand steadiness"
        case .dots: "Spatial recall and decisions"
        }
    }
}

enum DuskCopy {
    static let brand = "SpatialAge"
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
