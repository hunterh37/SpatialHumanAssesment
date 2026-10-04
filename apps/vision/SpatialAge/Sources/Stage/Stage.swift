import RealityKit
import simd
import UIKit

/// The fully immersive environment: a Dusk sunset valley at life scale (Dusk spec section 3).
/// Back to front: gradient sky, low sun and halo, clouds, far mountains and haze, near mountains, hills,
/// lake, two-tone tree silhouettes, grass around the participant. World-locked meshes, so it moves in true
/// parallax. Clouds drift slowly between blocks; `setAmbient(false)` freezes them while trials run, so every
/// motion in view during play is a game signal. Nothing bright or moving sits inside arm's reach.
@MainActor
enum Stage {
    static func make() -> Entity {
        let root = Entity()
        root.name = "stage"
        let R = Theme.Size.skyRadius

        // Sky: vertical gradient from skyTop to skyHorizon, as thin latitude bands of solid color
        // (no texture sampling, so it renders the same on every device).
        addSky(to: root, radius: R)

        // Sun and halo: low, off to the right of the default facing, never behind the targets ahead.
        let sunDir = direction(azimuthDeg: 100, elevationDeg: 5)
        let sun = ModelEntity(mesh: .generateSphere(radius: 1.1), materials: [Look.flat(Dusk.sun)])
        sun.position = sunDir * (R * 0.92)
        root.addChild(sun)
        for (r, a) in [(Float(2.4), Float(0.30)), (4.2, 0.14)] {
            if let disc = Meshes.ellipse(width: 2 * r, height: 2 * r) {
                let halo = ModelEntity(mesh: disc, materials: [Look.veil(Dusk.sun, opacity: a)])
                halo.position = sunDir * (R * 0.93)
                face(halo)
                root.addChild(halo)
            }
        }

        // Clouds: soft flat ellipses, 45% opacity. Grouped so they can drift as one.
        let clouds = Entity()
        clouds.name = cloudsName
        var rng = SeededRNG(seed: 1937)
        for i in 0..<9 {
            let az = Float(i) / 9 * 360 + Float.random(in: -14...14, using: &rng)
            let el = Float.random(in: 11...26, using: &rng)
            let w = Float.random(in: 6...11, using: &rng)
            guard let disc = Meshes.ellipse(width: w, height: w * Float.random(in: 0.14...0.22, using: &rng)) else { continue }
            let c = ModelEntity(mesh: disc, materials: [Look.veil(Dusk.cloud, opacity: 0.45)])
            c.position = direction(azimuthDeg: az, elevationDeg: el) * (R * 0.85)
            face(c)
            clouds.addChild(c)
        }
        root.addChild(clouds)

        // Mountains and hills: three ridges, far to near, each a seeded silhouette.
        addRidge(to: root, radius: R * 0.82, color: Dusk.mountainFar, seed: 11, low: 4, high: 9)
        if let band = Meshes.ridge(radius: R * 0.80, base: -0.4, top: { _ in 2.8 }) {
            root.addChild(ModelEntity(mesh: band, materials: [Look.veil(Dusk.lake, opacity: 0.18)]))
        }
        addRidge(to: root, radius: R * 0.66, color: Dusk.mountainNear, seed: 23, low: 2.2, high: 5.5)
        addRidge(to: root, radius: R * 0.50, color: Dusk.hill, seed: 37, low: 0.6, high: 2.2)

        // Lake, with a few faint light ripples on the sun side.
        let lake = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: R * 0.50), materials: [Look.flat(Dusk.lake)])
        lake.position.y = -0.004
        root.addChild(lake)
        for k in 0..<4 {
            let d = 9.5 + Float(k) * 1.8
            let ripple = ModelEntity(mesh: .generateBox(width: 0.02, height: 0.001, depth: 2.4 - Float(k) * 0.4),
                                     materials: [Look.veil(Dusk.sun, opacity: 0.35)])
            let a = (100 + Float(k % 2 == 0 ? -3 : 3)) * .pi / 180
            ripple.position = [sin(a) * d, -0.002, -cos(a) * d]
            ripple.orientation = simd_quatf(angle: -a + .pi / 2, axis: [0, 1, 0])
            root.addChild(ripple)
        }

        // Grass island around the participant.
        let grass = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: grassRadius), materials: [Look.flat(Dusk.grass)])
        root.addChild(grass)

        // Trees: two-tone silhouettes on the island edge and along the far shore.
        var trng = SeededRNG(seed: 4021)
        for i in 0..<12 {
            let a = (Float(i) + Float.random(in: -0.35...0.35, using: &trng)) / 12 * 2 * .pi
            let r = Float.random(in: 6.2...7.2, using: &trng)
            root.addChild(tree(height: Float.random(in: 2.6...3.8, using: &trng), dark: i % 2 == 1, at: [sin(a) * r, 0, -cos(a) * r]))
        }
        for i in 0..<30 {
            let a = (Float(i) + Float.random(in: -0.4...0.4, using: &trng)) / 30 * 2 * .pi
            let r = Float.random(in: R * 0.47...R * 0.52, using: &trng)
            root.addChild(tree(height: Float.random(in: 3.5...6, using: &trng), dark: i % 3 != 0, at: [sin(a) * r, 0, -cos(a) * r]))
        }
        return root
    }

    /// Grass radius, meters. Trees stand outside the 0.9 m play volume and outside 5 m.
    static let grassRadius: Float = 7.5
    static let cloudsName = "dusk-clouds"
    /// Cloud drift, radians per second (one lap in about 50 minutes).
    static let drift: Float = 0.002

    /// Advances the cloud drift. Call every frame; pass `ambient = false` while trials run.
    static func tick(_ stage: Entity, dt: Double, ambient: Bool) {
        guard ambient, !UIAccessibility.isReduceMotionEnabled,
              let clouds = stage.findEntity(named: cloudsName) else { return }
        clouds.orientation = simd_quatf(angle: drift * Float(dt), axis: [0, 1, 0]) * clouds.orientation
    }

    /// Two-tone conifer silhouette standing on the floor at `p`.
    static func tree(height: Float, dark: Bool, at p: SIMD3<Float>) -> Entity {
        let t = Entity()
        t.position = p
        let color = dark ? Dusk.treeDark : Dusk.tree
        let trunk = ModelEntity(mesh: .generateCylinder(height: height * 0.18, radius: height * 0.03),
                                materials: [Look.flat(Dusk.treeDark)])
        trunk.position.y = height * 0.09
        t.addChild(trunk)
        for (k, f) in [Float(0.0), 0.28, 0.52].enumerated() {
            let h = height * (0.5 - Float(k) * 0.08)
            let cone = ModelEntity(mesh: .generateCone(height: h, radius: height * (0.22 - Float(k) * 0.045)),
                                   materials: [Look.flat(color)])
            cone.position.y = height * 0.15 + height * f + h / 2
            t.addChild(cone)
        }
        return t
    }

    private static func addRidge(to root: Entity, radius: Float, color: UIColor, seed: Int, low: Float, high: Float) {
        var rng = SeededRNG(seed: seed)
        // Sum of a few sines with seeded phases: smooth, irregular peaks that close on themselves.
        let waves: [(k: Float, a: Float, p: Float)] = [(2, 1, 0), (3, 0.6, 0), (5, 0.35, 0), (9, 0.18, 0), (17, 0.08, 0)]
            .map { ($0.0, $0.1, Float.random(in: 0...(2 * .pi), using: &rng)) }
        let total = waves.reduce(0) { $0 + $1.a }
        let mesh = Meshes.ridge(radius: radius) { theta in
            let v = waves.reduce(0) { $0 + $1.a * sin($1.k * theta + $1.p) } / total
            return low + (high - low) * (v * 0.5 + 0.5)
        }
        if let mesh { root.addChild(ModelEntity(mesh: mesh, materials: [Look.flat(color)])) }
    }

    /// Unit vector for an azimuth (0 = -Z, positive to the right) and elevation, degrees.
    static func direction(azimuthDeg: Float, elevationDeg: Float) -> SIMD3<Float> {
        let az = azimuthDeg * .pi / 180, el = elevationDeg * .pi / 180
        return [sin(az) * cos(el), sin(el), -cos(az) * cos(el)]
    }

    /// Turns a flat +Z-facing mesh toward the origin.
    private static func face(_ e: Entity) {
        e.look(at: e.position * 2, from: e.position, relativeTo: nil)
    }

    /// Bands from 12 degrees below the horizon to the zenith. Warmth gathers low: the horizon color fades
    /// into skyTop with a 2.2 power curve, so the upper sky stays dusky.
    private static func addSky(to root: Entity, radius: Float) {
        var top: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), hor = top
        Dusk.skyTop.getRed(&top.0, green: &top.1, blue: &top.2, alpha: &top.3)
        Dusk.skyHorizon.getRed(&hor.0, green: &hor.1, blue: &hor.2, alpha: &hor.3)
        let bands = 150
        var edges: [Float] = [-12]
        for i in 0...bands { edges.append(90 * Float(i) / Float(bands)) }
        for k in 0..<(edges.count - 1) {
            let lo = edges[k], hi = edges[k + 1]
            let mid = max(0, (lo + hi) / 2)
            let w = CGFloat(pow(1 - Double(mid / 90), 2.2))
            let c = UIColor(red: top.0 + (hor.0 - top.0) * w, green: top.1 + (hor.1 - top.1) * w,
                            blue: top.2 + (hor.2 - top.2) * w, alpha: 1)
            if let mesh = Meshes.skyBand(radius: radius, from: lo, to: hi) {
                root.addChild(ModelEntity(mesh: mesh, materials: [Look.flat(c)]))
            }
        }
    }
}

/// A frame at the participant: origin under the head, -Z is where they faced when the game began.
struct Rig {
    var origin: SIMD3<Float>
    var yaw: Float

    init(head: simd_float4x4) {
        let p = head.columns.3
        let f = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        origin = [p.x, 0, p.z]
        yaw = simd_length(f) > 1e-3 ? atan2(-f.x, -f.z) : 0
        eye = p.y
    }

    var eye: Float

    /// Local (x right, y up, z forward negative) to world.
    func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
        origin + simd_quatf(angle: yaw, axis: [0, 1, 0]).act(local)
    }

    var rotation: simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }
}
