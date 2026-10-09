import AppKit
import AVFoundation
import PingCore

if let index = CommandLine.arguments.firstIndex(of: "--visual-check"), CommandLine.arguments.count > index+1 {
    do { try VisualChecks.run(to: URL(fileURLWithPath: CommandLine.arguments[index+1])); exit(0) }
    catch { print("Visual check failed: \(error)"); exit(1) }
}

// Diagnostics modes never create an event tap or synthesize keyboard/mouse events.
if let index = CommandLine.arguments.firstIndex(of: "--export-sounds"), CommandLine.arguments.count > index+1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[index+1])
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in SoundSynth.names { try SoundSynth.wav(name).write(to: folder.appendingPathComponent(name + ".wav")) }
        print("Exported \(SoundSynth.names.count) synthesised cues: \(folder.path)"); exit(0)
    } catch { print("Export failed: \(error)"); exit(1) }
}

// Writes the glyph outlines for the Windows build as WPF path markup in a unit
// square with y pointing down, keyed by PingKind raw value.
if let index = CommandLine.arguments.firstIndex(of: "--export-glyphs"), CommandLine.arguments.count > index+1 {
    func point(_ p: CGPoint) -> String { String(format: "%.5f,%.5f", Double(p.x), Double(1-p.y)) }
    var glyphs: [String: String] = [:]
    for kind in PingKind.allCases {
        let glyph = Glyphs.glyph(kind)
        var parts = [glyph.evenOdd ? "F0" : "F1"]
        glyph.path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: parts.append("M" + point(points[0]))
            case .addLineToPoint: parts.append("L" + point(points[0]))
            case .addQuadCurveToPoint: parts.append("Q" + point(points[0]) + " " + point(points[1]))
            case .addCurveToPoint: parts.append("C" + point(points[0]) + " " + point(points[1]) + " " + point(points[2]))
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
        glyphs[kind.rawValue] = parts.joined(separator: " ")
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: glyphs, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
        print("Exported \(glyphs.count) glyphs"); exit(0)
    } catch { print("Export failed: \(error)"); exit(1) }
}

if CommandLine.arguments.contains("--check-assets") {
    var failures: [String] = []
    for kind in PingKind.allCases {
        if Glyphs.glyph(kind).path.isEmpty { failures.append("Empty glyph: \(kind.rawValue)") }
        do {
            let player = try AVAudioPlayer(data: SoundSynth.wav(kind.soundName))
            if player.duration <= 0 { failures.append("Invalid duration: \(kind.soundName)") }
            print("\(kind.title(.english)): glyph=\(Glyphs.glyph(kind).evenOdd ? "even-odd" : "union"), sound=\(kind.soundName) \(String(format: "%.2f", player.duration))s")
        } catch { failures.append("\(kind.soundName): \(error.localizedDescription)") }
    }
    if let custom = SoundPlayer.customOverrides(), !custom.isEmpty { print("Custom sounds in use: " + custom.joined(separator: ", ")) }
    for recipe in GameSoundRecipe.all {
        guard let cue = Assets.gameCues[recipe.output], let player = try? AVAudioPlayer(data: cue), player.duration > 0 else {
            failures.append("Game sound missing or unreadable: \(recipe.output)"); continue
        }
        print("game \(recipe.output): \(String(format: "%.2f", player.duration))s")
    }
    if failures.isEmpty { print("All \(PingKind.allCases.count) glyphs draw; all 7 game and 7 synthesised cues decode."); exit(0) }
    failures.forEach { print($0) }; exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
