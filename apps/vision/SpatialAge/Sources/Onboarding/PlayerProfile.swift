import Foundation
import ScoreKit

/// Setup answers kept on this headset. `participant` goes into every session, with height, weight and posture
/// copied in (schema 0.5). The first name is never stored.
struct PlayerProfile: Codable, Equatable {
    typealias Posture = Participant.Posture

    var participant: Participant
    var heightCm: Double
    /// Nil when the player skipped the weight question.
    var weightKg: Double?
    var posture: Posture

    private static let key = "sa.profile"

    static func load(_ defaults: UserDefaults = .standard) -> PlayerProfile? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PlayerProfile.self, from: $0) }
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    /// The participant with body size and posture filled in. Profiles saved before schema 0.5 lack them.
    var sessionParticipant: Participant {
        var p = participant
        p.heightCm = heightCm
        p.weightKg = weightKg
        p.posture = posture
        return p
    }
}

extension PlayerProfile.Posture {
    /// Seated play drops the games that need standing balance or a full reach.
    var skips: Set<Game> { self == .seated ? [.reach, .wall] : [] }
}

/// Answers while the setup flow is open. Optionals are questions not answered yet.
struct OnboardingDraft {
    var name = ""
    var age: Double = 62
    var sex: Participant.Sex?
    var heightCm: Double = 168
    var heightImperial = Locale.current.measurementSystem == .us
    var weightKg: Double = 73
    var weightImperial = Locale.current.measurementSystem == .us
    var weightSkipped = false
    var hand: Participant.Handedness?
    var posture: PlayerProfile.Posture?
    var code = Participant.randomCode()
    /// The age the player chose. Setup cannot continue on the default, so a skipped answer never labels a session.
    var ageSet = false

    init() {}

    init(_ p: PlayerProfile) {
        age = p.participant.ageYears
        ageSet = true
        sex = p.participant.sex
        heightCm = p.heightCm
        weightKg = p.weightKg ?? weightKg
        weightSkipped = p.weightKg == nil
        hand = p.participant.handedness
        posture = p.posture
        code = p.participant.code
    }

    var profile: PlayerProfile {
        PlayerProfile(
            participant: Participant(code: code, ageYears: age, sex: sex ?? .unspecified, handedness: hand ?? .right,
                                     heightCm: heightCm, weightKg: weightSkipped ? nil : weightKg,
                                     posture: posture ?? .standing),
            heightCm: heightCm,
            weightKg: weightSkipped ? nil : weightKg,
            posture: posture ?? .standing)
    }

    // Unit conversions used by the steppers and the review rows.
    var inches: Int { Int((heightCm / 2.54).rounded()) }
    var pounds: Int { Int((weightKg * 2.20462).rounded()) }

    mutating func stepHeight(_ d: Int) {
        heightCm = heightImperial
            ? Double(min(84, max(48, inches + d))) * 2.54
            : Double(min(215, max(120, Int(heightCm.rounded()) + d)))
    }

    mutating func stepWeight(_ d: Int) {
        weightKg = weightImperial
            ? Double(min(450, max(70, pounds + d))) / 2.20462
            : Double(min(200, max(30, Int(weightKg.rounded()) + d)))
        weightSkipped = false
    }

    var heightText: String { heightImperial ? "\(inches / 12)′ \(inches % 12)″" : "\(Int(heightCm.rounded())) cm" }
    var weightText: String {
        weightSkipped ? "Skipped" : (weightImperial ? "\(pounds) lb" : "\(Int(weightKg.rounded())) kg")
    }
}
