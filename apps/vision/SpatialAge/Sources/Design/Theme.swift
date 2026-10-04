import RealityKit
import SwiftUI
import UIKit

/// Design tokens. Spec: specs/games/design.md.
/// Color carries meaning and nothing else: blue = touch, orange = leave, gold = caught, teal = follow.
enum Theme {
    static let ink = UIColor(red: 0.043, green: 0.059, blue: 0.090, alpha: 1)       // #0B0F17 sky
    static let inkLift = UIColor(red: 0.106, green: 0.141, blue: 0.188, alpha: 1)   // #1B2430 horizon, floor
    static let paper = UIColor(red: 0.965, green: 0.957, blue: 0.937, alpha: 1)     // #F6F4EF
    static let grid = UIColor(red: 0.851, green: 0.831, blue: 0.780, alpha: 1)      // #D9D4C7
    static let mute = UIColor(red: 0.541, green: 0.561, blue: 0.600, alpha: 1)      // #8A8F99
    static let go = UIColor(red: 0.184, green: 0.420, blue: 1.000, alpha: 1)        // #2F6BFF
    static let nogo = UIColor(red: 1.000, green: 0.478, blue: 0.239, alpha: 1)      // #FF7A3D
    static let gold = UIColor(red: 1.000, green: 0.784, blue: 0.239, alpha: 1)      // #FFC83D
    static let teal = UIColor(red: 0.078, green: 0.722, blue: 0.651, alpha: 1)      // #14B8A6

    static func color(_ c: UIColor) -> Color { Color(uiColor: c) }

    /// Sizes in meters. Life scale: everything sits where an arm can reach it.
    enum Size {
        static let target: Float = 0.06
        static let star: Float = 0.04
        static let orb: Float = 0.04
        static let bob: Float = 0.04
        static let floorRadius: Float = 6
        static let skyRadius: Float = 40
    }

    /// Micro-interaction timing, seconds. Five primitives, used everywhere.
    enum Motion {
        /// Breathe: live targets pulse so the eye knows they are touchable.
        static let breatheHz = 0.5
        static let breatheDepth: Float = 0.03
        /// Proximity glow starts at this fingertip distance.
        static let glowRange: Float = 0.30
        /// Contact pop and its ring.
        static let pop = 0.09
        static let ring = 0.24
        static let ringScale: Float = 3
        /// Miss sink.
        static let sink = 0.25
        static let sinkDepth: Float = 0.03
        /// Release snap of the pendulum cord.
        static let snap = 0.12
        /// Appearance. Short enough to keep spawn time exact to one frame.
        static let appear = 0.06
    }
}

/// Dusk theme. Spec: Dusk design spec v1.0. Signal colors (go, nogo, gold, teal) are unchanged.
enum Dusk {
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
    // UI
    static let bg = hex(0x1B191A), surface = hex(0x262324), surface2 = hex(0x2F2B2C)
    static let fg = hex(0xF7E9DA), mute = hex(0xA89698), warn = hex(0xFF9A62)
    static let accent = hex(0xFBDAB4), accentStrong = hex(0xD8AB8B), onAccent = hex(0x252322)
    static let accentSoft = hex(0xD8AB8B, 0.20), accentGlow = hex(0xFBDAB4, 0.45)
    // Glass
    static let glass = hex(0x252322, 0.52), glassStrong = hex(0x252322, 0.80)
    static let glassEdge = hex(0xFBDAB4, 0.22), glassInk = hex(0xFBEADA)
    static let chip = hex(0xFBDAB4, 0.09), chipStrong = hex(0xFBDAB4, 0.20)
    // Environment
    static let skyTop = hex(0x3A3240), skyHorizon = hex(0xFBD3A6), sun = hex(0xFFE6C4)
    static let cloud = hex(0xE9B9A0), mountainFar = hex(0xA39193), mountainNear = hex(0x6F6470)
    static let hill = hex(0x4E4B51), lake = hex(0xD8AB8B), tree = hex(0x3A363C)
    static let treeDark = hex(0x252322), grass = hex(0x2D2A2C), haze = hex(0xD8AB8B, 0.18)
    // Results scoreboard grades. Not in spec v1.0: derived from the Dusk palette, muted to sit next to peach,
    // and kept clear of nogo #FF7A3D and gold #FFC83D so they never read as game signals. 2D windows only.
    static let gradeGood = hex(0xA9C79B), gradeMid = hex(0xEEC97E), gradeLow = hex(0xE88A7D)

    static func color(_ c: UIColor) -> Color { Color(uiColor: c) }
}

/// Material helpers. Lit PBR for objects, unlit for light sources and environment.
enum Look {
    static func glow(_ color: UIColor, intensity: Float = 0.6) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = 0.35
        m.metallic = 0.0
        m.emissiveColor = .init(color: color)
        m.emissiveIntensity = intensity
        return m
    }

    static func metal(_ color: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = 0.22
        m.metallic = 1.0
        return m
    }

    static func flat(_ color: UIColor) -> UnlitMaterial { UnlitMaterial(color: color) }
}
