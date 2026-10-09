namespace DotaPing.Core;

/// <summary>Uncompressed audio, one array per channel, samples in -1...1.</summary>
public sealed class Pcm(int sampleRate, float[][] channels)
{
    public int SampleRate { get; } = sampleRate;
    public float[][] Channels { get; } = channels;
    public int FrameCount => Channels.Length == 0 ? 0 : Channels[0].Length;
}

/// <summary>16-bit PCM WAV, the format of the game's UI sounds and of the synthesised cues.</summary>
public static class Wav
{
    public static byte[] Encode(Pcm pcm)
    {
        int channels = Math.Max(1, pcm.Channels.Length), frames = pcm.FrameCount, bytes = frames * channels * 2;
        using var stream = new MemoryStream(44 + bytes);
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8); writer.Write(36 + bytes);
        writer.Write("WAVEfmt "u8); writer.Write(16); writer.Write((short)1); writer.Write((short)channels);
        writer.Write(pcm.SampleRate); writer.Write(pcm.SampleRate * channels * 2); writer.Write((short)(channels * 2)); writer.Write((short)16);
        writer.Write("data"u8); writer.Write(bytes);
        for (int frame = 0; frame < frames; frame++)
            for (int channel = 0; channel < channels; channel++)
            {
                float value = pcm.Channels.Length == 0 ? 0 : pcm.Channels[channel][frame];
                writer.Write((short)(Math.Clamp(value, -1f, 1f) * short.MaxValue));
            }
        writer.Flush();
        return stream.ToArray();
    }

    /// <summary>Reads 16-bit integer PCM; anything else returns null.</summary>
    public static Pcm? Decode(byte[] data)
    {
        if (data.Length < 12 || data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F'
            || data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') return null;
        int U16(int i) => data[i] | data[i + 1] << 8;
        int U32(int i) => U16(i) | U16(i + 2) << 16;
        int offset = 12, channels = 0, rate = 0, bits = 0, format = 0;
        while (offset + 8 <= data.Length)
        {
            string id = System.Text.Encoding.ASCII.GetString(data, offset, 4);
            int size = U32(offset + 4), body = offset + 8;
            if (body + size > data.Length && id != "data") return null;
            if (id == "fmt " && size >= 16)
            {
                format = U16(body); channels = U16(body + 2); rate = U32(body + 4); bits = U16(body + 14);
            }
            else if (id == "data")
            {
                if (format != 1 || bits != 16 || channels <= 0 || rate <= 0) return null;
                int end = Math.Min(body + size, data.Length), frames = (end - body) / (2 * channels);
                var result = new float[channels][];
                for (int c = 0; c < channels; c++) result[c] = new float[frames];
                for (int frame = 0; frame < frames; frame++)
                    for (int c = 0; c < channels; c++)
                        result[c][frame] = (short)U16(body + (frame * channels + c) * 2) / (float)short.MaxValue;
                return new Pcm(rate, result);
            }
            offset = body + size + (size & 1);
        }
        return null;
    }
}

/// <summary>
/// How the game plays each ping sound event: a main file and, for Warning and
/// Attack, a second layer with its own volume, pitch and delay. Values from
/// soundevents/game_sounds_ui_imported.vsndevts.
/// </summary>
public sealed record GameSoundRecipe(string Output, string File, float Volume, GameSoundRecipe.LayerSpec? Layer)
{
    public sealed record LayerSpec(string File, float Volume, double Pitch, double Delay);

    public static readonly IReadOnlyList<GameSoundRecipe> All =
    [
        new("ping", "ping.wav", 0.6f, null),
        new("ping_warning", "ping_warning.wav", 0.5f, new("ping_warning_layer.wav", 0.5f, 1.25, 0)),
        new("ping_waypoint", "ping.wav", 0.5f, null),
        new("ping_attack", "ping_attack.wav", 0.6f, new("ping_attack_layer.wav", 0.5f, 0.95, 0.1)),
        new("ping_enemy_ward", "ping_enemy_ward.wav", 0.3f, null),
        new("ping_friendly_ward", "ping_need_ward.wav", 0.5f, null),
        new("ping_defense", "ping_defense.wav", 0.6f, null),
    ];

    public static IReadOnlyList<string> Files =>
        All.SelectMany(r => r.Layer is null ? [r.File] : new[] { r.File, r.Layer.File }).Distinct().Order(StringComparer.Ordinal).ToList();

    /// <summary>
    /// Mixes the main file and its layer at the main file's sample rate. The
    /// loudest event volume (0.6) maps to unity gain, so relative levels match
    /// the game; the result is scaled down only if it would clip.
    /// </summary>
    public Pcm Mix(Pcm main, Pcm? layerPcm)
    {
        double rate = main.SampleRate; const float unity = 0.6f;
        var channels = main.Channels.Select(c => c.Select(v => v * Volume / unity).ToArray()).ToArray();
        if (Layer is { } layer && layerPcm is { FrameCount: > 0 } source)
        {
            // Varispeed, as a pitch change does in game: the layer gets shorter as it gets higher.
            double step = source.SampleRate * layer.Pitch / rate;
            int start = (int)Math.Round(layer.Delay * rate);
            int length = start + (int)((source.FrameCount - 1) / step) + 1;
            for (int c = 0; c < channels.Length; c++)
            {
                if (channels[c].Length < length) Array.Resize(ref channels[c], length);
                var input = source.Channels[Math.Min(c, source.Channels.Length - 1)];
                for (int i = 0; i < length - start; i++)
                {
                    double position = i * step;
                    int index = (int)position, next = Math.Min(index + 1, input.Length - 1);
                    float fraction = (float)(position - index);
                    channels[c][start + i] += (input[index] * (1 - fraction) + input[next] * fraction) * layer.Volume / unity;
                }
            }
        }
        float peak = channels.SelectMany(c => c).Select(Math.Abs).DefaultIfEmpty(0).Max();
        if (peak > 0.98f) channels = channels.Select(c => c.Select(v => v * 0.98f / peak).ToArray()).ToArray();
        return new Pcm(main.SampleRate, channels);
    }
}

/// <summary>Short cues synthesised in memory: the alternative to the game's own ping sounds.</summary>
public static class SoundSynth
{
    public const int SampleRate = 44_100;
    public static readonly IReadOnlyList<string> Names =
        ["ping", "ping_warning", "ping_waypoint", "ping_attack", "ping_enemy_ward", "ping_friendly_ward", "ping_defense"];

    sealed record Note(double Start, double Length, double Frequency, double? GlideTo = null, double Gain = 1,
                       (double Ratio, double Amp)[]? Partials = null, double Decay = 7, double VibratoRate = 0, double VibratoDepth = 0);

    static Note[] Notes(string name)
    {
        (double, double)[] buzzy = [(1, 1), (3, 0.30), (5, 0.14)];
        return name switch
        {
            "ping" => [new(0, 0.22, 1568, Partials: [(1, 1), (2, 0.25), (3, 0.08)], Decay: 14),
                       new(0.085, 0.46, 2093, Gain: 0.9, Partials: [(1, 1), (2, 0.2), (4.2, 0.05)], Decay: 7)],
            "ping_warning" => [new(0, 0.20, 932, Partials: buzzy, Decay: 9), new(0.17, 0.40, 698, Partials: buzzy, Decay: 6)],
            "ping_waypoint" => [new(0, 0.16, 1047, Decay: 12), new(0.075, 0.18, 1319, Decay: 11), new(0.15, 0.42, 1568, Decay: 6)],
            "ping_attack" => [new(0, 0.17, 740, GlideTo: 600, Partials: [(1, 1), (2, 0.5), (3, 0.33), (4, 0.2)], Decay: 10),
                              new(0.12, 0.36, 988, GlideTo: 930, Partials: [(1, 1), (2, 0.45), (3, 0.25)], Decay: 7)],
            "ping_enemy_ward" => [new(0, 0.24, 880, Partials: [(1, 1), (2.01, 0.3)], Decay: 7, VibratoRate: 14, VibratoDepth: 0.012),
                                  new(0.14, 0.50, 659, Partials: [(1, 1), (2.01, 0.3)], Decay: 4.5, VibratoRate: 11, VibratoDepth: 0.018)],
            "ping_friendly_ward" => [new(0, 0.30, 1319, Partials: [(1, 1), (2, 0.18), (3, 0.06)], Decay: 6, VibratoRate: 6, VibratoDepth: 0.004),
                                     new(0.10, 0.50, 1760, Decay: 4.5, VibratoRate: 6, VibratoDepth: 0.004),
                                     new(0.10, 0.50, 2637, Gain: 0.25, Decay: 6)],
            "ping_defense" => [new(0, 0.62, 392, Partials: [(1, 1), (2, 0.55), (3.02, 0.3), (4.1, 0.12)], Decay: 5),
                               new(0, 0.45, 587, Gain: 0.4, Decay: 6)],
            _ => [],
        };
    }

    /// <summary>Mono samples in -1...1, identical in design to the macOS cues.</summary>
    public static float[] Samples(string name)
    {
        var notes = Notes(name);
        if (notes.Length == 0) return [];
        double rate = SampleRate, total = notes.Max(n => n.Start + n.Length) + 0.02;
        var mix = new double[(int)(total * rate)];
        foreach (var note in notes)
        {
            var partials = note.Partials ?? [(1, 1), (2, 0.18)];
            var phases = new double[partials.Length];
            int first = (int)(note.Start * rate), count = (int)(note.Length * rate);
            for (int i = 0; i < count && first + i < mix.Length; i++)
            {
                double t = i / rate;
                double frequency = note.GlideTo is { } to ? note.Frequency * Math.Pow(to / note.Frequency, t / note.Length) : note.Frequency;
                if (note.VibratoDepth > 0) frequency *= 1 + note.VibratoDepth * Math.Sin(2 * Math.PI * note.VibratoRate * t);
                // 4 ms attack, exponential decay, 12 ms release: no clicks at either end.
                double envelope = Math.Min(1, t / 0.004) * Math.Exp(-note.Decay * t) * Math.Min(1, (note.Length - t) / 0.012);
                double value = 0;
                for (int k = 0; k < partials.Length; k++)
                {
                    phases[k] += 2 * Math.PI * frequency * partials[k].Ratio / rate;
                    value += partials[k].Amp * Math.Sin(phases[k]);
                }
                mix[first + i] += value * envelope * note.Gain;
            }
        }
        double peak = mix.Select(Math.Abs).Max(), gain = peak > 0 ? 0.82 / peak : 0;
        return mix.Select(v => (float)(v * gain)).ToArray();
    }

    public static byte[] Wav(string name) => Core.Wav.Encode(new Pcm(SampleRate, [Samples(name)]));
}
