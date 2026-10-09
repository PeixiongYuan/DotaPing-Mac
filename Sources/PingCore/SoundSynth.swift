import Foundation

/// Short cues synthesised in memory: the alternative to the game's own ping
/// sounds (`GameSoundRecipe`). A user may also place their own files in the
/// custom sound folder.
public enum SoundSynth {
    public static let sampleRate = 44_100
    public static let names = ["ping", "ping_warning", "ping_waypoint", "ping_attack", "ping_enemy_ward", "ping_friendly_ward", "ping_defense"]

    struct Note {
        var start: Double, length: Double, frequency: Double
        var glideTo: Double? = nil
        var gain: Double = 1
        var partials: [(Double, Double)] = [(1, 1), (2, 0.18)]
        var decay: Double = 7
        var vibrato: (rate: Double, depth: Double) = (0, 0)
    }

    static func notes(_ name: String) -> [Note] {
        let buzzy: [(Double, Double)] = [(1, 1), (3, 0.30), (5, 0.14)]
        switch name {
        case "ping":
            // Two bright, rising blips.
            return [Note(start: 0, length: 0.22, frequency: 1568, partials: [(1, 1), (2, 0.25), (3, 0.08)], decay: 14),
                    Note(start: 0.085, length: 0.46, frequency: 2093, gain: 0.9, partials: [(1, 1), (2, 0.2), (4.2, 0.05)], decay: 7)]
        case "ping_warning":
            // Lower, slightly reedy and falling.
            return [Note(start: 0, length: 0.20, frequency: 932, partials: buzzy, decay: 9),
                    Note(start: 0.17, length: 0.40, frequency: 698, partials: buzzy, decay: 6)]
        case "ping_waypoint":
            // A quick major arpeggio.
            return [Note(start: 0, length: 0.16, frequency: 1047, decay: 12),
                    Note(start: 0.075, length: 0.18, frequency: 1319, decay: 11),
                    Note(start: 0.15, length: 0.42, frequency: 1568, decay: 6)]
        case "ping_attack":
            // Two hard, bending hits.
            return [Note(start: 0, length: 0.17, frequency: 740, glideTo: 600, partials: [(1, 1), (2, 0.5), (3, 0.33), (4, 0.2)], decay: 10),
                    Note(start: 0.12, length: 0.36, frequency: 988, glideTo: 930, partials: [(1, 1), (2, 0.45), (3, 0.25)], decay: 7)]
        case "ping_enemy_ward":
            // Falling and wavering: something is watching.
            return [Note(start: 0, length: 0.24, frequency: 880, partials: [(1, 1), (2.01, 0.3)], decay: 7, vibrato: (14, 0.012)),
                    Note(start: 0.14, length: 0.50, frequency: 659, partials: [(1, 1), (2.01, 0.3)], decay: 4.5, vibrato: (11, 0.018))]
        case "ping_friendly_ward":
            // Rising shimmer.
            return [Note(start: 0, length: 0.30, frequency: 1319, partials: [(1, 1), (2, 0.18), (3, 0.06)], decay: 6, vibrato: (6, 0.004)),
                    Note(start: 0.10, length: 0.50, frequency: 1760, decay: 4.5, vibrato: (6, 0.004)),
                    Note(start: 0.10, length: 0.50, frequency: 2637, gain: 0.25, decay: 6)]
        case "ping_defense":
            // A solid, bell-like strike.
            return [Note(start: 0, length: 0.62, frequency: 392, partials: [(1, 1), (2, 0.55), (3.02, 0.3), (4.1, 0.12)], decay: 5),
                    Note(start: 0, length: 0.45, frequency: 587, gain: 0.4, decay: 6)]
        default:
            return []
        }
    }

    /// Mono samples in -1...1.
    public static func samples(_ name: String) -> [Float] {
        let notes = notes(name)
        guard !notes.isEmpty else { return [] }
        let rate = Double(sampleRate)
        let total = (notes.map { $0.start + $0.length }.max() ?? 0) + 0.02
        var mix = [Double](repeating: 0, count: Int(total*rate))
        for note in notes {
            var phases = [Double](repeating: 0, count: note.partials.count)
            let first = Int(note.start*rate), count = Int(note.length*rate)
            for i in 0..<count where first+i < mix.count {
                let t = Double(i)/rate
                var frequency = note.glideTo.map { note.frequency*pow($0/note.frequency, t/note.length) } ?? note.frequency
                if note.vibrato.depth > 0 { frequency *= 1 + note.vibrato.depth*sin(2 * .pi*note.vibrato.rate*t) }
                // 4 ms attack, exponential decay, 12 ms release: no clicks at either end.
                let envelope = min(1, t/0.004) * exp(-note.decay*t) * min(1, (note.length-t)/0.012)
                var value = 0.0
                for (k, partial) in note.partials.enumerated() {
                    phases[k] += 2 * .pi*frequency*partial.0/rate
                    value += partial.1*sin(phases[k])
                }
                mix[first+i] += value*envelope*note.gain
            }
        }
        let peak = mix.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? 0.82/peak : 0
        return mix.map { Float($0*gain) }
    }

    /// 16-bit PCM mono WAV, playable by AVAudioPlayer.
    public static func wav(_ name: String) -> Data {
        WAV.encode(PCM(sampleRate: sampleRate, channels: [samples(name)]))
    }
}
