import simd

/// Front view of a standing person whose hands sit at two given points, as convex pieces in the wall plane
/// (x right, y up from the floor, meters). The union of the pieces is the figure. Hole in the Wall cuts it.
///
/// Segment lengths are fractions of stature H = eye / 0.936 (Drillis and Contini). Each arm is solved as two
/// bones from the shoulder to the hand. A hand nearer the shoulder than the arm's length means the arm also
/// reaches toward the viewer, so both bones are drawn foreshortened by the same factor with a slight elbow
/// bend. A strongly foreshortened arm shows an open palm, fingers up.
struct BodySilhouette {
    /// Convex outlines, counterclockwise seen from +z.
    private(set) var pieces: [[SIMD2<Float>]] = []

    /// - Parameters:
    ///   - eye: eye height above the floor.
    ///   - shoulderY: shoulder joint height, the estimate the hand targets use.
    ///   - left, right: hand centers.
    ///   - inflate: grows every piece by this margin, for an outline drawn behind the figure.
    init(eye: Float, shoulderY sh: Float, left: SIMD2<Float>, right: SIMD2<Float>, inflate g: Float = 0) {
        let h = eye / 0.936
        // Offsets measured on a 1.7 m adult, scaled to this one.
        let s = h / 1.7

        // Head, a little taller than wide, centered just above the eyes.
        pieces.append(Self.ellipse([0, 0.936 * h], rx: 0.047 * h + g, ry: 0.066 * h + g))
        // Neck and trunk as stacked symmetric rows, top to bottom: (height, half width).
        let rows: [(Float, Float)] = [
            (0.885 * h, 0.032 * h),
            (sh + 0.075 * s, 0.036 * h),
            (sh + 0.045 * s, 0.080 * h),
            (sh + 0.012 * s, 0.118 * h),
            (sh - 0.060 * s, 0.124 * h),
            (sh - 0.150 * s, 0.104 * h),
            (0.640 * h, 0.086 * h),
            (0.575 * h, 0.098 * h),
            (0.510 * h, 0.102 * h),
            (0.460 * h, 0.060 * h),
        ]
        for (a, b) in zip(rows, rows.dropFirst()) {
            let top = a.0 + (a.0 == rows[0].0 ? g : 0), bottom = b.0 - (b.0 == rows.last!.0 ? g : 0)
            pieces.append([[-b.1 - g, bottom], [b.1 + g, bottom], [a.1 + g, top], [-a.1 - g, top]])
        }

        // Legs: thigh, shin, and the front of the foot turned slightly out.
        for side: Float in [-1, 1] {
            let hip = SIMD2<Float>(side * 0.052 * h, 0.505 * h)
            let knee = SIMD2<Float>(side * 0.056 * h, 0.285 * h)
            let ankle = SIMD2<Float>(side * 0.062 * h, 0.040 * h)
            pieces.append(Self.capsule(hip, knee, 0.056 * h + g, 0.035 * h + g))
            pieces.append(Self.capsule(knee, [side * 0.060 * h, 0.17 * h], 0.034 * h + g, 0.033 * h + g))
            pieces.append(Self.capsule([side * 0.060 * h, 0.17 * h], ankle, 0.033 * h + g, 0.021 * h + g))
            pieces.append(Self.capsule(ankle, [side * 0.080 * h, 0.012 * h], 0.022 * h + g, 0.017 * h + g))
        }

        for (side, hand) in [(Float(-1), left), (Float(1), right)] {
            arm(shoulder: [side * 0.112 * h, sh], hand: hand, side: side, h: h, g: g)
        }
    }

    /// Upper arm, forearm and hand from the shoulder joint to the hand center.
    private mutating func arm(shoulder: SIMD2<Float>, hand: SIMD2<Float>, side: Float, h: Float, g: Float) {
        let upper = 0.186 * h, fore = 0.146 * h, palmOffset = 0.050 * h
        let reach = upper + fore + palmOffset
        let d = simd_distance(shoulder, hand)
        // Foreshortening: the part of the arm that points at the viewer is lost in a front view.
        let k = min(1, d / (0.94 * reach))
        let l1 = upper * k, l2 = (fore + palmOffset) * k
        let elbow = Self.elbow(shoulder, hand, l1, l2, side: side)
        let dir = simd_length(hand - elbow) > 1e-4 ? simd_normalize(hand - elbow) : SIMD2<Float>(0, 1)
        // The hand is centered on its target point, so the forearm ends where the palm begins.
        let palmFacing = k < 0.45
        let u = palmFacing ? simd_normalize(SIMD2<Float>(side * 0.15, 1)) : dir
        let base = hand - u * 0.048 * h

        // Deltoid cap, upper arm, forearm.
        pieces.append(Self.ellipse(shoulder + [side * 0.006 * h, -0.004 * h], rx: 0.034 * h + g, ry: 0.034 * h + g))
        pieces.append(Self.capsule(shoulder, elbow, 0.030 * h + g, 0.025 * h + g))
        pieces.append(Self.capsule(elbow, palmFacing ? hand : base, 0.025 * h + g, 0.019 * h + g))

        // Palm and fingers along the forearm, or an open palm facing the viewer when the arm points at it.
        pieces.append(Self.capsule(base, base + u * 0.055 * h, 0.021 * h + g, 0.026 * h + g))
        pieces.append(Self.capsule(base + u * 0.055 * h, base + u * 0.096 * h, 0.023 * h + g, 0.016 * h + g))
        // Thumb, on the side of the hand toward the body's midline when the palm faces the viewer.
        let across = SIMD2<Float>(-u.y, u.x) * (palmFacing ? -side : side)
        let thumbRoot = base + u * 0.018 * h + across * 0.016 * h
        pieces.append(Self.capsule(thumbRoot, thumbRoot + simd_normalize(u + across * 1.2) * 0.036 * h,
                                   0.010 * h + g, 0.008 * h + g))
    }

    /// Elbow of a two-bone chain. Of the two bends, takes the one that drops the elbow and keeps it outboard.
    private static func elbow(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ l1: Float, _ l2: Float, side: Float) -> SIMD2<Float> {
        let d = simd_distance(a, b)
        guard d > 1e-4 else { return a + [0, -l1] }
        let u = (b - a) / d
        let dc = min(d, (l1 + l2) * 0.9999)
        let x = (l1 * l1 - l2 * l2 + dc * dc) / (2 * dc)
        let y = sqrt(max(l1 * l1 - x * x, 0))
        let n = SIMD2<Float>(-u.y, u.x)
        let c1 = a + u * x + n * y, c2 = a + u * x - n * y
        let prefer = simd_normalize(SIMD2<Float>(side, -1))
        return simd_dot(c1 - a, prefer) >= simd_dot(c2 - a, prefer) ? c1 : c2
    }

    static func ellipse(_ c: SIMD2<Float>, rx: Float, ry: Float, segments: Int = 28) -> [SIMD2<Float>] {
        (0..<segments).map { i in
            let a = Float(i) / Float(segments) * 2 * .pi
            return c + [cos(a) * rx, sin(a) * ry]
        }
    }

    /// Convex hull of two circles: a limb segment that tapers from radius `ra` at `a` to `rb` at `b`.
    static func capsule(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ ra: Float, _ rb: Float) -> [SIMD2<Float>] {
        hull(ellipse(a, rx: ra, ry: ra, segments: 20) + ellipse(b, rx: rb, ry: rb, segments: 20))
    }

    /// Andrew's monotone chain, counterclockwise.
    static func hull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let p = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count > 2 else { return p }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = [], upper: [SIMD2<Float>] = []
        for q in p {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
