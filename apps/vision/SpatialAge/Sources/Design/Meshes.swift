import RealityKit
import simd

/// Meshes RealityKit does not generate.
@MainActor
enum Meshes {
    /// Torus in the XY plane, facing +Z, so a BillboardComponent turns it toward the viewer.
    static func ring(radius: Float, thickness: Float, segments: Int = 48, sides: Int = 8) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments) * 2 * .pi
            let center = SIMD3<Float>(cos(u), sin(u), 0) * radius
            for j in 0...sides {
                let v = Float(j) / Float(sides) * 2 * .pi
                let n = SIMD3<Float>(cos(u) * cos(v), sin(u) * cos(v), sin(v))
                positions.append(center + n * thickness)
                normals.append(n)
            }
        }
        let stride = UInt32(sides + 1)
        for i in 0..<UInt32(segments) {
            for j in 0..<UInt32(sides) {
                let a = i * stride + j, b = (i + 1) * stride + j
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        var d = MeshDescriptor(name: "ring")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Unit sphere seen from inside, for the sky dome.
    static func invertedSphere(radius: Float, segments: Int = 48) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        let rings = segments / 2
        for r in 0...rings {
            let phi = Float(r) / Float(rings) * .pi
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                positions.append(n * radius)
                normals.append(-n)
            }
        }
        let stride = UInt32(segments + 1)
        for r in 0..<UInt32(rings) {
            for s in 0..<UInt32(segments) {
                let a = r * stride + s, b = (r + 1) * stride + s
                indices += [a, a + 1, b, a + 1, b + 1, b]
            }
        }
        var d = MeshDescriptor(name: "sky")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Open tube seen from inside, no caps, centered on the origin. Same winding as `invertedSphere`.
    static func innerTube(radius: Float, height: Float, segments: Int = 96) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for y in [height / 2, -height / 2] {
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let n = SIMD3<Float>(cos(theta), 0, sin(theta))
                positions.append(n * radius + [0, y, 0])
                normals.append(-n)
            }
        }
        let stride = UInt32(segments + 1)
        for s in 0..<UInt32(segments) {
            let a = s, b = stride + s
            indices += [a, a + 1, b, a + 1, b + 1, b]
        }
        var d = MeshDescriptor(name: "tube")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Flat leaf in the XY plane, stem at the origin, blade hanging down -Y, both faces drawn.
    static func leaf(length: Float, width: Float, segments: Int = 16) -> MeshResource? {
        var outline: [SIMD3<Float>] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments)
            outline.append([width / 2 * sin(.pi * u) * (1 - 0.35 * u), -length * u, 0])
        }
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for (face, n) in [(0, SIMD3<Float>(0, 0, 1)), (1, SIMD3<Float>(0, 0, -1))] {
            let base = UInt32(positions.count)
            for p in outline { positions.append(p); normals.append(n) }
            for p in outline { positions.append([-p.x, p.y, p.z]); normals.append(n) }
            let k = UInt32(outline.count)
            for i in 0..<UInt32(segments) {
                let r0 = base + i, r1 = base + i + 1, l0 = base + k + i, l1 = base + k + i + 1
                indices += face == 0 ? [l0, r0, r1, l0, r1, l1] : [l0, r1, r0, l0, l1, r1]
            }
        }
        var d = MeshDescriptor(name: "leaf")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Flat annulus on the floor (XZ plane), facing up.
    static func annulus(inner: Float, outer: Float, segments: Int = 96) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for s in 0...segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            let d = SIMD3<Float>(cos(a), 0, sin(a))
            positions += [d * inner, d * outer]
            normals += [[0, 1, 0], [0, 1, 0]]
        }
        for s in 0..<UInt32(segments) {
            let a = 2 * s, b = 2 * s + 1, c = 2 * s + 2, e = 2 * s + 3
            indices += [a, c, b, b, c, e]
        }
        var d = MeshDescriptor(name: "annulus")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Flat convex polygons in the XY plane at depth `z`, facing +Z, as one mesh. Each polygon is
    /// counterclockwise seen from +Z and fanned from its first vertex.
    static func flat(_ polygons: [[SIMD2<Float>]], z: Float = 0) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        for poly in polygons where poly.count >= 3 {
            let base = UInt32(positions.count)
            positions += poly.map { [$0.x, $0.y, z] }
            for k in 1..<UInt32(poly.count - 1) { indices += [base, base + k, base + k + 1] }
        }
        guard !indices.isEmpty else { return nil }
        var d = MeshDescriptor(name: "flat")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(Array(repeating: SIMD3<Float>(0, 0, 1), count: positions.count))
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Latitude band of a sphere seen from inside, between two elevations in degrees.
    static func skyBand(radius: Float, from lo: Float, to hi: Float, segments: Int = 96) -> MeshResource? {
        let a = lo * .pi / 180, b = hi * .pi / 180
        return ridgeBetween(radius: radius, segments: segments,
                            bottom: (radius * cos(a), radius * sin(a)), top: (radius * cos(b), radius * sin(b)))
    }

    private static func ridgeBetween(radius: Float, segments: Int, bottom: (r: Float, y: Float), top: (r: Float, y: Float)) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for s in 0...segments {
            let theta = Float(s) / Float(segments) * 2 * .pi
            let n = SIMD3<Float>(cos(theta), 0, sin(theta))
            positions += [n * top.r + [0, top.y, 0], n * bottom.r + [0, bottom.y, 0]]
            normals += [-n, -n]
        }
        for s in 0..<UInt32(segments) {
            let a = 2 * s, b = 2 * s + 1, c = 2 * s + 2, e = 2 * s + 3
            // Both faces: seen from inside and outside alike.
            indices += [a, c, b, c, e, b, a, b, c, c, b, e]
        }
        var d = MeshDescriptor(name: "band")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Mountain ridge: a vertical band around the origin at `radius`, seen from inside, from `base` up to a
    /// height profile `top(theta)`. Theta runs from 0 to 2 pi around +X toward +Z.
    static func ridge(radius: Float, base: Float = -1, segments: Int = 180, top: (Float) -> Float) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for s in 0...segments {
            let theta = Float(s) / Float(segments) * 2 * .pi
            let n = SIMD3<Float>(cos(theta), 0, sin(theta))
            positions += [n * radius + [0, top(theta), 0], n * radius + [0, base, 0]]
            normals += [-n, -n]
        }
        for s in 0..<UInt32(segments) {
            let a = 2 * s, b = 2 * s + 1, c = 2 * s + 2, e = 2 * s + 3
            // Both faces: seen from inside and outside alike.
            indices += [a, c, b, c, e, b, a, b, c, c, b, e]
        }
        var d = MeshDescriptor(name: "ridge")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// Flat ellipse in the XY plane, facing +Z.
    static func ellipse(width: Float, height: Float, segments: Int = 40) -> MeshResource? {
        let poly = (0..<segments).map { i -> SIMD2<Float> in
            let a = Float(i) / Float(segments) * 2 * .pi
            return [cos(a) * width / 2, sin(a) * height / 2]
        }
        return flat([poly])
    }
}
