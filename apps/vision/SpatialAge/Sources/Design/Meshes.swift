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
}
