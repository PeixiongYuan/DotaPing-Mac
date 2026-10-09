import Foundation

/// Uncompressed audio, one array per channel, samples in -1...1.
public struct PCM: Equatable {
    public var sampleRate: Int
    public var channels: [[Float]]
    public init(sampleRate: Int, channels: [[Float]]) { self.sampleRate = sampleRate; self.channels = channels }
    public var frameCount: Int { channels.first?.count ?? 0 }
}

/// 16-bit PCM WAV, the format of the game's UI sounds and of the synthesised cues.
public enum WAV {
    public static func encode(_ pcm: PCM) -> Data {
        let channels = max(1, pcm.channels.count), frames = pcm.frameCount
        var data = Data(capacity: 44 + frames*channels*2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(frames*channels*2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36+bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(channels))
        append(UInt32(pcm.sampleRate)); append(UInt32(pcm.sampleRate*channels*2)); append(UInt16(channels*2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for frame in 0..<frames {
            for channel in 0..<channels {
                let value = pcm.channels.isEmpty ? 0 : pcm.channels[channel][frame]
                append(Int16(max(-1, min(1, value)) * Float(Int16.max)))
            }
        }
        return data
    }

    /// Reads 16-bit integer PCM; anything else returns nil.
    public static func decode(_ data: Data) -> PCM? {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i+1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i+2) << 16 }
        guard bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x41, 0x56, 0x45] else { return nil }
        var offset = 12, channels = 0, rate = 0, bits = 0, format = 0
        while offset+8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset+4], as: UTF8.self), size = u32(offset+4), body = offset+8
            guard body+size <= bytes.count || id == "data" else { return nil }
            if id == "fmt ", size >= 16 {
                format = u16(body); channels = u16(body+2); rate = u32(body+4); bits = u16(body+14)
            } else if id == "data" {
                guard format == 1, bits == 16, channels > 0, rate > 0 else { return nil }
                let end = min(body+size, bytes.count), frames = (end-body)/(2*channels)
                var result = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        result[channel][frame] = Float(Int16(bitPattern: UInt16(u16(body + (frame*channels+channel)*2)))) / Float(Int16.max)
                    }
                }
                return PCM(sampleRate: rate, channels: result)
            }
            offset = body + size + (size & 1)
        }
        return nil
    }
}

/// How the game plays each ping sound event: a main file and, for Warning
/// and Attack, a second layer with its own volume, pitch and delay. Values
/// from `soundevents/game_sounds_ui_imported.vsndevts`.
public struct GameSoundRecipe {
    public struct Layer {
        public let file: String
        public let volume: Float
        public let pitch: Double
        public let delay: Double
    }
    /// The cue name used by DotaPing (`SoundSynth.names`).
    public let output: String
    public let file: String
    public let volume: Float
    public let layer: Layer?

    public static let all: [GameSoundRecipe] = [
        GameSoundRecipe(output: "ping", file: "ping.wav", volume: 0.6, layer: nil),
        GameSoundRecipe(output: "ping_warning", file: "ping_warning.wav", volume: 0.5,
                        layer: Layer(file: "ping_warning_layer.wav", volume: 0.5, pitch: 1.25, delay: 0)),
        GameSoundRecipe(output: "ping_waypoint", file: "ping.wav", volume: 0.5, layer: nil),
        GameSoundRecipe(output: "ping_attack", file: "ping_attack.wav", volume: 0.6,
                        layer: Layer(file: "ping_attack_layer.wav", volume: 0.5, pitch: 0.95, delay: 0.1)),
        GameSoundRecipe(output: "ping_enemy_ward", file: "ping_enemy_ward.wav", volume: 0.3, layer: nil),
        GameSoundRecipe(output: "ping_friendly_ward", file: "ping_need_ward.wav", volume: 0.5, layer: nil),
        GameSoundRecipe(output: "ping_defense", file: "ping_defense.wav", volume: 0.6, layer: nil),
    ]
    public static var files: [String] { Array(Set(all.flatMap { [$0.file] + ($0.layer.map { [$0.file] } ?? []) })).sorted() }

    /// Mixes the main file and its layer at the main file's sample rate. The
    /// loudest event volume (0.6) maps to unity gain, so relative levels match
    /// the game; the result is scaled down only if it would clip.
    public func mix(main: PCM, layer layerPCM: PCM?) -> PCM {
        let rate = Double(main.sampleRate), unity: Float = 0.6
        var channels = main.channels.map { $0.map { $0*volume/unity } }
        if let layer, let source = layerPCM, source.frameCount > 0 {
            // Varispeed, as a pitch change does in game: the layer gets shorter as it gets higher.
            let step = Double(source.sampleRate)*layer.pitch/rate, start = Int((layer.delay*rate).rounded())
            let length = start + Int(Double(source.frameCount-1)/step) + 1
            for channel in channels.indices {
                if channels[channel].count < length { channels[channel] += [Float](repeating: 0, count: length-channels[channel].count) }
                let input = source.channels[min(channel, source.channels.count-1)]
                for i in 0..<(length-start) {
                    let position = Double(i)*step, index = Int(position), fraction = Float(position-Double(index))
                    let next = min(index+1, input.count-1)
                    channels[channel][start+i] += (input[index]*(1-fraction) + input[next]*fraction) * layer.volume/unity
                }
            }
        }
        let peak = channels.joined().reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0.98 { channels = channels.map { $0.map { $0*0.98/peak } } }
        return PCM(sampleRate: main.sampleRate, channels: channels)
    }
}
