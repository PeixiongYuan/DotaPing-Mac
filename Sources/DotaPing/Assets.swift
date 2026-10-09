import AppKit
import AVFoundation
import PingCore

enum Assets {
    static func path(_ kind: PingKind, in rect: CGRect) -> CGPath? {
        var transform = CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY)
        return Glyphs.glyph(kind).path.copy(using: &transform)
    }
    static func draw(_ kind: PingKind, in rect: CGRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext, let path = path(kind, in: rect) else { return }
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.addPath(path); context.drawPath(using: Glyphs.glyph(kind).evenOdd ? .eoFill : .fill)
        context.restoreGState()
    }
    /// The game's ping sound files, in the app bundle or, when run from a build
    /// folder, in the repository.
    static let soundsFolder: URL = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sounds"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Sounds")
    }()
    /// Each cue mixed from the bundled files the way the game's sound events
    /// play them. A cue whose files are missing is left out.
    static let gameCues: [String: Data] = {
        func load(_ file: String) -> PCM? { (try? Data(contentsOf: soundsFolder.appendingPathComponent(file))).flatMap(WAV.decode) }
        var cues: [String: Data] = [:]
        for recipe in GameSoundRecipe.all {
            guard let main = load(recipe.file) else { continue }
            let layer = recipe.layer.flatMap { load($0.file) }
            if recipe.layer != nil && layer == nil { continue }
            cues[recipe.output] = WAV.encode(recipe.mix(main: main, layer: layer))
        }
        return cues
    }()
    static func icon(_ kind: PingKind, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            draw(kind, in: rect.insetBy(dx: 2, dy: 2), color: color); return true
        }
    }
}

extension NSColor {
    convenience init(_ rgb: RGB, alpha: CGFloat = 1) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}

extension PingKind {
    func tint(_ player: PlayerColor) -> NSColor { NSColor(color(for: player)) }
}

/// Plays, in order of preference: a same-named file from the custom folder,
/// the game's sound when selected, or the synthesised cue.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    var useGameSounds = false
    static let customFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DotaPing/Sounds", isDirectory: true)
    static let customExtensions = ["wav", "mp3", "m4a", "aiff", "aif", "caf"]
    private let synthesised: [String: Data] = Dictionary(uniqueKeysWithValues: SoundSynth.names.map { ($0, SoundSynth.wav($0)) })
    private var players: [AVAudioPlayer] = []

    static func customFile(_ name: String) -> URL? {
        customExtensions.lazy.map { customFolder.appendingPathComponent("\(name).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func customOverrides() -> [String]? {
        SoundSynth.names.compactMap { customFile($0)?.lastPathComponent }
    }
    static func revealCustomFolder() {
        try? FileManager.default.createDirectory(at: customFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(customFolder)
    }
    func play(_ kind: PingKind, volume: Double) {
        guard volume > 0 else { return }
        // Files are read on each ping, so a replaced file applies without a restart.
        let custom = Self.customFile(kind.soundName).flatMap { try? Data(contentsOf: $0) }
        let game = useGameSounds ? Assets.gameCues[kind.soundName] : nil
        guard let bytes = custom ?? game ?? synthesised[kind.soundName] else { return }
        // An unreadable custom file is skipped silently; the ping still shows.
        guard let player = try? AVAudioPlayer(data: bytes) else { return }
        player.volume = Float(volume)
        player.delegate = self
        player.prepareToPlay()
        // Bound simultaneous playback without imposing the game's rate limit.
        if players.count >= 12 { players.removeFirst().stop() }
        players.append(player)
        player.play()
    }
    func stopAll() { players.forEach { $0.stop() }; players.removeAll() }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        players.removeAll { $0 === player }
    }
}
