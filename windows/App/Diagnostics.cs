using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DotaPing.Core;
using Trigger = DotaPing.Core.Trigger;

namespace DotaPing;

/// <summary>
/// Command-line checks: --check-assets, --visual-check DIR, --input-self-test.
/// They render with the app's own code and never touch the user's settings.
/// </summary>
static class Diagnostics
{
    public static int Run(Application app, string[] args)
    {
        app.Startup += async (_, _) =>
        {
            int code;
            try
            {
                code = args[0] switch
                {
                    "--check-assets" => CheckAssets(),
                    "--visual-check" when args.Length > 1 => await VisualCheck(app, args[1]),
                    "--input-self-test" => await InputSelfTest.Run(app.Dispatcher),
                    _ => Usage(),
                };
            }
            catch (Exception error) { Console.WriteLine(error); code = 1; }
            Console.Out.Flush();
            app.Shutdown(code);
        };
        return app.Run();
    }

    static int Usage()
    {
        Console.WriteLine("DotaPing [--check-assets | --visual-check DIR | --input-self-test]");
        return 2;
    }

    static int CheckAssets()
    {
        var failures = new List<string>();
        foreach (var kind in Pings.All)
        {
            var bounds = Art.Glyph(kind).Bounds;
            if (bounds.IsEmpty || bounds.Left < -0.01 || bounds.Top < -0.01 || bounds.Right > 1.01 || bounds.Bottom > 1.01) failures.Add($"Glyph out of bounds: {kind}");
        }
        var game = SoundPlayer.MixGameCues();
        foreach (var name in SoundSynth.Names)
        {
            if (!game.TryGetValue(name, out var bytes) || Wav.Decode(bytes) is not { } pcm) { failures.Add($"Game sound missing: {name}"); continue; }
            var synth = Wav.Decode(SoundSynth.Wav(name));
            Console.WriteLine($"{name}: game {(double)pcm.FrameCount / pcm.SampleRate:F2}s, synthesized {(double)(synth?.FrameCount ?? 0) / SoundSynth.SampleRate:F2}s");
        }
        foreach (var failure in failures) Console.WriteLine(failure);
        if (failures.Count > 0) return 1;
        Console.WriteLine($"All {Pings.All.Count} glyphs parse; all {game.Count} game and {SoundSynth.Names.Count} synthesized cues decode.");
        return 0;
    }

    static readonly Color Backdrop = Color.FromRgb(15, 18, 20);

    static RenderTargetBitmap Render(FrameworkElement element, double width, double height, double scale, Color? background = null)
    {
        element.Measure(new Size(width, height));
        element.Arrange(new Rect(0, 0, width, height));
        element.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Round(width * scale), (int)Math.Round(height * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        if (background is { } color)
        {
            var fill = new DrawingVisual();
            using (var dc = fill.RenderOpen()) dc.DrawRectangle(Art.Brush(color), null, new Rect(0, 0, width, height));
            bitmap.Render(fill);
        }
        bitmap.Render(element);
        return bitmap;
    }

    static void Save(BitmapSource bitmap, string path)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(path);
        encoder.Save(file);
    }

    static byte[] Pixels(BitmapSource bitmap)
    {
        int stride = bitmap.PixelWidth * 4;
        var data = new byte[stride * bitmap.PixelHeight];
        bitmap.CopyPixels(data, stride, 0);
        return data;
    }

    static Canvas Sheet(double width, double height) => new() { Width = width, Height = height, Background = Art.Brush(Backdrop) };

    static void Place(Canvas canvas, FrameworkElement element, double x, double y, double width, double height)
    {
        element.Width = width; element.Height = height;
        Canvas.SetLeft(element, x); Canvas.SetTop(element, y);
        canvas.Children.Add(element);
    }

    static async Task<int> VisualCheck(Application app, string directory)
    {
        Directory.CreateDirectory(directory);
        var report = new List<string>();

        // Each animation changes over time, clears completely when it ends and disappears when stopped.
        foreach (var kind in Pings.All)
        {
            var effect = new EffectVisual(kind, PlayerColor.Blue, Language.English, 1);
            byte[] Frame(double t) { effect.Seek(t); return Pixels(Render(effect, 240, 240, 1)); }
            var empty = Pixels(Render(new Canvas(), 240, 240, 1));
            byte[] early = Frame(0.25), late = Frame(effect.Duration - 0.5), finished = Frame(effect.Duration + 0.01);
            effect.Seek(0.6); effect.Stop();
            var stopped = Pixels(Render(effect, 240, 240, 1));
            if (early.SequenceEqual(empty) || early.SequenceEqual(late) || late.SequenceEqual(empty) || !finished.SequenceEqual(empty) || !stopped.SequenceEqual(empty))
                throw new InvalidOperationException($"Animation/stop check failed: {kind}");
        }
        report.Add($"PASS {Pings.All.Count} effects: visible animation changes, finish clean and stop immediately ({Pings.All.Count * 4} pixel comparisons).");

        var order = Pings.Wheel.Append(PingKind.Regular).ToList();
        int rows = (order.Count + 2) / 3;
        foreach (var scale in new[] { 0.75, 1.0, 1.5 })
        {
            double side = 300 * scale, gap = 16;
            var sheet = Sheet(side * 3 + gap * 4, side * rows + gap * (rows + 1));
            for (int i = 0; i < order.Count; i++)
            {
                var wheel = new WheelVisual();
                double? angle = order[i] == PingKind.Regular ? null : Pings.Wheel.ToList().IndexOf(order[i]) * WheelGeometry.Sector;
                wheel.SetSelection(order[i], angle, animated: false);
                Place(sheet, wheel, gap + i % 3 * (side + gap), gap + i / 3 * (side + gap), side, side);
            }
            Save(Render(sheet, sheet.Width, sheet.Height, 2), Path.Combine(directory, $"wheel-{(int)(scale * 100)}-2x.png"));
        }
        var single = new WheelVisual { Player = PlayerColor.Pink };
        single.SetSelection(PingKind.Attack, WheelGeometry.Sector, animated: false);
        Save(Render(single, 300, 300, 1, Backdrop), Path.Combine(directory, "wheel-100-1x.png"));

        double[] times = [0.06, 0.2, 0.45, 1.2, 1.8, 2.6];
        var phases = Sheet(200 * times.Length, 200 * order.Count);
        for (int row = 0; row < order.Count; row++)
            for (int column = 0; column < times.Length; column++)
            {
                var effect = new EffectVisual(order[row], PlayerColor.Blue, Language.English, 1);
                effect.Seek(times[column]);
                Place(phases, effect, column * 200, row * 200, 200, 200);
            }
        Save(Render(phases, phases.Width, phases.Height, 2), Path.Combine(directory, "effect-phases-2x.png"));

        var colors = Sheet(200 * 5, 200 * 2);
        foreach (var color in PlayerColors.All)
        {
            var effect = new EffectVisual(PingKind.Regular, color, Language.English, 1);
            effect.Seek(0.45);
            Place(colors, effect, (int)color % 5 * 200, color.IsRadiant() ? 0 : 200, 200, 200);
        }
        Save(Render(colors, colors.Width, colors.Height, 2), Path.Combine(directory, "player-colors-2x.png"));

        foreach (var language in new[] { Language.English, Language.Chinese })
        {
            string suffix = language == Language.English ? "" : "-zh";
            var wheel = new WheelVisual { UiLanguage = language };
            wheel.SetSelection(PingKind.EnemyWard, Pings.Wheel.ToList().IndexOf(PingKind.EnemyWard) * WheelGeometry.Sector, animated: false);
            Save(Render(wheel, 300, 300, 2, Backdrop), Path.Combine(directory, $"readme-wheel{suffix}.png"));
            var row = Sheet(160 * 5, 170);
            var kinds = new[] { PingKind.Regular, PingKind.Caution, PingKind.Attack, PingKind.EnemyWard, PingKind.FriendlyWard };
            for (int i = 0; i < kinds.Length; i++)
            {
                var effect = new EffectVisual(kinds[i], PlayerColor.Blue, language, 1);
                effect.Seek(0.7);
                Place(row, effect, i * 160, 0, 160, 170);
            }
            Save(Render(row, row.Width, row.Height, 2), Path.Combine(directory, $"readme-pings{suffix}.png"));
        }

        // The settings window in each theme and language, with in-memory settings only.
        var shots = new (string Name, ThemeMode Theme, Language Language, Trigger Trigger)[]
        {
            ("window-light", ThemeMode.Light, Language.English, Trigger.HoldCtrlAltShift),
            ("window-dark", ThemeMode.Dark, Language.English, Trigger.HoldCtrlAltShift),
            ("window-alt-click", ThemeMode.Dark, Language.English, Trigger.AltClick),
            ("window-zh", ThemeMode.Dark, Language.Chinese, Trigger.HoldCtrlAltShift),
        };
        foreach (var (name, theme, language, trigger) in shots)
        {
            app.ThemeMode = theme;
            var settings = new Settings { Enabled = false, Language = language.Code(), Trigger = trigger.ToString() };
            var controller = new AppController(app.Dispatcher, settings, persist: false);
            var window = new SettingsWindow(controller) { Left = -32000, Top = 0, ShowActivated = false, ShowInTaskbar = false };
            window.Show();
            await Task.Delay(400);
            window.UpdateLayout();
            // The scroll viewer lays its content out at full height; draw all of it, not just the visible part.
            var content = (FrameworkElement)((ScrollViewer)window.Content).Content;
            var margin = content.Margin;
            double width = content.ActualWidth + margin.Left + margin.Right, height = content.ActualHeight + margin.Top + margin.Bottom;
            var background = theme == ThemeMode.Light ? Color.FromRgb(243, 243, 243) : Color.FromRgb(32, 32, 32);
            var bitmap = new RenderTargetBitmap((int)(width * 2), (int)(height * 2), 192, 192, PixelFormats.Pbgra32);
            var page = new DrawingVisual();
            using (var dc = page.RenderOpen())
            {
                dc.DrawRectangle(Art.Brush(background), null, new Rect(0, 0, width, height));
                dc.DrawRectangle(new VisualBrush(content) { Stretch = Stretch.None }, null, new Rect(margin.Left, margin.Top, content.ActualWidth, content.ActualHeight));
            }
            bitmap.Render(page);
            Save(bitmap, Path.Combine(directory, name + ".png"));
            window.Hide();
        }
        app.ThemeMode = ThemeMode.System;

        report.Add($"Snapshots saved: {directory}");
        File.WriteAllLines(Path.Combine(directory, "report.txt"), report);
        foreach (var line in report) Console.WriteLine(line);
        return 0;
    }
}
