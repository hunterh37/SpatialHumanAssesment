import Foundation

/// 3D vector in meters. Encodes as `[x, y, z]`.
public struct V3: Codable, Sendable, Equatable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = V3(0, 0, 0)

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self); y = try c.decode(Double.self); z = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(Self.round(x)); try c.encode(Self.round(y)); try c.encode(Self.round(z))
    }

    /// Millimeter precision on disk. Hand tracking noise is larger.
    private static func round(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }

    public static func + (a: V3, b: V3) -> V3 { V3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: V3, b: V3) -> V3 { V3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: V3, s: Double) -> V3 { V3(a.x * s, a.y * s, a.z * s) }
    public static func / (a: V3, s: Double) -> V3 { V3(a.x / s, a.y / s, a.z / s) }
    public func dot(_ b: V3) -> Double { x * b.x + y * b.y + z * b.z }
    public var length: Double { dot(self).squareRoot() }
    public func distance(to b: V3) -> Double { (self - b).length }
}
