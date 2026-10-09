import Foundation
import CryptoKit
import PingCore

/// Downloads the game's own ping sounds on request and stores the mixed cues
/// on this Mac only. Nothing from the game is bundled with DotaPing.
enum GameSounds {
    enum InstallError: LocalizedError {
        case http(String, Int), checksum(String), format(String)
        var errorDescription: String? {
            switch self {
            case .http(let file, let code): return "\(file): HTTP \(code)"
            case .checksum(let file): return "\(file): checksum mismatch"
            case .format(let file): return "\(file): unsupported audio"
            }
        }
    }
    /// Community archive of the game's sound files, pinned to one commit.
    static let archive = "Source2Sounds/dota2"
    static let commit = "a4ba82b96ef173da6c83e8a658e3e7125efc3968"
    static let source = URL(string: "https://raw.githubusercontent.com/\(archive)/\(commit)/sounds/ui/")!
    /// SHA-256 of each file at that commit; anything else is rejected.
    static let checksums: [String: String] = [
        "ping.wav": "c27fc0e196b841a4fde420ba0d644e79f188be87226bcbfe08102ed2f04680e4",
        "ping_attack.wav": "492b742f634ba0af80f932f7f1f8a52b0c6320753bbd97f42fdf663c5af90098",
        "ping_attack_layer.wav": "98cd0130c28ef20e0e4766f6597393e86f5d915256235f548d52c292c292fa29",
        "ping_defense.wav": "b2d036427f605cd6f0f68e28609e977575ea46c08a73d7eecd4d3049803117fc",
        "ping_enemy_ward.wav": "6c0ba9f117252bea31c585ade55285f16d615f84b194f589b62c7e96553c5198",
        "ping_need_ward.wav": "f220a3cea143ee601fb088163bd434ccdb01a54b4443c0b30bee9449e532c080",
        "ping_warning.wav": "d2741d9061a8f2bc46adaee3a6302a1d517fd215882a01edc5a36c23ee500830",
        "ping_warning_layer.wav": "ce4ec0121958b4fd02dd8a89f3b033bf6ed876a5cf986e77358b23338f41dab0",
    ]
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DotaPing/GameSounds", isDirectory: true)

    static func file(_ name: String) -> URL { folder.appendingPathComponent(name + ".wav") }
    static var installed: Bool { SoundSynth.names.allSatisfy { FileManager.default.fileExists(atPath: file($0).path) } }

    static func install(to destination: URL = folder) async throws {
        var sources: [String: PCM] = [:]
        for name in GameSoundRecipe.files {
            let (data, response) = try await URLSession.shared.data(from: source.appendingPathComponent(name))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw InstallError.http(name, status) }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == checksums[name] else { throw InstallError.checksum(name) }
            guard let pcm = WAV.decode(data) else { throw InstallError.format(name) }
            sources[name] = pcm
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for recipe in GameSoundRecipe.all {
            let mixed = recipe.mix(main: sources[recipe.file]!, layer: recipe.layer.flatMap { sources[$0.file] })
            try WAV.encode(mixed).write(to: destination.appendingPathComponent(recipe.output + ".wav"), options: .atomic)
        }
    }
}
