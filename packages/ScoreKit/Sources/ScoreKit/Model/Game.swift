/// The minigames. Each one runs one task kind from the session schema.
/// Raw values and task kinds predate the Games Ideas deck and stay fixed so stored sessions keep scoring.
public enum Game: String, CaseIterable, Codable, Sendable {
    case pendulum, spark, gate, constellation, orbit, reach, wall, dots

    /// The catalog, in the order of the Games Ideas deck (specs/games/README.md). Gate, Constellation and Orbit
    /// are outside the deck: they still run and score when queued, but the catalog does not list them.
    public static let catalog: [Game] = [.pendulum, .dots, .reach, .wall, .spark]

    public var task: TaskKind {
        switch self {
        case .pendulum: .pendulum
        case .spark: .simpleRT
        case .gate: .choiceRT
        case .constellation: .corsi
        case .orbit: .pursuit
        case .reach: .reachGrab
        case .wall: .wall
        case .dots: .colorDots
        }
    }

    public init?(task: TaskKind) {
        guard let g = Game.allCases.first(where: { $0.task == task }) else { return nil }
        self = g
    }

    public var title: String {
        switch self {
        case .pendulum: "Stick Drop"
        case .spark: "Spatial Tracking"
        case .gate: "Gate"
        case .constellation: "Constellation"
        case .orbit: "Orbit"
        case .reach: "Scary Balance"
        case .wall: "Hole in the Wall"
        case .dots: "Spatial Memory"
        }
    }

    /// One line shown on the catalog card.
    public var instruction: String {
        switch self {
        case .pendulum: "Catch the falling leaf before it hits the ground."
        case .spark: "Listen and look. Point at each falling leaf before it lands."
        case .gate: "Touch blue as fast as you can. Leave orange."
        case .constellation: "Watch the stars light, then touch them in order."
        case .orbit: "Keep your fingertip inside the moving light."
        case .reach: "Walk to the glowing spot and reach for the object. Freeze when the creature passes."
        case .wall: "Stay on the island. Make the shape in the wall and hold it as the wall passes."
        case .dots: "Touch the balls you are asked for. Then find the ones you did, or did not, touch."
        }
    }

    /// Scored on speed. The HUD says so before the countdown.
    public var isTimed: Bool {
        switch self {
        case .pendulum, .spark, .gate: true
        default: false
        }
    }

    /// What the game measures, for the catalog card and the report.
    public var measures: String {
        switch self {
        case .pendulum: "Visual reaction time and useful field of view"
        case .spark: "Audio and visual reaction time and localization"
        case .gate: "Decision time and inhibition"
        case .constellation: "Spatial working memory span"
        case .orbit: "Visuomotor tracking error and lag"
        case .reach: "Reach, lean and holding still"
        case .wall: "Arm mobility and pose holding"
        case .dots: "Decision time and spatial memory"
        }
    }

    /// Scored trials per run. Familiarization trials come first and are not scored.
    public var scoredTrials: Int {
        switch self {
        case .pendulum: 16
        case .spark: 16
        case .gate: 30
        case .constellation: 14
        case .orbit: 3
        case .reach: 12
        case .wall: 8
        case .dots: 10
        }
    }

    public var familiarizationTrials: Int {
        switch self {
        case .pendulum: 3
        case .spark: 3
        case .gate: 5
        case .constellation: 1
        case .orbit: 1
        case .reach: 2
        case .wall: 1
        case .dots: 1
        }
    }
}
