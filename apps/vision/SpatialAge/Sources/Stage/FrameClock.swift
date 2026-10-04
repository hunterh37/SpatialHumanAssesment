import Foundation
import QuartzCore

/// Drives game logic from RealityKit's render loop. Games `await next()` once per frame,
/// so every check (contact, catch, pursuit sample) runs at display rate with no timers.
@MainActor
final class FrameClock {
    private var waiters: [CheckedContinuation<Double, Never>] = []
    private var tweens: [Tween] = []
    private(set) var elapsed: Double = 0

    struct Tween {
        var duration: Double
        var t: Double = 0
        var step: (Double) -> Void
        var done: (() -> Void)?
    }

    /// Called from `SceneEvents.Update`.
    func tick(_ dt: Double) {
        elapsed += dt
        let current = tweens
        tweens = []
        var alive: [Tween] = []
        for var tw in current {
            tw.t += dt
            let p = min(tw.t / tw.duration, 1)
            tw.step(p)
            if p < 1 { alive.append(tw) } else { tw.done?() }
        }
        // `done` handlers may have started new tweens; keep them.
        tweens = alive + tweens
        let w = waiters
        waiters = []
        w.forEach { $0.resume(returning: dt) }
    }

    func next() async -> Double {
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Frame-accurate wait. Returns early if the task is cancelled.
    func wait(_ seconds: Double) async {
        var t = 0.0
        while t < seconds && !Task.isCancelled { t += await next() }
    }

    /// Runs `step(p)` with p from 0 to 1 over `duration` seconds, eased by the caller.
    func animate(_ duration: Double, _ step: @escaping (Double) -> Void, done: (() -> Void)? = nil) {
        tweens.append(Tween(duration: max(duration, 1e-3), step: step, done: done))
    }
}

enum Ease {
    static func out(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    static func inOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    /// Overshoots to about 1.1 then settles. For pops.
    static func back(_ p: Double) -> Double {
        let c = 1.70158, c3 = c + 1
        return 1 + c3 * pow(p - 1, 3) + c * pow(p - 1, 2)
    }
}
