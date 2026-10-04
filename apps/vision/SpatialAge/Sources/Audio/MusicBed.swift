import AVFoundation
import Foundation
import Observation

/// Calm music bed for menus and results (Dusk spec section 8, working title "Golden Hour").
/// Plays every bundled audio file named `music-*`, shuffled and endless, with a 4 s crossfade between tracks.
/// `follow` says when to stay silent: while a game block runs, so sound never cues timing, and while Sky Plank
/// plays its own wind. With no files it stays silent and `isAvailable` is false, which hides the mini-player.
/// Tracks drop into `Audio/Music/` (see the README there).
@MainActor
@Observable
final class MusicBed {
    /// A file is a track when it sits in the bundle root, its name starts with this and its extension is listed.
    static let namePrefix = "music-"
    static let extensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "caf"]
    static let fallbackTitle = "Golden Hour"
    /// UserDefaults key for the listener's play/pause choice. Default on.
    static let defaultsKey = "music.enabled"
    /// Player volume at full level. Sits under the effects.
    static let volume: Float = 0.35
    /// Seconds: crossfade between tracks, fade to silence for a game block, fade back in on menus and results.
    static let crossfade = 4.0, fadeOut = 0.5, fadeIn = 1.5

    /// False when the bundle holds no playable track. The mini-player hides itself.
    private(set) var isAvailable: Bool
    /// The listener's choice, saved in UserDefaults `music.enabled` (default on). Context can still keep it quiet.
    private(set) var enabled: Bool
    /// Title of the track now playing, from its file name.
    private(set) var title = MusicBed.fallbackTitle

    private let tracks: [URL]
    private let defaults: UserDefaults
    @ObservationIgnored private var quiet: (@MainActor () -> Bool)?
    /// Silent until `follow` says otherwise.
    @ObservationIgnored private var silent = true
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var deck: [URL] = []
    @ObservationIgnored private var lastURL: URL?
    @ObservationIgnored private var current: Voice?
    /// The next track, alive only during a crossfade.
    @ObservationIgnored private var incoming: Voice?
    /// 0 is silent, 1 is `volume`. Ramps toward the goal at the fade rates.
    @ObservationIgnored private var level: Float = 0
    /// True while the players are paused (fully faded out) or not yet started.
    @ObservationIgnored private var paused = true
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// One decoded track and whether it has ever started playing.
    private final class Voice {
        let player: AVAudioPlayer
        let title: String
        var started = false

        init(player: AVAudioPlayer, title: String) {
            self.player = player
            self.title = title
        }

        func play() {
            if player.play() { started = true }
        }
    }

    // Audio session: deliberately left alone. Tone effects, the Sky Plank wind and the results chime already run on
    // the system default (soloAmbient), and the bed is the same kind of client as that chime (an AVAudioPlayer),
    // so none of them change. A mixable category would let other apps' audio play under a timed test, and a
    // category switch at runtime can reconfigure RealityKit's audio engine mid-play. For the same reason the
    // session is never deactivated here.
    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        let found = Self.tracks(in: bundle)
        self.defaults = defaults
        tracks = found
        isAvailable = !found.isEmpty
        enabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    // MARK: - Control

    /// Sets the condition for silence. `quiet` is read again whenever the observable state it reads changes.
    func follow(_ quiet: @escaping @MainActor () -> Bool) {
        self.quiet = quiet
        watch()
    }

    /// The listener's play/pause choice, saved at once.
    func toggle() {
        enabled.toggle()
        defaults.set(enabled, forKey: Self.defaultsKey)
        update()
    }

    private func watch() {
        guard let quiet else { return }
        silent = withObservationTracking { quiet() } onChange: { [weak self] in
            // Fires before the new value lands, so look again on the next main-actor turn.
            Task { @MainActor in self?.watch() }
        }
        update()
    }

    private func update() {
        wanted = enabled && isAvailable && !silent
        // When not wanted, the running ticker fades out and pauses; an idle bed has nothing to do.
        if wanted { resume() }
    }

    private func resume() {
        if current == nil {
            guard let first = nextVoice() else {
                isAvailable = false
                return
            }
            current = first
            show(first.title)
            paused = true
        }
        if paused {
            paused = false
            current?.play()
            incoming?.play()
        }
        startTicker()
    }

    // MARK: - Tick

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                let dt = min(now - last, 0.25)
                last = now
                guard let bed = self, bed.step(dt) else { break }
                try? await Task.sleep(for: .milliseconds(33))
            }
            self?.ticker = nil
        }
    }

    /// One tick: ramp the level, run the crossfade, set both volumes. False once the bed is paused or has
    /// no track left, which ends the ticker.
    private func step(_ dt: Double) -> Bool {
        ramp(dt)
        guard advance() else {
            isAvailable = false
            paused = true
            return false
        }
        mix()
        if !wanted, level <= 0 {
            current?.player.pause()
            incoming?.player.pause()
            paused = true
            return false
        }
        return true
    }

    /// Moves the level toward its goal: down in `fadeOut`, back up over `fadeIn`.
    private func ramp(_ dt: Double) {
        let seconds = wanted ? Self.fadeIn : Self.fadeOut
        let delta = Float(dt / seconds)
        level = wanted ? min(1, level + delta) : max(0, level - delta)
    }

    /// Starts the next track under the tail of this one, and hands over once this one has played out.
    /// False when no track can be decoded.
    private func advance() -> Bool {
        guard let cur = current else { return false }
        let player = cur.player
        var remaining = player.duration - player.currentTime
        let span = min(Self.crossfade, player.duration / 3)
        if incoming == nil, remaining <= span, let next = nextVoice() {
            next.play()
            incoming = next
        }
        if !player.isPlaying {
            // Stopped without us: it ended, or an interruption cut it. A track that never started just retries.
            if cur.started, remaining < 1 || player.currentTime < 0.05 { remaining = 0 } else { cur.play() }
        }
        guard remaining <= 0.05 else { return true }
        player.stop()
        if let next = incoming {
            current = next
        } else {
            current = nextVoice()
            current?.play()
        }
        incoming = nil
        guard let now = current else { return false }
        show(now.title)
        return true
    }

    /// Sets both volumes: level squared for a smooth fade, equal-power curves for the crossfade.
    private func mix() {
        var blend: Float = 0
        if let cur = current, incoming != nil {
            let span = min(Self.crossfade, cur.player.duration / 3)
            let left = cur.player.duration - cur.player.currentTime
            let done: Double = 1 - left / span
            blend = Float(min(max(done, 0), 1))
        }
        let quarterTurn: Float = .pi / 2
        let gain = Self.volume * level * level
        current?.player.volume = gain * cos(blend * quarterTurn)
        incoming?.player.volume = gain * sin(blend * quarterTurn)
        if blend >= 0.5, let next = incoming { show(next.title) }
    }

    private func show(_ name: String) {
        if title != name { title = name }
    }

    // MARK: - Tracks

    /// Next track off a shuffled deck, decoded and silent. Files that will not decode are skipped.
    private func nextVoice() -> Voice? {
        for _ in tracks {
            if deck.isEmpty {
                deck = tracks.shuffled()
                // Never the same track twice in a row across a reshuffle.
                if deck.count > 1, deck.last == lastURL { deck.swapAt(0, deck.count - 1) }
            }
            let url = deck.removeLast()
            lastURL = url
            guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 1 else { continue }
            player.volume = 0
            player.prepareToPlay()
            return Voice(player: player, title: Self.title(for: url))
        }
        return nil
    }

    /// Bundled audio whose name starts with `music-`, sorted by name. XcodeGen flattens everything under
    /// Sources into the bundle root, so a directory listing finds a track whatever folder it came from.
    static func tracks(in bundle: Bundle) -> [URL] {
        let root = bundle.resourceURL ?? bundle.bundleURL
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { url in
                Self.extensions.contains(url.pathExtension.lowercased())
                    && url.lastPathComponent.lowercased().hasPrefix(Self.namePrefix)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Display title from the file name: `music-golden-hour-1.m4a` reads "Golden Hour". A trailing number is a
    /// take or a version, so it is dropped. Falls back to "Golden Hour" when nothing is left.
    static func title(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent.dropFirst(namePrefix.count)
        var words = stem.split(whereSeparator: { "-_ ".contains($0) }).map(String.init)
        if let last = words.last, last.allSatisfy(\.isNumber) { words.removeLast() }
        let name = words.map { $0.capitalized }.joined(separator: " ")
        return name.isEmpty ? fallbackTitle : name
    }
}
