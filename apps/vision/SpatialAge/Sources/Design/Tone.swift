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
        /// Spatial Tracking warning: a short leaf rustle, played from where the leaf will fall.
        case rustle
        /// Scary Balance creature: a low hum with a slow wobble, about 2 s.
        case creature
    }

    private static var cache: [Cue: AudioFileResource] = [:]

    static func play(_ cue: Cue, on entity: Entity, gain: Double = -12) {
        guard let res = resource(cue) else { return }
        let controller = entity.prepareAudio(res)
        controller.gain = gain
        controller.play()
    }

    static func resource(_ cue: Cue) -> AudioFileResource? {
        if let r = cache[cue] { return r }
        var partials: [(Double, Double)]
        var duration: Double
        var noise = 0.0, sustain = false
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
        case .rustle: partials = [(2400, 0.08)]; duration = 0.45; noise = 1
        case .creature: partials = [(73, 1), (110, 0.6), (146, 0.25)]; duration = 2.2; sustain = true
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(abs(cue.hashValue)).wav")
        do {
            try wav(partials: partials, duration: duration, noise: noise, sustain: sustain).write(to: url)
            let r = try AudioFileResource.load(contentsOf: url)
            cache[cue] = r
            return r
        } catch {
            return nil
        }
    }

    /// 16-bit mono 44.1 kHz PCM. 2 ms attack, decay to -60 dB at `duration`. `noise` mixes in band-limited
    /// noise with a fast flutter (a rustle). `sustain` holds level with a 3 Hz wobble and fades at both ends.
    static func wav(partials: [(Double, Double)], duration: Double, noise: Double = 0, sustain: Bool = false) -> Data {
        let rate = 44_100.0
        let n = Int(rate * duration)
        let norm = partials.reduce(0) { $0 + $1.1 } + noise
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
            let tone = partials.reduce(0) { $0 + sin(2 * .pi * $1.0 * t) * $1.1 }
            let s = (tone + hiss) / norm * env * 0.8
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
