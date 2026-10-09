using System;
using System.IO;
using System.Text.Json;
using DotaPing.Core;

namespace DotaPing;

/// <summary>Preferences, saved as JSON in %APPDATA%\DotaPing\settings.json.</summary>
sealed class Settings
{
    public bool Enabled { get; set; } = true;
    public string Trigger { get; set; } = nameof(Core.Trigger.HoldCtrlAltShift);
    public int PlayerColor { get; set; }
    public double Volume { get; set; } = 0.55;
    public double Scale { get; set; } = 1;
    public string Sounds { get; set; } = "game";
    public string Language { get; set; } = "en";

    static readonly string FilePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DotaPing", "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath)) return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new();
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { }
        return new();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
