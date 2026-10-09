using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Media;
using DotaPing.Core;

namespace DotaPing;

/// <summary>
/// Plays, in order of preference: a same-named file from the custom folder, the
/// game's sound when selected, or the synthesised cue. MediaPlayer needs files,
/// so the cues are written to a cache folder once at launch.
/// </summary>
sealed class SoundPlayer
{
    public static readonly string CustomFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DotaPing", "Sounds");
    static readonly string CacheFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DotaPing", "Cues");
    static readonly string[] CustomExtensions = ["wav", "mp3", "m4a", "wma"];

    public bool UseGameSounds { get; set; } = true;
    readonly Task<(Dictionary<string, string> Game, Dictionary<string, string> Synthesized)> cues = Task.Run(PrepareCues);
    readonly List<MediaPlayer> players = [];

    /// <summary>The game's cues mixed from the embedded files, as WAV bytes keyed by cue name.</summary>
    public static Dictionary<string, byte[]> MixGameCues()
    {
        var assembly = Assembly.GetExecutingAssembly();
        Pcm? Load(string file)
        {
            using var stream = assembly.GetManifestResourceStream("Sounds." + file);
            if (stream is null) return null;
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return Wav.Decode(memory.ToArray());
        }
        var sources = GameSoundRecipe.Files.ToDictionary(f => f, Load);
        var result = new Dictionary<string, byte[]>();
        foreach (var recipe in GameSoundRecipe.All)
        {
            if (sources[recipe.File] is not { } main) continue;
            Pcm? layer = recipe.Layer is null ? null : sources[recipe.Layer.File];
            if (recipe.Layer is not null && layer is null) continue;
            result[recipe.Output] = Wav.Encode(recipe.Mix(main, layer));
        }
        return result;
    }

    static (Dictionary<string, string>, Dictionary<string, string>) PrepareCues()
    {
        var game = new Dictionary<string, string>();
        var synthesized = new Dictionary<string, string>();
        try
        {
            Directory.CreateDirectory(Path.Combine(CacheFolder, "game"));
            Directory.CreateDirectory(Path.Combine(CacheFolder, "synth"));
            foreach (var (name, bytes) in MixGameCues())
            {
                var path = Path.Combine(CacheFolder, "game", name + ".wav");
                File.WriteAllBytes(path, bytes);
                game[name] = path;
            }
            foreach (var name in SoundSynth.Names)
            {
                var path = Path.Combine(CacheFolder, "synth", name + ".wav");
                File.WriteAllBytes(path, SoundSynth.Wav(name));
                synthesized[name] = path;
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return (game, synthesized);
    }

    static string? CustomFile(string name) => CustomExtensions.Select(e => Path.Combine(CustomFolder, $"{name}.{e}")).FirstOrDefault(File.Exists);

    public static void RevealCustomFolder()
    {
        Directory.CreateDirectory(CustomFolder);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"\"{CustomFolder}\"") { UseShellExecute = true });
    }

    public void Play(PingKind kind, double volume)
    {
        if (volume <= 0) return;
        var (game, synthesized) = cues.Result;
        string name = kind.SoundName();
        string? file = CustomFile(name)
            ?? (UseGameSounds && game.TryGetValue(name, out var g) ? g : null)
            ?? (synthesized.TryGetValue(name, out var s) ? s : null);
        if (file is null) return;
        var player = new MediaPlayer { Volume = volume };
        void Finish() { player.Close(); players.Remove(player); }
        player.MediaEnded += (_, _) => Finish();
        player.MediaFailed += (_, _) => Finish();
        player.Open(new Uri(file));
        player.Play();
        // Bound simultaneous playback without imposing the game's rate limit.
        players.Add(player);
        if (players.Count > 12) { players[0].Stop(); players[0].Close(); players.RemoveAt(0); }
    }

    public void StopAll()
    {
        foreach (var player in players) { player.Stop(); player.Close(); }
        players.Clear();
    }
}
