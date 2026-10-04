import CoreGraphics
import Foundation
import RealityKit
import simd
import UIKit

/// Alex's Dusk Meadow (packages/DuskEnvironment, see its README): everything past 60 m is one baked panorama
/// on a 1 km inverted sphere; the near field (heightmap ground, trees, shrubs, rocks, grass) is real 3D.
/// Every material is unlit and the stage adds no lights, so game signal colors render unchanged (Dusk spec 3-4).
/// Shading is baked instead: each prop vertex carries its shade in uv.x and samples a 256-texel ramp, one ramp
/// row per instance tint. The export is static, so nothing here moves.
enum DuskMeadow {
    /// UserDefaults kill switch. Absent means on; false keeps the procedural valley only.
    static let defaultsKey = "stage.meadow"
    static var isOn: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    /// Bundle subdirectory (folder reference in project.yml).
    static let folder = "DuskMeadow"
    /// Far-field sphere radius, meters, centered on the immersive origin.
    static let skyRadius: Float = 1000
    /// Play volume: no instance within this horizontal distance of the origin, meters.
    static let clearRadius: Float = 1.0
    /// Total triangle budget for the whole Meadow. Grass gets what the rest leaves, nearest cards first.
    static let triangleBudget = 500_000
    /// Albedo alpha is 1 inside this radius and fades to 0 at the heightmap edge, meters.
    static let fadeStart: Float = 48
    /// Angular sectors per merged mesh group, so the renderer can cull what is behind the player.
    static let sectors = 6
    static let edgeSectors = 8
    static let grassBuckets = 4
    static let rampWidth = 256
    /// Baked light on props: ambient floor plus a soft term toward the sun.
    static let ambient: Float = 0.72

    enum MeadowError: Error {
        case missing(String)
        case malformed(String)
    }

    /// Builds the whole Meadow, or throws. Files are parsed off the main actor; RealityKit resources are made here.
    @MainActor
    static func load() async throws -> Entity {
        guard let dir = Bundle.main.url(forResource: folder, withExtension: nil) else { throw MeadowError.missing(folder) }
        let b = try await Task.detached(priority: .userInitiated) { try bake(dir: dir) }.value

        let color = TextureResource.CreateOptions(semantic: .color)
        let pano = try await TextureResource(contentsOf: b.panorama, options: color)
        let albedo = try await TextureResource(contentsOf: b.albedo, options: color)
        let card = try await TextureResource(contentsOf: b.grassCard, options: color)

        let root = Entity()
        root.name = "dusk-meadow"
        root.addChild(try await model("meadow-sky", b.sky, unlit(pano)))
        root.addChild(try await model("meadow-ground", b.groundInner, unlit(albedo)))
        // The edge fades into the panorama; split by sector so each piece sorts as far away as it is.
        var fade = unlit(albedo)
        fade.blending = .transparent(opacity: .init(floatLiteral: 1))
        for (i, part) in b.groundEdge.enumerated() where part.triangles > 0 {
            root.addChild(try await model("meadow-ground-edge-\(i)", part, fade))
        }
        if b.rampRows > 0, let image = rampImage(b.ramp, rows: b.rampRows) {
            // No mipmaps: each row is one instance tint, and mip levels would blend neighbouring rows.
            let ramp = try await TextureResource(image: image, withName: nil, options: .init(semantic: .color, mipmapsMode: .none))
            let props = unlit(ramp)
            for (i, part) in b.props.enumerated() where part.triangles > 0 {
                root.addChild(try await model("meadow-props-\(i)", part, props))
            }
        }
        for (i, g) in b.grass.enumerated() where g.part.triangles > 0 {
            var m = unlit(card, tint: b.grassTints[g.bucket])
            m.opacityThreshold = 0.42
            root.addChild(try await model("meadow-grass-\(i)", g.part, m))
        }
        print("Stage: Dusk Meadow ready, \(b.triangles) triangles, \(root.children.count) meshes, \(b.skipped) instances inside the play volume skipped, \(b.grassDropped) grass cards over budget")
        return root
    }

    // MARK: - RealityKit (main actor)

    @MainActor
    private static func unlit(_ texture: TextureResource, tint: SIMD3<Float>? = nil) -> UnlitMaterial {
        // The panorama is already tone mapped and the near field is matched to it, so skip RealityKit's tone map.
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        let c = tint.map { UIColor(red: CGFloat(srgb($0.x)), green: CGFloat(srgb($0.y)), blue: CGFloat(srgb($0.z)), alpha: 1) }
        m.color = .init(tint: c ?? .white, texture: .init(texture))
        m.faceCulling = .none
        return m
    }

    @MainActor
    private static func model(_ name: String, _ part: Part, _ material: UnlitMaterial) async throws -> ModelEntity {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffer(part.positions)
        d.textureCoordinates = MeshBuffer(part.uvs)
        d.primitives = .triangles(part.indices)
        let e = ModelEntity(mesh: try await MeshResource(from: [d]), materials: [material])
        e.name = name
        return e
    }

    /// RGBA8 ramp rows as an sRGB image (rows x 256).
    private static func rampImage(_ rgba: [UInt8], rows: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: rampWidth, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rampWidth * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Parsing and meshing (off the main actor)

    /// CPU mesh: positions, uvs, triangle indices.
    struct Part: Sendable {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var triangles: Int { indices.count / 3 }

        /// Appends one placed instance of `shape` from the record at float offset `o` (position, quaternion,
        /// scale). `uv` gets the vertex index and its world normal.
        fileprivate mutating func place(_ shape: Shape, _ inst: [Float], at o: Int, uv: (Int, SIMD3<Float>) -> SIMD2<Float>) {
            let p = SIMD3<Float>(inst[o], inst[o + 1], inst[o + 2])
            let q = simd_quatf(ix: inst[o + 3], iy: inst[o + 4], iz: inst[o + 5], r: inst[o + 6])
            let s = SIMD3<Float>(inst[o + 7], inst[o + 8], inst[o + 9])
            let base = UInt32(positions.count)
            for i in shape.positions.indices {
                positions.append(p + q.act(shape.positions[i] * s))
                let n = q.act(shape.normals[i] / s)   // inverse transpose for non-uniform scale
                let len = simd_length(n)
                uvs.append(uv(i, len > 1e-6 ? n / len : [0, 1, 0]))
            }
            indices += shape.indices.map { $0 + base }
        }
    }

    struct GrassPart: Sendable {
        var bucket: Int
        var part: Part
    }

    /// Everything the main actor needs, parsed and meshed.
    struct Baked: Sendable {
        var panorama: URL, albedo: URL, grassCard: URL
        var sky = Part(), groundInner = Part()
        var groundEdge: [Part] = [], props: [Part] = [], grass: [GrassPart] = []
        var grassTints: [SIMD3<Float>] = []
        var ramp: [UInt8] = [], rampRows = 0
        var triangles = 0, skipped = 0, grassDropped = 0
    }

    struct Manifest: Decodable {
        struct File: Decodable { let file: String }
        struct Heightmap: Decodable { let file: String; let size: [Int]; let xRange: [Float] }
        struct Terrain: Decodable { let heightmap: Heightmap; let albedo: File }
        struct InstanceSet: Decodable { let name: String; let prototype: String; let count: Int; let offsetFloats: Int }
        struct Instances: Decodable { let file: String; let stride: Int; let sets: [InstanceSet] }
        struct Sun: Decodable { let directionToSun: [Float] }
        struct Lighting: Decodable { let sun: Sun }
        let panorama: File, nearTerrain: Terrain, instances: Instances, prototypes: File, grassCard: File, lighting: Lighting
    }

    /// One prototype as exported: flat float arrays, local space, base at y = 0.
    struct Prototype: Decodable {
        let positions: [Float], normals: [Float]?, colors: [Float]?, uvs: [Float]?, indices: [UInt32]
    }

    /// A prototype ready to place: vertex shade as a scalar, and its mean hue folded into a tint factor.
    fileprivate struct Shape {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = []
        var shade: [Float] = [], indices: [UInt32] = []
        var chroma = SIMD3<Float>(repeating: 1)

        init(_ p: Prototype) {
            let n = p.positions.count / 3
            for i in 0..<n {
                positions.append([p.positions[3 * i], p.positions[3 * i + 1], p.positions[3 * i + 2]])
                if let v = p.normals, v.count >= 3 * n { normals.append([v[3 * i], v[3 * i + 1], v[3 * i + 2]]) } else { normals.append([0, 1, 0]) }
                if let t = p.uvs, t.count >= 2 * n { uvs.append([t[2 * i], t[2 * i + 1]]) }
            }
            if let c = p.colors, c.count >= 3 * n, n > 0 {
                var mean = SIMD3<Float>.zero
                for i in 0..<n {
                    let rgb = SIMD3<Float>(c[3 * i], c[3 * i + 1], c[3 * i + 2])
                    shade.append(simd_dot(rgb, luma))
                    mean += rgb
                }
                mean /= Float(n)
                chroma = mean / max(simd_dot(mean, luma), 1e-4)
            } else {
                shade = Array(repeating: 1, count: n)
            }
            indices = p.indices.allSatisfy { Int($0) < n } ? p.indices : []
        }
    }

    private static let luma = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    static func bake(dir: URL) throws -> Baked {
        let url = { (name: String) in dir.appendingPathComponent(name) }
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url("manifest.json")))
        let prototypes = try JSONDecoder().decode([String: Prototype].self, from: Data(contentsOf: url(m.prototypes.file)))
        let hm = m.nearTerrain.heightmap
        let heights = try floats(url(hm.file))
        guard hm.size.count == 2, hm.size[0] == hm.size[1], hm.size[0] > 1, heights.count == hm.size[0] * hm.size[1],
              hm.xRange.count == 2 else { throw MeadowError.malformed(hm.file) }
        let inst = try floats(url(m.instances.file))
        let s = m.lighting.sun.directionToSun
        let sun = s.count == 3 ? simd_normalize(SIMD3<Float>(s[0], s[1], s[2])) : SIMD3<Float>(0, 1, 0)

        var b = Baked(panorama: url(m.panorama.file), albedo: url(m.nearTerrain.albedo.file), grassCard: url(m.grassCard.file))
        b.sky = skyDome(radius: skyRadius)
        (b.groundInner, b.groundEdge) = ground(heights, n: hm.size[0], half: hm.xRange[1])

        // Sort every record into props or grass, skipping anything inside the play volume.
        let stride = m.instances.stride
        guard stride == 13 else { throw MeadowError.malformed(m.instances.file) }
        var shapes: [String: Shape] = [:]
        var props: [(shape: String, at: Int)] = [], grass: [Int] = []
        var grassShape: String?
        for set in m.instances.sets {
            guard let p = prototypes[set.prototype], set.offsetFloats >= 0,
                  set.offsetFloats + set.count * stride <= inst.count else { throw MeadowError.malformed(set.name) }
            if shapes[set.prototype] == nil { shapes[set.prototype] = Shape(p) }
            let isGrass = p.uvs != nil && p.colors != nil && set.prototype.hasPrefix("grass")
            if isGrass { grassShape = set.prototype }
            for k in 0..<set.count {
                let o = set.offsetFloats + k * stride
                if hypot(inst[o], inst[o + 2]) < clearRadius { b.skipped += 1; continue }
                if isGrass { grass.append(o) } else { props.append((set.prototype, o)) }
            }
        }

        // Props: merged per sector; uv = (baked shade, this instance's ramp row).
        b.props = Array(repeating: Part(), count: sectors)
        b.rampRows = props.count
        b.ramp.reserveCapacity(props.count * rampWidth * 4)
        for (row, item) in props.enumerated() {
            guard let shape = shapes[item.shape] else { continue }
            let o = item.at
            let tint = SIMD3<Float>(inst[o + 10], inst[o + 11], inst[o + 12]) * shape.chroma
            for i in 0..<rampWidth {
                let c = tint * ((Float(i) + 0.5) / Float(rampWidth))
                b.ramp += [UInt8(srgb(c.x) * 255 + 0.5), UInt8(srgb(c.y) * 255 + 0.5), UInt8(srgb(c.z) * 255 + 0.5), 255]
            }
            let v = (Float(row) + 0.5) / Float(props.count)
            b.props[sector(inst[o], inst[o + 2], sectors)].place(shape, inst, at: o) { i, n in
                [min(1, shape.shade[i] * (ambient + (1 - ambient) * max(0, simd_dot(n, sun)))), v]
            }
        }

        // Grass: nearest first up to the budget, then luminance-quartile tint buckets, merged per bucket and sector.
        let others = b.sky.triangles + b.groundInner.triangles + b.groundEdge.reduce(0) { $0 + $1.triangles }
            + b.props.reduce(0) { $0 + $1.triangles }
        if let name = grassShape, let shape = shapes[name], !shape.indices.isEmpty, !grass.isEmpty {
            let perCard = shape.indices.count / 3
            let fit = max(0, (triangleBudget - others) / perCard)
            grass.sort { hypot(inst[$0], inst[$0 + 2]) < hypot(inst[$1], inst[$1 + 2]) }
            if grass.count > fit {
                b.grassDropped = grass.count - fit
                grass.removeLast(b.grassDropped)
            }
            let lum = grass.map { simd_dot(SIMD3<Float>(inst[$0 + 10], inst[$0 + 11], inst[$0 + 12]), luma) }
            let ranked = lum.sorted()
            let cuts = ranked.isEmpty ? [] : (1..<grassBuckets).map { ranked[$0 * ranked.count / grassBuckets] }
            var sums = [SIMD3<Float>](repeating: .zero, count: grassBuckets), counts = [Int](repeating: 0, count: grassBuckets)
            var parts = [Part](repeating: Part(), count: grassBuckets * sectors)
            for (k, o) in grass.enumerated() {
                let bucket = cuts.reduce(0) { $0 + (lum[k] >= $1 ? 1 : 0) }
                sums[bucket] += SIMD3<Float>(inst[o + 10], inst[o + 11], inst[o + 12])
                counts[bucket] += 1
                // Card uvs keep their export convention: v = 0 at the blade base, which is the image's bottom row.
                parts[bucket * sectors + sector(inst[o], inst[o + 2], sectors)].place(shape, inst, at: o) { i, _ in
                    i < shape.uvs.count ? shape.uvs[i] : [0, 0]
                }
            }
            b.grassTints = (0..<grassBuckets).map { counts[$0] > 0 ? sums[$0] / Float(counts[$0]) : .zero }
            b.grass = parts.enumerated().map { GrassPart(bucket: $0.offset / sectors, part: $0.element) }
        }
        b.triangles = others + b.grass.reduce(0) { $0 + $1.part.triangles }
        return b
    }

    /// Inverted UV sphere with the manifest's equirect mapping. Seam vertices are duplicated (u = 0 and u = 1
    /// sit behind the player, +Z) and v is flipped: the manifest counts v = 0 at the image's top row, while
    /// RealityKit (USD convention) samples v = 0 at the bottom row, so v = 0.5 + asin(d.y) / pi.
    static func skyDome(radius: Float, segments: Int = 72, rings: Int = 36) -> Part {
        var p = Part()
        for i in 0...rings {
            let lat = Float.pi / 2 - Float.pi * Float(i) / Float(rings)
            for j in 0...segments {
                let u = Float(j) / Float(segments)
                let lon = (u - 0.5) * 2 * .pi
                // atan2(d.x, -d.z) = lon, so u = 0.5 + atan2(d.x, -d.z) / 2pi as in the manifest.
                p.positions.append(SIMD3<Float>(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat)) * radius)
                p.uvs.append([u, 0.5 + lat / .pi])
            }
        }
        let w = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(segments) {
                let a = i * w + j, c = a + w
                if i != 0 { p.indices += [a, a + 1, c] }                          // top fan is degenerate
                if i != UInt32(rings) - 1 { p.indices += [a + 1, c + 1, c] }      // bottom fan is degenerate
            }
        }
        return p
    }

    /// Ground from the heightmap at every other sample (1 m for the 0.5 m export). Cells fully inside the
    /// opaque radius form one opaque mesh; the fading edge is split into sectors; cells past the edge are dropped.
    static func ground(_ h: [Float], n: Int, half: Float) -> (inner: Part, edge: [Part]) {
        let k = (n - 1) % 2 == 0 ? 2 : 1
        let g = (n - 1) / k + 1
        let step = 2 * half / Float(n - 1)
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = []
        for i in 0..<g {
            for j in 0..<g {
                let r = i * k, c = j * k
                let x = -half + Float(c) * step, z = -half + Float(r) * step
                pos.append([x, h[r * n + c], z])
                // Albedo top row is z = -half; flip v for RealityKit.
                uv.append([(x + half) / (2 * half), 1 - (z + half) / (2 * half)])
            }
        }
        var inner = Builder(), edge = [Builder](repeating: Builder(), count: edgeSectors)
        for i in 0..<(g - 1) {
            for j in 0..<(g - 1) {
                let a = UInt32(i * g + j), b = a + 1, c = a + UInt32(g), d = c + 1
                let radii = [a, b, c, d].map { hypot(pos[Int($0)].x, pos[Int($0)].z) }
                guard let lo = radii.min(), let hi = radii.max(), lo < half else { continue }
                let tris: [UInt32] = [a, c, b, b, c, d]
                if hi <= fadeStart {
                    inner.add(tris, pos, uv)
                } else {
                    let m = (pos[Int(a)] + pos[Int(d)]) / 2
                    edge[sector(m.x, m.z, edgeSectors)].add(tris, pos, uv)
                }
            }
        }
        return (inner.part, edge.map(\.part))
    }

    /// Collects triangles from a shared vertex grid into a compact part, so each part's bounds are its own.
    private struct Builder {
        var part = Part()
        var map: [UInt32: UInt32] = [:]

        mutating func add(_ ids: [UInt32], _ pos: [SIMD3<Float>], _ uv: [SIMD2<Float>]) {
            for id in ids {
                if let k = map[id] { part.indices.append(k); continue }
                let k = UInt32(part.positions.count)
                map[id] = k
                part.positions.append(pos[Int(id)])
                part.uvs.append(uv[Int(id)])
                part.indices.append(k)
            }
        }
    }

    /// Sector index for a horizontal position, 0 ..< count, starting behind the player.
    static func sector(_ x: Float, _ z: Float, _ count: Int) -> Int {
        let a = atan2(x, -z) / (2 * .pi) + 0.5
        return min(count - 1, max(0, Int(a * Float(count))))
    }

    static func floats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count % 4 == 0 else { throw MeadowError.malformed(url.lastPathComponent) }
        return data.withUnsafeBytes { raw in
            (0..<data.count / 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    /// Linear to sRGB encoding, clamped to 0...1.
    static func srgb(_ x: Float) -> Float {
        let c = min(max(x, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}
