import Foundation
import RealityKit

/// Procedural sound. Every cue is a short sine with an exponential decay, rendered to a WAV once and cached.
/// Sounds are spatial: they play from the entity that made them.
@MainActor
enum Tone {
    enum Cue: Hashable {
        /// Contact. Pitch rises with speed: `step` 0 (slow) to 6 (fast).
        case pop(step: Int)
        /// Constellation star, one pitch per star on a pentatonic scale.
        case star(Int)
        case tock
        case miss
        case caught
        /// A target appeared. A noise click over a tone: broadband onsets are what the ear localizes,
        /// so the participant can hear which way to turn before the target is in view.
        case spawn
    }

    private static var cache: [Cue: AudioFileResource] = [:]

    static func play(_ cue: Cue, on entity: Entity, gain: Double = -12) {
        guard let res = resource(cue) else { return }
        // Explicitly spatial and omnidirectional, so the cue comes from where the entity is.
        if entity.components[SpatialAudioComponent.self] == nil {
            entity.components.set(SpatialAudioComponent(directivity: .beam(focus: 0)))
        }
        let controller = entity.prepareAudio(res)
        controller.gain = gain
        controller.play()
    }

    static func resource(_ cue: Cue) -> AudioFileResource? {
        if let r = cache[cue] { return r }
        let partials: [(Double, Double)]
        let duration: Double
        var noise = 0.0
        switch cue {
        case .pop(let step):
            let f = 660 * pow(2, Double(min(max(step, 0), 6)) / 6)
            partials = [(f, 1), (f * 2, 0.25)]; duration = 0.09
        case .star(let i):
            let scale = [0, 2, 4, 7, 9, 12, 14, 16, 19]
            let f = 392 * pow(2, Double(scale[i % scale.count]) / 12)
            partials = [(f, 1), (f * 3, 0.12)]; duration = 0.5
        case .tock: partials = [(170, 1), (340, 0.3)]; duration = 0.12
        case .miss: partials = [(220, 0.6)]; duration = 0.18
        case .caught: partials = [(784, 1), (1176, 0.5)]; duration = 0.35
        case .spawn: partials = [(1046, 1), (2093, 0.35), (3136, 0.15)]; duration = 0.16; noise = 0.9
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(abs(cue.hashValue)).wav")
        do {
            try wav(partials: partials, duration: duration, noise: noise).write(to: url)
            let r = try AudioFileResource.load(contentsOf: url)
            cache[cue] = r
            return r
        } catch {
            return nil
        }
    }

    /// 16-bit mono 44.1 kHz PCM. 2 ms attack, decay to -60 dB at `duration`.
    /// `noise` mixes in a white noise burst that decays within the first 30 ms, at that amplitude relative to the tone.
    static func wav(partials: [(Double, Double)], duration: Double, noise: Double = 0) -> Data {
        let rate = 44_100.0
        let n = Int(rate * duration)
        let norm = partials.reduce(0) { $0 + $1.1 } + noise
        var rng = SeededRNG(seed: 1)
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / rate
            let env = min(t / 0.002, 1) * exp(-6.9 * t / duration)
            let click = noise > 0 ? noise * Double.random(in: -1...1, using: &rng) * exp(-6.9 * t / 0.03) : 0
            let s = (partials.reduce(0) { $0 + sin(2 * .pi * $1.0 * t) * $1.1 } * env + click) / norm * 0.8
            var v = Int16(max(-1, min(1, s)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        h.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        h.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        h.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        return h + pcm
    }
}
