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
    if failures.isEmpty { print("All 9 glyphs draw and all 7 synthesised cues decode."); exit(0) }
    failures.forEach { print($0) }; exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
