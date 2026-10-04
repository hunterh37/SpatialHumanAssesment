import Foundation
import RealityKit
import RealKit
import RealLibrary
import simd

/// Height-exposure viewer: RealityHD `rooftop-plank` (a 30 cm board between two 40-storey towers,
/// a downtown grid 150 m below), sky dome, sun and IBL, plus looping wind. The board's near end sits
/// under the participant's feet and runs the way they face, so the real floor is the board.
/// Real walk needed: about 0.6 m of deck, then the 4.9 m board.
@MainActor
final class SkyPlank {
    let root = Entity()
    private var built: Entity?
    private var env: RealEnvironment?
    private var wind: AudioPlaybackController?
    private var loading = false

    init() {
        RealKitSetup.register()
        root.name = "sky-plank"
        root.isEnabled = false
    }

    var isShown: Bool { root.isEnabled }

    /// Builds on first use (geometry off the main actor), then places the board start at `rig`.
    func show(at rig: Rig) async {
        place(rig)
        root.isEnabled = true
        guard built == nil, !loading else { startWind(); return }
        loading = true
        defer { loading = false }
        let builder = RooftopPlank()
        let scene = await Task.detached(priority: .userInitiated) { builder.build(seed: 1) }.value
        do {
            var sky = scene.lighting.sky ?? SunSky()
            sky.skyResolution = 2048
            // Sky dome past the far ground's haze so the horizon reads as distance, not a wall.
            let env = try RealEnvironment(sky, skybox: true, skyboxRadius: 2500)
            let city = try await scene.entity()
            city.position = -builder.start
            env.illuminate(city)
            root.addChild(env.root)
            root.addChild(city)
            self.env = env
            built = city
        } catch {
            return
        }
        await RealViewerTracker.shared.start()
        if root.isEnabled { startWind() }
    }

    func hide() {
        root.isEnabled = false
        wind?.stop()
    }

    private func place(_ rig: Rig) {
        root.position = rig.origin
        root.orientation = rig.rotation
    }

    private func startWind() {
        guard let res = Self.windResource() else { return }
        if wind == nil {
            root.components.set(AmbientAudioComponent(gain: -14))
            wind = root.prepareAudio(res)
        }
        wind?.gain = -14
        wind?.play()
    }

    // MARK: - wind

    private static var windCache: AudioFileResource?

    /// 16 s of high-altitude wind: brown noise low-passed around 400 Hz, slow gusts, a faint whistle
    /// band, the last second crossfaded into the first so the loop has no seam.
    static func windResource() -> AudioFileResource? {
        if let r = windCache { return r }
        let rate = 44_100.0, seconds = 16.0, fade = Int(rate)
        let n = Int(rate * seconds) + fade
        var rng = SpatialAge.SeededRNG(seed: 911)
        var out = [Double](repeating: 0, count: n)
        var brown = 0.0, lp = 0.0, bp1 = 0.0, bp2 = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            let white = Double(rng.next() >> 11) / Double(1 << 53) * 2 - 1
            brown = (brown + 0.02 * white) * 0.998
            lp += 0.055 * (brown - lp)
            // Whistle: white through two cascaded one-poles, differenced (a soft band near 1.2 kHz).
            bp1 += 0.16 * (white - bp1)
            bp2 += 0.16 * (bp1 - bp2)
            let whistle = (bp1 - bp2)
            let gust = 0.55 + 0.3 * sin(2 * .pi * t / 16 * 3) + 0.15 * sin(2 * .pi * t / 16 * 7 + 1.3)
            out[i] = (lp * 9 + whistle * 0.18 * gust * gust) * gust
        }
        let loopN = n - fade
        for k in 0..<fade {
            let a = Double(k) / Double(fade)
            out[k] = out[k] * a + out[loopN + k] * (1 - a)
        }
        let peak = out[0..<loopN].map(abs).max() ?? 1
        var pcm = Data(capacity: loopN * 2)
        for i in 0..<loopN {
            var v = Int16(max(-1, min(1, out[i] / peak * 0.85)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        h.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        h.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        h.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        let url = FileManager.default.temporaryDirectory.appending(path: "sky-plank-wind.wav")
        do {
            try (h + pcm).write(to: url)
            let r = try AudioFileResource.load(contentsOf: url, configuration: .init(shouldLoop: true))
            windCache = r
            return r
        } catch {
            return nil
        }
    }
}
