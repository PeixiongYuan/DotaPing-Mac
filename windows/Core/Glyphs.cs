using System.Reflection;
using System.Text.Json;

namespace DotaPing.Core;

/// <summary>
/// Icon outlines shared with the macOS app: WPF path markup in a unit square
/// with y pointing down, prefixed with the fill rule (F0 even-odd, F1 nonzero).
/// Regenerate with `DotaPing --export-glyphs windows/Core/glyphs.json` on macOS.
/// </summary>
public static class Glyphs
{
    static readonly Dictionary<string, string> data = Load();

    static Dictionary<string, string> Load()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DotaPing.glyphs.json")
            ?? throw new InvalidOperationException("glyphs.json is not embedded");
        return JsonSerializer.Deserialize<Dictionary<string, string>>(stream) ?? new();
    }

    public static string PathData(PingKind kind) => data.TryGetValue(kind.Id(), out var path) ? path : "";
}
