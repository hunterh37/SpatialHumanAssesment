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
        /// Timeout or drop: one soft low mallet note. Quiet, so a miss never reads as punishment.
        case miss
        /// Wrong touch (orange touched, wrong star, wrong ball, wall hit): two soft mallet notes falling a
        /// minor third. Warm and short, never a buzzer.
        case wrong
        case caught
        /// Spatial Tracking warning: a short leaf rustle, played from where the leaf will fall.
        case rustle
        /// Scary Balance creature: a low hum with a slow wobble, about 2 s.
        case creature
        /// Songbird call, variant 0 to 3. Swept sines, finch-like.
        case chirp(Int)
        /// Songbird trill while petted.
        case trill
        /// Songbird alarm when startled off the hand.
        case alarm
        /// Wing whirr at takeoff.
        case whirr
        /// Buddy talking: one soft syllable per word while a speech bubble types out, variant 0 to 3.
        /// Lower and shorter than `.chirp`, so a line reads as chatter, not song.
        case peep(Int)
        /// Speech bubble tapped: a low rising plop.
        case bubble
        /// A target appeared. A noise click over a tone: broadband onsets are what the ear localizes,
        /// so the participant can hear which way to turn before the target is in view.
        case spawn
        /// Success charm: a rising bell arpeggio. Tier 0 to 3 lifts the register and adds a top note.
        case chime(Int)
        /// High glassy twinkles layered over a chime from tier 2.
        case sparkle
        /// End of a scored block: arpeggio up to a held major chord, about 1.4 s.
        case fanfare
        /// Lock-on: two quick rising mallet notes. Orbit acquisition, Reach and Grab floor spot reached.
        case lock
        /// Your turn: a soft rising bell fifth. Constellation and Color Dots response phase begins.
        case ready
        /// Quiet confirm for a correct hold-back: Gate no-go left alone, Scary Balance freeze held. One bell
        /// note with its fifth, no arpeggio.
        case soft
    }

    /// One bell strike: start (s), frequency (Hz), decay length (s), relative gain.
    typealias Strike = (start: Double, freq: Double, length: Double, gain: Double)

    /// One swept syllable: start and length in seconds, start and end frequency in Hz, relative gain.
    typealias Syllable = (start: Double, length: Double, from: Double, to: Double, gain: Double)

    private static let calls: [[Syllable]] = [
        [(0, 0.07, 3600, 5200, 1), (0.10, 0.09, 5000, 3400, 0.9)],
        [(0, 0.045, 3200, 4300, 1), (0.075, 0.045, 3300, 4400, 0.9), (0.15, 0.045, 3400, 4500, 0.85),
         (0.225, 0.05, 4600, 3600, 0.8)],
        [(0, 0.11, 3000, 5600, 1)],
        [(0, 0.06, 5200, 4000, 1), (0.09, 0.06, 5100, 3900, 0.85)],
    ]

    /// Talking syllables: rise, fall, rise-fall, flat. 2.2 to 3.4 kHz, 45 to 70 ms.
    private static let peeps: [Syllable] = [
        (0, 0.055, 2400, 3200, 1), (0, 0.06, 3300, 2500, 1), (0, 0.07, 2600, 3400, 1), (0, 0.045, 2900, 2800, 1),
    ]

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
        if let strikes = bells(cue) { return store(cue, Self.bell(strikes)) }
        if let strikes = mallets(cue) { return store(cue, Self.bell(strikes, partials: Self.mallet)) }
        var partials: [(Double, Double)]
        var duration: Double
        var noise = 0.0, click = 0.0, sustain = false
        var song: [Syllable]?
        switch cue {
        case .chirp(let k): song = calls[abs(k) % calls.count]; partials = []; duration = 0
        case .trill: song = (0..<9).map { (Double($0) * 0.045, 0.032, 4300, 4900, 1) }; partials = []; duration = 0
        case .alarm: song = (0..<3).map { (Double($0) * 0.06, 0.04, 6000, 3800, 1) }; partials = []; duration = 0
        case .whirr: partials = [(120, 0.05)]; duration = 0.32; noise = 1
        case .peep(let k): song = [Self.peeps[abs(k) % Self.peeps.count]]; partials = []; duration = 0
        case .bubble: song = [(0, 0.075, 380, 820, 1), (0.05, 0.05, 900, 1300, 0.25)]; partials = []; duration = 0
        case .pop(let step):
            let f = 660 * pow(2, Double(min(max(step, 0), 6)) / 6)
            partials = [(f, 1), (f * 2, 0.25)]; duration = 0.09
        case .star(let i):
            let scale = [0, 2, 4, 7, 9, 12, 14, 16, 19]
            let f = 392 * pow(2, Double(scale[i % scale.count]) / 12)
            partials = [(f, 1), (f * 3, 0.12)]; duration = 0.5
        case .tock: partials = [(170, 1), (340, 0.3)]; duration = 0.12
        case .caught: partials = [(784, 1), (1176, 0.5)]; duration = 0.35
        case .rustle: partials = [(2400, 0.08)]; duration = 0.45; noise = 1
        case .creature: partials = [(73, 1), (110, 0.6), (146, 0.25)]; duration = 2.2; sustain = true
        case .spawn: partials = [(1046, 1), (2093, 0.35), (3136, 0.15)]; duration = 0.16; click = 0.9
        case .chime, .sparkle, .fanfare, .ready, .soft, .miss, .wrong, .lock: return nil
        }
        return store(cue, song.map(Self.song)
            ?? wav(partials: partials, duration: duration, noise: noise, click: click, sustain: sustain))
    }

    private static func store(_ cue: Cue, _ data: Data) -> AudioFileResource? {
        let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(abs(cue.hashValue)).wav")
        do {
            try data.write(to: url)
            let r = try AudioFileResource.load(contentsOf: url)
            cache[cue] = r
            return r
        } catch {
            return nil
        }
    }

    /// Strike lists for the reward cues. Major pentatonic on C6, so every cue sits in one key with `.star`.
    private static func bells(_ cue: Cue) -> [Strike]? {
        func hz(_ semis: Double) -> Double { 1046.5 * pow(2, semis / 12) }
        switch cue {
        case .chime(let tier):
            let t = Double(min(max(tier, 0), 3))
            let root = [0.0, 2, 4, 7][Int(t)]
            var notes = [0.0, 4, 7, 12].map { root + $0 }
            if t >= 1 { notes.append(root + 16) }
            if t >= 3 { notes.append(root + 19) }
            return notes.enumerated().map { (Double($0.offset) * 0.045, hz($0.element - 12), 0.55, 1 - 0.08 * Double($0.offset)) }
        case .sparkle:
            return [(0.02, hz(24), 0.18, 0.5), (0.07, hz(28), 0.16, 0.45), (0.11, hz(31), 0.15, 0.4),
                    (0.16, hz(36), 0.14, 0.35), (0.22, hz(28), 0.2, 0.3)]
        case .fanfare:
            let run = [0.0, 4, 7, 12, 16, 19].enumerated().map { (Double($0.offset) * 0.07, hz($0.element - 12), 0.5, 0.8) }
            let chord = [0.0, 4, 7, 12].map { (0.48, hz($0 - 12), 1.1, 0.7) }
            return run + chord + [(0.5, hz(24), 0.8, 0.35)]
        case .ready:
            return [(0, hz(-12), 0.45, 0.8), (0.09, hz(-5), 0.55, 0.7)]
        case .soft:
            return [(0, hz(-8), 0.5, 0.8), (0.02, hz(-1), 0.4, 0.3)]
        default:
            return nil
        }
    }

    /// Strike lists for the mallet cues. Same key as the bells, an octave or two lower, so error tones stay
    /// in tune with the music bed and the chimes.
    private static func mallets(_ cue: Cue) -> [Strike]? {
        func hz(_ semis: Double) -> Double { 1046.5 * pow(2, semis / 12) }
        switch cue {
        case .miss: return [(0, hz(-27), 0.42, 1)]
        case .wrong: return [(0, hz(-21), 0.24, 0.85), (0.12, hz(-24), 0.42, 1)]
        case .lock: return [(0, hz(-5), 0.16, 0.8), (0.06, hz(0), 0.26, 1)]
        default: return nil
        }
    }

    typealias Partial = (ratio: Double, gain: Double, decay: Double)
    /// Glockenspiel ratios: bright, long ring.
    nonisolated static let glock: [Partial] = [(1, 1, 1), (2.76, 0.32, 0.45), (5.40, 0.12, 0.25), (2, 0.18, 0.7)]
    /// Marimba ratios: a round fundamental, a quiet fourth partial that dies fast. Soft and wooden.
    nonisolated static let mallet: [Partial] = [(1, 1, 1), (3.93, 0.10, 0.18), (2, 0.06, 0.4)]

    /// Bell partials with a soft 3 ms attack and exponential decay, summed and normalized.
    static func bell(_ strikes: [Strike], partials: [Partial] = glock) -> Data {
        let rate = 44_100.0
        let duration = (strikes.map { $0.start + $0.length }.max() ?? 0) + 0.02
        let n = Int(rate * duration)
        var samples = [Double](repeating: 0, count: n)
        for s in strikes {
            let i0 = Int(s.start * rate), count = Int(s.length * rate)
            for k in 0..<count where i0 + k < n {
                let t = Double(k) / rate
                let attack = min(t / 0.003, 1)
                var v = 0.0
                for p in partials where s.freq * p.ratio < 16_000 {
                    v += sin(2 * .pi * s.freq * p.ratio * t) * p.gain * exp(-6.9 * t / (s.length * p.decay))
                }
                samples[i0 + k] += v * attack * s.gain
            }
        }
        let peak = max(samples.map(abs).max() ?? 1, 1e-6)
        var pcm = Data(capacity: n * 2)
        for x in samples {
            var v = Int16(max(-1, min(1, x / peak * 0.8)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        return riff(pcm, rate: rate)
    }

    /// 16-bit mono 44.1 kHz PCM. 2 ms attack, decay to -60 dB at `duration`. `noise` mixes in band-limited
    /// noise with a fast flutter (a rustle). `click` mixes in a white noise burst that decays within the first
    /// 30 ms. `sustain` holds level with a 3 Hz wobble and fades at both ends.
    static func wav(partials: [(Double, Double)], duration: Double, noise: Double = 0, click: Double = 0,
                    sustain: Bool = false) -> Data {
        let rate = 44_100.0
        let n = Int(rate * duration)
        let norm = partials.reduce(0) { $0 + $1.1 } + noise + click
        var clickRNG = SeededRNG(seed: 1)
        var pcm = Data(capacity: n * 2)
        var rng = SeededRNG(seed: 7)
        var low = 0.0, prev = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            let env = sustain
                ? min(t / 0.25, 1) * min((duration - t) / 0.4, 1) * (0.75 + 0.25 * sin(2 * .pi * 3 * t))
                : min(t / 0.002, 1) * exp(-6.9 * t / duration)
            // Noise: white, one-pole low-passed, then high-passed by differencing, gated by a 22 Hz flutter.
            var hiss = 0.0
            if noise > 0 {
                let white = Double(rng.next() >> 11) / Double(1 << 53) * 2 - 1
                low += 0.35 * (white - low)
                hiss = (low - prev) * 3 * (0.55 + 0.45 * sin(2 * .pi * 22 * t)) * noise
                prev = low
            }
            let burst = click > 0 ? click * Double.random(in: -1...1, using: &clickRNG) * exp(-6.9 * t / 0.03) : 0
            let tone = partials.reduce(0) { $0 + sin(2 * .pi * $1.0 * t) * $1.1 }
            let s = ((tone + hiss) * env + burst) / norm * 0.8
            var v = Int16(max(-1, min(1, s)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        return riff(pcm, rate: rate)
    }

    /// Bird call: exponential frequency sweeps with a soft second harmonic, normalized to 0.8 peak.
    static func song(_ syllables: [Syllable]) -> Data {
        let rate = 44_100.0
        let duration = (syllables.map { $0.start + $0.length }.max() ?? 0) + 0.02
        let n = Int(rate * duration)
        var samples = [Double](repeating: 0, count: n)
        for s in syllables {
            var phase = 0.0
            let i0 = Int(s.start * rate), count = max(Int(s.length * rate), 1)
            for k in 0..<count where i0 + k < n {
                let u = Double(k) / Double(count)
                phase += 2 * .pi * s.from * pow(s.to / s.from, u) / rate
                samples[i0 + k] += (sin(phase) + 0.18 * sin(2 * phase)) * pow(sin(.pi * u), 0.7) * s.gain
            }
        }
        let peak = max(samples.map(abs).max() ?? 1, 1e-6)
        var pcm = Data(capacity: n * 2)
        for x in samples {
            var v = Int16(max(-1, min(1, x / peak * 0.8)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        return riff(pcm, rate: rate)
    }

    /// RIFF header for 16-bit mono PCM.
    private static func riff(_ pcm: Data, rate: Double) -> Data {
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
