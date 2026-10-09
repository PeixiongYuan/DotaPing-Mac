// Checks for DotaPing.Core, mirroring Tests/PingCoreTests on macOS. Run from
// the repository root: dotnet run --project windows/Checks
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.Json;
using DotaPing.Core;
using A = DotaPing.Core.GestureAction;

int failures = 0, assertions = 0;
void Check(bool condition, string what = "", [CallerLineNumber] int line = 0)
{
    assertions++;
    if (!condition) { failures++; Console.WriteLine($"FAIL Program.cs:{line} {what}"); }
}
void Same(IEnumerable<A> actual, params A[] expected) => Check(actual.SequenceEqual(expected), $"[{string.Join(", ", actual)}] != [{string.Join(", ", expected)}]");
void Resp(GestureResponse actual, bool consume, params A[] expected) =>
    Check(actual.Matches(consume, expected), $"{actual.Consume} [{string.Join(", ", actual.Actions)}] != {consume} [{string.Join(", ", expected)}]");

var chord = Modifiers.Control | Modifiers.Alt | Modifiers.Shift;
var anchor = new Point2(600, 400);
void Open(GestureMachine m)
{
    Same(m.FlagsChanged(chord, anchor, false), new A.Arm(anchor));
    Same(m.DelayElapsed(), new A.Show(anchor));
}
GestureMachine Game() => new() { Trigger = Trigger.AltClick };

var scenarios = new List<(string, Action)>
{
    ("Every direction and centre zone", () =>
    {
        Check(Pings.Wheel.Count == 9);
        for (int i = 0; i < Pings.Wheel.Count; i++)
            foreach (var offset in new[] { 0, -WheelGeometry.Sector / 2 + 0.01, WheelGeometry.Sector / 2 - 0.01 })
            {
                double theta = i * WheelGeometry.Sector + offset;
                Check(WheelGeometry.Selection(new(100 * Math.Sin(theta), 100 * Math.Cos(theta)), new(0, 0), WheelGeometry.CenterRadius) == Pings.Wheel[i]);
            }
        Check(WheelGeometry.Selection(new(66, 0), new(0, 0), WheelGeometry.CenterRadius) == PingKind.Regular);
        Check(WheelGeometry.Selection(new(67, 0), new(0, 0), WheelGeometry.CenterRadius) == PingKind.OnMyWay);
    }),
    ("Short press never pings", () =>
    {
        var m = new GestureMachine();
        m.FlagsChanged(chord, anchor, false);
        Same(m.FlagsChanged(Modifiers.None, anchor, false), new A.Hide());
        Same(m.DelayElapsed());
    }),
    ("Sends once at the original anchor", () =>
    {
        var m = new GestureMachine(); Open(m);
        // Due west lies in the Enemy Ward slot (260°–300°).
        Same(m.Moved(new(500, 400)), new A.Hover(PingKind.EnemyWard, -Math.PI / 2));
        Same(m.FlagsChanged(Modifiers.Control | Modifiers.Alt, new(0, 0), false), new A.Dismiss(), new A.Commit(PingKind.EnemyWard, anchor));
        Same(m.FlagsChanged(Modifiers.Alt, new(0, 0), false));
        Same(m.FlagsChanged(Modifiers.None, new(0, 0), false));
        Check(m.Phase == Phase.Idle);
    }),
    ("Every key-release order", () =>
    {
        Modifiers[] keys = [Modifiers.Control, Modifiers.Alt, Modifiers.Shift];
        foreach (var first in keys)
            foreach (var second in keys.Where(k => k != first))
            {
                var m = new GestureMachine(); Open(m);
                var remaining = chord; int commits = 0;
                foreach (var key in new[] { first, second }.Concat(keys.Where(k => k != first && k != second)))
                {
                    remaining &= ~key;
                    commits += m.FlagsChanged(remaining, anchor, false).Count(a => a is A.Commit);
                }
                Check(commits == 1); Check(m.Phase == Phase.Idle);
            }
    }),
    ("Re-pressing a key does not send again", () =>
    {
        var m = new GestureMachine(); Open(m);
        m.FlagsChanged(Modifiers.Control | Modifiers.Alt, anchor, false);
        Same(m.FlagsChanged(chord, anchor, false));
        Same(m.DelayElapsed());
        m.FlagsChanged(Modifiers.None, anchor, false);
        Open(m);
    }),
    ("Cancel requires a full release", () =>
    {
        var m = new GestureMachine(); Open(m);
        Same(m.Cancel(), new A.Hide());
        Same(m.FlagsChanged(Modifiers.Alt, anchor, false));
        m.FlagsChanged(chord, anchor, false);
        Same(m.DelayElapsed());
        m.FlagsChanged(Modifiers.None, anchor, false);
        Open(m);
    }),
    ("Extra modifier cancels", () =>
    {
        var m = new GestureMachine(); Open(m);
        Same(m.FlagsChanged(chord | Modifiers.Win, anchor, false), new A.Hide());
        Same(m.FlagsChanged(Modifiers.None, anchor, false));
    }),
    ("Existing drag or key press does not arm", () =>
    {
        var m = new GestureMachine();
        Same(m.FlagsChanged(chord, anchor, true));
        Same(m.DelayElapsed());
        Check(m.Phase == Phase.Blocked);
    }),
    ("No commit after reset", () =>
    {
        var m = new GestureMachine(); Open(m);
        m.Reset();
        Same(m.FlagsChanged(Modifiers.None, anchor, false));
        Same(m.DelayElapsed());
    }),
    ("Multi-display coordinates and edge anchor", () =>
    {
        var m = new GestureMachine();
        var edge = new Point2(-1915, 1080);
        var center = WheelGeometry.ClampedCenter(edge, new Rect2(-1920, 0, 1920, 1080), 150);
        Check(center == new Point2(-1770, 930));
        m.FlagsChanged(chord, edge, false); m.DelayElapsed();
        Same(m.SetWheelCenter(center));
        m.Moved(new(center.X + 90, center.Y));
        Same(m.FlagsChanged(Modifiers.None, edge, false), new A.Dismiss(), new A.Commit(PingKind.OnMyWay, edge));
    }),
    ("Pointer movement during the delay", () =>
    {
        var m = new GestureMachine();
        m.FlagsChanged(chord, anchor, false);
        m.Moved(new(620, 300));
        m.DelayElapsed();
        Same(m.SetWheelCenter(anchor), new A.Hover(PingKind.Assist, Math.Atan2(20, -100)));
    }),
    ("Every chord trigger", () =>
    {
        foreach (var trigger in Triggers.All.Where(t => !t.UsesPrimaryButton()))
        {
            var m = new GestureMachine { Trigger = trigger };
            Same(m.FlagsChanged(trigger.Modifiers(), anchor, false), new A.Arm(anchor));
            m.DelayElapsed();
            Same(m.FlagsChanged(Modifiers.None, anchor, false), new A.Dismiss(), new A.Commit(PingKind.Regular, anchor));
        }
    }),
    ("Direction updates and return to centre", () =>
    {
        var m = new GestureMachine(); Open(m);
        Same(m.Moved(new(600, 500)), new A.Hover(PingKind.Caution, 0));
        Same(m.Moved(new(610, 500)), new A.Hover(PingKind.Caution, Math.Atan2(10, 100)));
        Same(m.Moved(new(600, 466)), new A.Hover(PingKind.Regular, null));
        Same(m.FlagsChanged(Modifiers.None, anchor, false), new A.Dismiss(), new A.Commit(PingKind.Regular, anchor));
        Same(m.Moved(new(600, 500)));
    }),
    ("Scaled centre zone matches the drawing", () =>
    {
        foreach (var scale in new[] { 0.75, 1, 1.5 })
        {
            var m = new GestureMachine { DeadZone = WheelGeometry.CenterRadius * scale }; Open(m);
            Same(m.Moved(new(anchor.X + 66 * scale, anchor.Y)), new A.Hover(PingKind.Regular, null));
            Same(m.Moved(new(anchor.X + 66 * scale + 0.01, anchor.Y)), new A.Hover(PingKind.OnMyWay, Math.PI / 2));
        }
    }),
    ("Touchpad tap confirms once", () =>
    {
        var m = new GestureMachine(); Open(m);
        m.Moved(new(680, 480));
        Resp(m.PrimaryDown(new(680, 480), false), true, new A.Dismiss(), new A.Commit(PingKind.Attack, anchor));
        Resp(m.PrimaryDragged(new(690, 480)), true);
        Resp(m.PrimaryUp(new(690, 480)), true);
        Same(m.FlagsChanged(Modifiers.Control, anchor, false));
        Same(m.FlagsChanged(chord, anchor, false));
        Same(m.FlagsChanged(Modifiers.None, anchor, false));
        Resp(m.PrimaryUp(anchor), false);
        Open(m);
    }),
    ("Click before the wheel opens passes through", () =>
    {
        var m = new GestureMachine();
        m.FlagsChanged(chord, anchor, false);
        Resp(m.PrimaryDown(anchor, false), false, new A.Hide());
        Resp(m.PrimaryUp(anchor), false);
        Same(m.DelayElapsed());
        Check(m.Phase == Phase.Blocked);
    }),
    ("Foreign drag still cancels", () =>
    {
        var m = new GestureMachine(); Open(m);
        Resp(m.PrimaryDragged(anchor), false, new A.Hide());
        Same(m.FlagsChanged(Modifiers.None, anchor, false));
    }),
    ("Alt-click sends a Ping", () =>
    {
        var m = Game();
        Same(m.FlagsChanged(Modifiers.Alt, anchor, false));
        Resp(m.PrimaryDown(anchor, false), true, new A.Arm(anchor));
        Resp(m.PrimaryUp(anchor), true, new A.Hide(), new A.Commit(PingKind.Regular, anchor));
        Same(m.DelayElapsed());
        Check(m.Phase == Phase.Idle);
    }),
    ("Alt-hold, drag and release", () =>
    {
        var m = Game();
        m.FlagsChanged(Modifiers.Alt, anchor, false);
        m.PrimaryDown(anchor, false);
        Same(m.DelayElapsed(), new A.Show(anchor));
        Same(m.SetWheelCenter(anchor));
        Resp(m.PrimaryDragged(new(620, 300)), true, new A.Hover(PingKind.Assist, Math.Atan2(20, -100)));
        Same(m.FlagsChanged(Modifiers.None, anchor, false));
        Resp(m.PrimaryDragged(new(520, 320)), true, new A.Hover(PingKind.Defend, Math.Atan2(-80, -80)));
        Resp(m.PrimaryUp(new(520, 320)), true, new A.Dismiss(), new A.Commit(PingKind.Defend, anchor));
        Resp(m.PrimaryUp(anchor), false);
    }),
    ("Ctrl+Alt-click sends one Warning", () =>
    {
        var m = Game();
        m.FlagsChanged(Modifiers.Control | Modifiers.Alt, anchor, false);
        Resp(m.PrimaryDown(anchor, false), true, new A.Commit(PingKind.Warning, anchor));
        Same(m.DelayElapsed());
        Resp(m.PrimaryDragged(new(700, 400)), true);
        Resp(m.PrimaryUp(anchor), true);
    }),
    ("Other clicks pass through", () =>
    {
        foreach (var flags in new[] { Modifiers.None, Modifiers.Win, Modifiers.Alt | Modifiers.Win, Modifiers.Alt | Modifiers.Shift, Modifiers.Control })
        {
            var m = Game();
            m.FlagsChanged(flags, anchor, false);
            Resp(m.PrimaryDown(anchor, false), false);
            Resp(m.PrimaryUp(anchor), false);
        }
        var held = Game();
        held.FlagsChanged(Modifiers.Alt, anchor, false);
        Resp(held.PrimaryDown(anchor, true), false);
    }),
    ("Cancel while held swallows the release", () =>
    {
        var m = Game();
        m.FlagsChanged(Modifiers.Alt, anchor, false);
        m.PrimaryDown(anchor, false); m.DelayElapsed();
        m.PrimaryDragged(new(600, 500));
        Same(m.Cancel(), new A.Hide());
        Resp(m.PrimaryDragged(new(600, 520)), true);
        Resp(m.PrimaryUp(anchor), true);
        Resp(m.PrimaryDown(anchor, false), true, new A.Arm(anchor));
    }),
    ("Alt already held when enabled", () =>
    {
        var m = Game();
        m.Reset(modifiers: Modifiers.Alt);
        Resp(m.PrimaryDown(anchor, false), true, new A.Arm(anchor));
        m.Reset();
        Resp(m.PrimaryUp(anchor), false);
        Same(m.DelayElapsed());
    }),
    ("Game data and player colours", () =>
    {
        Check(Pings.Wheel.Distinct().Count() == 9 && !Pings.Wheel.Contains(PingKind.Regular));
        Check(PingKind.Caution.FixedColor() == Rgb.Of(255, 155, 14));
        Check(PingKind.EnemyWard.Color(PlayerColor.Pink) == Rgb.Of(225, 51, 51));
        Check(PingKind.Attack.Color(PlayerColor.Pink) == PlayerColor.Pink.Rgb());
        Check(PlayerColors.All.Select(c => c.Rgb()).Distinct().Count() == 10);
        Check(PlayerColors.All.Count(c => c.IsRadiant()) == 5);
        Check(Pings.All.Select(k => k.SoundName()).ToHashSet().SetEquals(SoundSynth.Names));
    }),
    ("Both languages complete", () =>
    {
        Check(Pings.Wheel.Select(k => k.Title(Language.English)).SequenceEqual(
            ["Caution", "Attack", "On My Way", "Warning", "Assist", "Friendly Ward", "Defend", "Enemy Ward", "Question Mark"]));
        foreach (var l in new[] { Language.English, Language.Chinese })
        {
            Check(Pings.All.Select(k => k.Title(l)).Distinct().Count() == 10);
            Check(Pings.All.Count(k => k.Chat(l) is not null) == 7);
            Check(PlayerColors.All.Select(c => c.Title(l)).Distinct().Count() == 10);
            Check(Triggers.All.Select(t => t.Title(l)).Distinct().Count() == Triggers.All.Count);
            Check(Triggers.All.All(t => t.Usage(l).Length > 0 && t.Ready(l).Length > 0));
        }
        Check(PingKind.FriendlyWard.Chat(Language.Chinese) == "我们需要视野");
        Check(Languages.FromCode("missing") == Language.English && Languages.FromCode("zh-Hans") == Language.Chinese);
    }),
    ("WAV encode and decode", () =>
    {
        var pcm = new Pcm(44_100, [[0, 0.5f, -0.5f, 1], [0.25f, -0.25f, 0, -1]]);
        var decoded = Wav.Decode(Wav.Encode(pcm));
        Check(decoded is { SampleRate: 44_100 } && decoded.Channels.Length == 2);
        Check(decoded is not null && pcm.Channels.SelectMany(c => c).Zip(decoded.Channels.SelectMany(c => c)).All(p => Math.Abs(p.First - p.Second) < 0.0001));
        Check(Wav.Decode("not audio"u8.ToArray()) is null);
        Check(Wav.Decode(SoundSynth.Wav("ping"))?.FrameCount == SoundSynth.Samples("ping").Length);
    }),
    ("Game sound mixing follows the sound events", () =>
    {
        Check(GameSoundRecipe.All.Select(r => r.Output).ToHashSet().SetEquals(SoundSynth.Names));
        Check(GameSoundRecipe.Files.SequenceEqual(["ping.wav", "ping_attack.wav", "ping_attack_layer.wav", "ping_defense.wav",
                                                   "ping_enemy_ward.wav", "ping_need_ward.wav", "ping_warning.wav", "ping_warning_layer.wav"]));
        var ward = GameSoundRecipe.All.First(r => r.Output == "ping_enemy_ward");
        var quiet = ward.Mix(new Pcm(10, [[0.6f, -0.6f]]), null);
        Check(Math.Abs(quiet.Channels[0][0] - 0.3f) < 1e-6 && Math.Abs(quiet.Channels[0][1] + 0.3f) < 1e-6);
        var attack = GameSoundRecipe.All.First(r => r.Output == "ping_attack");
        var mixed = attack.Mix(new Pcm(100, [new float[5], new float[5]]), new Pcm(100, [Enumerable.Repeat(0.6f, 96).ToArray()]));
        Check(mixed.FrameCount == 10 + (int)(95 / 0.95) + 1);
        Check(mixed.Channels[1][9] == 0 && Math.Abs(mixed.Channels[1][10] - 0.5f) < 0.0001);
        var loud = attack.Mix(new Pcm(100, [[1f, 1f]]), null);
        Check(Math.Abs(loud.Channels[0].Max() - 0.98f) < 0.0001);
    }),
    ("Bundled game sounds match their sources", () =>
    {
        var resources = Path.Combine(Directory.GetCurrentDirectory(), "Resources");
        using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(resources, "asset-sources.json")));
        var files = manifest.RootElement.GetProperty("files").EnumerateArray()
            .Select(f => (Path: f.GetProperty("path").GetString()!, Sha: f.GetProperty("sha256").GetString()!)).ToList();
        Check(files.Select(f => Path.GetFileName(f.Path)).ToHashSet().SetEquals(GameSoundRecipe.Files));
        var sources = new Dictionary<string, Pcm?>();
        foreach (var (path, sha) in files)
        {
            var data = File.ReadAllBytes(Path.Combine(resources, path));
            Check(Convert.ToHexStringLower(SHA256.HashData(data)) == sha, path);
            sources[Path.GetFileName(path)] = Wav.Decode(data);
        }
        foreach (var (cue, seconds) in new[] { ("ping", 1.9987), ("ping_attack", 1.7894), ("ping_warning", 1.88), ("ping_enemy_ward", 2.9397) })
        {
            var recipe = GameSoundRecipe.All.First(r => r.Output == cue);
            var mixed = recipe.Mix(sources[recipe.File]!, recipe.Layer is null ? null : sources[recipe.Layer.File]);
            Check(Math.Abs((double)mixed.FrameCount / mixed.SampleRate - seconds) < 0.001, cue);
            Check(mixed.Channels.SelectMany(c => c).All(v => Math.Abs(v) <= 0.98f), cue);
        }
    }),
    ("Glyph outlines present for every ping", () =>
    {
        foreach (var kind in Pings.All)
        {
            var path = Glyphs.PathData(kind);
            Check((path.StartsWith("F0 M") || path.StartsWith("F1 M")) && path.Contains('Z'), kind.ToString());
        }
    }),
    ("Synthesised cues are short and click-free", () =>
    {
        foreach (var name in SoundSynth.Names)
        {
            var samples = SoundSynth.Samples(name);
            double seconds = (double)samples.Length / SoundSynth.SampleRate;
            Check(seconds > 0.3 && seconds < 1.0, name);
            float peak = samples.Max(Math.Abs);
            Check(peak > 0.8f && peak <= 0.83f, name);
            Check(Math.Abs(samples[0]) < 0.01f && Math.Abs(samples[^1]) < 0.01f, name);
            Check(SoundSynth.Wav(name).Length == 44 + samples.Length * 2, name);
        }
        Check(SoundSynth.Samples("unknown").Length == 0);
    }),
};

foreach (var (name, scenario) in scenarios)
{
    int before = failures;
    try { scenario(); }
    catch (Exception error) { failures++; Console.WriteLine($"FAIL {name}: {error}"); }
    Console.WriteLine($"{(failures == before ? "PASS" : "FAIL")} {name}");
}
Console.WriteLine($"{scenarios.Count} scenarios, {assertions} assertions, {failures} failures");
return failures == 0 ? 0 : 1;
