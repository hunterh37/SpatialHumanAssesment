/// The five minigames. Each one runs one task kind from the session schema.
public enum Game: String, CaseIterable, Codable, Sendable {
    case pendulum, spark, gate, constellation, orbit

    public var task: TaskKind {
        switch self {
        case .pendulum: .pendulum
        case .spark: .simpleRT
        case .gate: .choiceRT
        case .constellation: .corsi
        case .orbit: .pursuit
        }
    }

    public init?(task: TaskKind) {
        guard let g = Game.allCases.first(where: { $0.task == task }) else { return nil }
        self = g
    }

    public var title: String {
        switch self {
        case .pendulum: "Pendulum"
        case .spark: "Spark"
        case .gate: "Gate"
        case .constellation: "Constellation"
        case .orbit: "Orbit"
        }
    }

    /// One line shown on the catalog card.
    public var instruction: String {
        switch self {
        case .pendulum: "Catch the weight when the cord lets go."
        case .spark: "Touch each light as it appears."
        case .gate: "Touch blue. Leave orange."
        case .constellation: "Watch the stars light, then touch them in order."
        case .orbit: "Keep your fingertip inside the moving light."
        }
    }

    /// What the game measures, for the catalog card and the report.
    public var measures: String {
        switch self {
        case .pendulum: "Catch latency and drop distance"
        case .spark: "Reaction, movement and reach kinematics"
        case .gate: "Decision time and inhibition"
        case .constellation: "Spatial working memory span"
        case .orbit: "Visuomotor tracking error and lag"
        }
    }

    /// Scored trials per run. Familiarization trials come first and are not scored.
    public var scoredTrials: Int {
        switch self {
        case .pendulum: 12
        case .spark: 20
        case .gate: 30
        case .constellation: 14
        case .orbit: 3
        }
    }

    public var familiarizationTrials: Int {
        switch self {
        case .pendulum: 3
        case .spark: 5
        case .gate: 5
        case .constellation: 1
        case .orbit: 1
        }
    }
}
