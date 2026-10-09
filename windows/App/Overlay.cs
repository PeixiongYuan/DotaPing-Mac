using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using DotaPing.Core;
using static DotaPing.NativeMethods;

namespace DotaPing;

/// <summary>Drawing helpers shared by the wheel, the landing effect and the settings window.</summary>
static class Art
{
    static readonly Dictionary<PingKind, Geometry> glyphs = new();
    public static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI");
    public static readonly Color IconIdle = Color.FromRgb(219, 222, 224);

    public static double Now => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;
    public static double Clamp01(double v) => Math.Min(1, Math.Max(0, v));
    public static double Ease(double v) { double t = Clamp01(v); return t * t * (3 - 2 * t); }
    public static double EaseOut(double v) { double t = Clamp01(v); return 1 - Math.Pow(1 - t, 3); }

    public static Color ToColor(Rgb rgb, double alpha = 1) => Color.FromArgb((byte)Math.Round(Clamp01(alpha) * 255),
        (byte)Math.Round(rgb.Red * 255), (byte)Math.Round(rgb.Green * 255), (byte)Math.Round(rgb.Blue * 255));
    public static Color Tint(this PingKind kind, PlayerColor player) => ToColor(kind.Color(player));
    public static Color WithAlpha(Color c, double alpha) => Color.FromArgb((byte)Math.Round(Clamp01(alpha) * c.A), c.R, c.G, c.B);
    public static Color Mix(Color a, Color b, double t)
    {
        t = Clamp01(t);
        byte L(byte x, byte y) => (byte)Math.Round(x + (y - x) * t);
        return Color.FromArgb(L(a.A, b.A), L(a.R, b.R), L(a.G, b.G), L(a.B, b.B));
    }
    public static SolidColorBrush Brush(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    public static Pen Pen(Color c, double thickness) { var p = new Pen(Brush(c), thickness); p.Freeze(); return p; }

    public static Geometry Glyph(PingKind kind)
    {
        if (!glyphs.TryGetValue(kind, out var geometry))
        {
            geometry = Geometry.Parse(Glyphs.PathData(kind));
            if (geometry.CanFreeze) geometry.Freeze();
            glyphs[kind] = geometry;
        }
        return geometry;
    }

    /// <summary>Glyph outlines live in a unit square; scale them into the rectangle.</summary>
    public static void DrawGlyph(DrawingContext dc, PingKind kind, Rect rect, Color color)
    {
        dc.PushTransform(new MatrixTransform(rect.Width, 0, 0, rect.Height, rect.X, rect.Y));
        dc.DrawGeometry(Brush(color), null, Glyph(kind));
        dc.Pop();
    }

    /// <summary>Point at a mathematical angle (degrees, counter-clockwise from +x) on screen, where y points down.</summary>
    public static Point Polar(Point c, double radius, double degrees)
    {
        double r = degrees * Math.PI / 180;
        return new Point(c.X + radius * Math.Cos(r), c.Y - radius * Math.Sin(r));
    }

    public static Geometry Sector(Point c, double inner, double outer, double fromDegrees, double toDegrees)
    {
        var g = new StreamGeometry();
        using (var ctx = g.Open())
        {
            bool large = toDegrees - fromDegrees > 180;
            ctx.BeginFigure(Polar(c, outer, fromDegrees), true, true);
            ctx.ArcTo(Polar(c, outer, toDegrees), new Size(outer, outer), 0, large, SweepDirection.Counterclockwise, true, false);
            ctx.LineTo(Polar(c, inner, toDegrees), true, false);
            ctx.ArcTo(Polar(c, inner, fromDegrees), new Size(inner, inner), 0, large, SweepDirection.Clockwise, true, false);
        }
        g.Freeze();
        return g;
    }

    public static Geometry Arc(Point c, double radius, double fromDegrees, double toDegrees)
    {
        var g = new StreamGeometry();
        using (var ctx = g.Open())
        {
            ctx.BeginFigure(Polar(c, radius, fromDegrees), false, false);
            ctx.ArcTo(Polar(c, radius, toDegrees), new Size(radius, radius), 0, toDegrees - fromDegrees > 180, SweepDirection.Counterclockwise, true, false);
        }
        g.Freeze();
        return g;
    }

    public static FormattedText Text(string text, double size, Color color, FontWeight weight, double pixelsPerDip) =>
        new(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(UiFont, FontStyles.Normal, weight, FontStretches.Normal), size, Brush(color), pixelsPerDip);

    public static void DrawCentered(DrawingContext dc, FormattedText text, Point center) =>
        dc.DrawText(text, new Point(center.X - text.Width / 2, center.Y - text.Height / 2));

    public static RadialGradientBrush Radial(Point center, double rx, double ry, params (Color Color, double Offset)[] stops)
    {
        var brush = new RadialGradientBrush { MappingMode = BrushMappingMode.Absolute, Center = center, GradientOrigin = center, RadiusX = rx, RadiusY = ry };
        foreach (var (color, offset) in stops) brush.GradientStops.Add(new GradientStop(color, offset));
        brush.Freeze();
        return brush;
    }
}

/// <summary>
/// Dark wheel with one slot per ping. The hovered slot is tinted in the ping's
/// colour, and a pointer on the centre ring shows the direction.
/// </summary>
sealed class WheelVisual : FrameworkElement
{
    public PlayerColor Player { get; set; } = PlayerColor.Blue;
    public Language UiLanguage { get; set; } = Core.Language.English;
    public PingKind Selected { get; private set; } = PingKind.Regular;
    public double? Direction { get; private set; }
    readonly double[] weights = new double[Pings.Wheel.Count], origins = new double[Pings.Wheel.Count];
    double transitionStart;
    double? openingStart;
    bool animating;

    public void Open() { openingStart = Art.Now; StartAnimating(); }

    public void SetSelection(PingKind kind, double? angle, bool animated = true)
    {
        Direction = kind == PingKind.Regular ? null : angle;
        if (!animated)
        {
            Selected = kind;
            for (int i = 0; i < weights.Length; i++) weights[i] = origins[i] = Pings.Wheel[i] == kind ? 1 : 0;
            transitionStart = 0; StopAnimating(); InvalidateVisual();
            return;
        }
        UpdateAnimation(Art.Now);
        if (kind != Selected)
        {
            Array.Copy(weights, origins, weights.Length);
            Selected = kind; transitionStart = Art.Now;
            StartAnimating();
        }
        InvalidateVisual();
    }

    public void Stop() => StopAnimating();

    /// <summary>Diagnostics sample the same interpolation the live animation uses.</summary>
    public void SampleTransition(double elapsed) { UpdateAnimation(transitionStart + elapsed); openingStart = null; InvalidateVisual(); }

    void StartAnimating() { if (animating) return; animating = true; CompositionTarget.Rendering += OnFrame; }
    void StopAnimating() { if (!animating) return; animating = false; CompositionTarget.Rendering -= OnFrame; }

    void OnFrame(object? sender, EventArgs e)
    {
        double now = Art.Now;
        UpdateAnimation(now); InvalidateVisual();
        if (now - transitionStart >= 0.12 && (openingStart is null || now - openingStart >= 0.11)) { StopAnimating(); openingStart = null; }
    }

    void UpdateAnimation(double now)
    {
        if (transitionStart <= 0) return;
        double progress = Art.Ease((now - transitionStart) / 0.12);
        for (int i = 0; i < weights.Length; i++)
            weights[i] = origins[i] + ((Pings.Wheel[i] == Selected ? 1.0 : 0.0) - origins[i]) * progress;
    }

    protected override void OnRender(DrawingContext dc)
    {
        double width = ActualWidth, s = width / 300, ppd = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var c = new Point(width / 2, ActualHeight / 2);
        int pushes = 0;
        if (openingStart is { } start)
        {
            // Fade in while settling from slightly larger, about the wheel centre.
            double p = Art.Ease((Art.Now - start) / 0.11), grow = 1.06 - 0.06 * p;
            dc.PushOpacity(p); dc.PushTransform(new ScaleTransform(grow, grow, c.X, c.Y)); pushes = 2;
        }
        double outer = WheelGeometry.OuterRadius * s, inner = WheelGeometry.CenterRadius * s;
        dc.DrawEllipse(Art.Brush(Color.FromArgb(219, 14, 15, 17)), Art.Pen(Color.FromArgb(31, 255, 255, 255), 1 * s), c, outer, outer);

        int n = Pings.Wheel.Count;
        double step = 360.0 / n, half = step / 2;
        for (int i = 0; i < n; i++)
        {
            var kind = Pings.Wheel[i];
            double degrees = 90 - i * step, weight = weights[i];
            var tint = kind.Tint(Player);
            if (weight > 0.001)
            {
                dc.DrawGeometry(Art.Brush(Art.WithAlpha(tint, 0.20 * weight)), null, Art.Sector(c, inner, outer - 0.5 * s, degrees - half, degrees + half));
                dc.DrawGeometry(null, Art.Pen(Art.WithAlpha(tint, weight), 2.6 * s), Art.Arc(c, outer - 1.8 * s, degrees - half, degrees + half));
            }
            dc.DrawLine(Art.Pen(Color.FromArgb(20, 255, 255, 255), 0.6 * s), Art.Polar(c, inner, degrees + half), Art.Polar(c, outer, degrees + half));
            var p = Art.Polar(c, WheelGeometry.IconRadius * s, degrees);
            double side = (24 + 6 * weight) * s;
            var rect = new Rect(p.X - side / 2, p.Y - side / 2, side, side);
            // Pings with a fixed colour keep a hint of it, so the two wards differ at a glance.
            var idle = kind.FixedColor() is null ? Art.WithAlpha(Art.IconIdle, 0.78) : Art.WithAlpha(Art.Mix(Art.IconIdle, tint, 0.5), 0.85);
            Art.DrawGlyph(dc, kind, Rect.Offset(rect, 0, 0.6 * s), Color.FromArgb(150, 0, 0, 0));
            Art.DrawGlyph(dc, kind, rect, Art.Mix(idle, tint, weight));
        }

        dc.DrawEllipse(Art.Brush(Color.FromArgb(245, 9, 10, 11)), Art.Pen(Color.FromArgb(36, 255, 255, 255), 1 * s), c, inner, inner);
        if (Direction is { } angle)
        {
            double theta = 90 - angle * 180 / Math.PI, spread = 0.09 * 180 / Math.PI;
            var pointer = new StreamGeometry();
            using (var ctx = pointer.Open())
            {
                ctx.BeginFigure(Art.Polar(c, inner - 1 * s, theta + spread), true, true);
                ctx.LineTo(Art.Polar(c, inner + 7 * s, theta), true, false);
                ctx.LineTo(Art.Polar(c, inner - 1 * s, theta - spread), true, false);
            }
            pointer.Freeze();
            dc.DrawGeometry(Art.Brush(Selected.Tint(Player)), null, pointer);
        }
        if (Selected == PingKind.Regular)
        {
            Art.DrawGlyph(dc, PingKind.Regular, new Rect(c.X - 10 * s, c.Y - 24 * s, 20 * s, 20 * s), PingKind.Regular.Tint(Player));
            Art.DrawCentered(dc, Art.Text(PingKind.Regular.Title(UiLanguage), 13 * s, Colors.White, FontWeights.Medium, ppd), new Point(c.X, c.Y + 13 * s));
        }
        else
        {
            Art.DrawCentered(dc, Art.Text(Selected.Title(UiLanguage), 14 * s, Colors.White, FontWeights.Medium, ppd), c);
        }
        for (; pushes > 0; pushes--) dc.Pop();
    }
}

/// <summary>
/// The landing effect, after the game's minimap ping: a ring closes onto the
/// spot and throbs, wide pulses spread out, the icon rises over a ground glow
/// and the team chat line appears above it.
/// </summary>
sealed class EffectVisual : FrameworkElement
{
    /// <summary>The ground point sits this far below the element centre (before scaling).</summary>
    public const double GroundOffset = 22;
    public PingKind Kind { get; }
    public double Duration => Kind.EffectDuration();
    public double Elapsed { get; private set; }
    public event Action? Finished;
    readonly Color tint;
    readonly Language language;
    readonly double effectScale;
    double started;
    bool running;

    public EffectVisual(PingKind kind, PlayerColor player, Language language, double scale)
    {
        Kind = kind; tint = kind.Tint(player); this.language = language; effectScale = scale;
        Elapsed = Duration; IsHitTestVisible = false;
    }

    public void Start()
    {
        started = Art.Now; Seek(0);
        if (!running) { running = true; CompositionTarget.Rendering += OnFrame; }
    }

    public void Seek(double time) { Elapsed = time; InvalidateVisual(); }

    public void Stop()
    {
        if (running) { running = false; CompositionTarget.Rendering -= OnFrame; }
        Elapsed = Duration; InvalidateVisual();
    }

    void OnFrame(object? sender, EventArgs e)
    {
        Seek(Art.Now - started);
        if (Elapsed >= Duration) { Stop(); Finished?.Invoke(); }
    }

    protected override void OnRender(DrawingContext dc)
    {
        double t = Elapsed, d = Duration;
        if (t < 0 || t >= d) return;
        double s = effectScale, ppd = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var ground = new Point(ActualWidth / 2, ActualHeight / 2 + GroundOffset * s);
        double alpha = Art.Ease(t / 0.07) * (1 - Art.Ease((t - (d - 0.9)) / 0.9));
        dc.PushOpacity(alpha);
        // Ground glow under the marker.
        dc.DrawEllipse(Art.Radial(ground, 46 * s, 23 * s, (Art.WithAlpha(tint, 0.30), 0), (Art.WithAlpha(tint, 0.12), 0.55), (Art.WithAlpha(tint, 0), 1)),
            null, ground, 46 * s, 23 * s);
        // A ring collapses from far out onto the spot in 0.3 s, then throbs.
        double settle = Art.EaseOut(t / 0.3), throb = t > 0.3 ? 1.4 * Math.Sin((t - 0.3) * 2 * Math.PI * 1.5) : 0;
        double radius = (92 - 71 * settle + throb) * s;
        dc.DrawEllipse(null, Art.Pen(Art.WithAlpha(tint, 0.18), 5 * s), ground, radius, radius / 2);
        dc.DrawEllipse(null, Art.Pen(Art.WithAlpha(tint, 0.35 + 0.6 * settle), (1.2 + 1.2 * settle) * s), ground, radius, radius / 2);
        // Wide, faint pulses spread outwards once the marker lands.
        foreach (var (index, delay) in new[] { (0, 0.28), (1, 0.95) })
        {
            if (t <= delay) continue;
            double progress = (t - delay) / 1.5;
            if (progress >= 1) continue;
            double r = (21 + 64 * Art.EaseOut(progress)) * s;
            dc.DrawEllipse(null, Art.Pen(Art.WithAlpha(tint, Math.Pow(1 - progress, 1.6) * (index == 0 ? 0.75 : 0.45)), (index == 0 ? 1.6 : 1.0) * s), ground, r, r / 2);
        }
        // A brief flash as the ring lands.
        if (t > 0.24 && t < 1.1)
        {
            double flash = 1 - Art.Ease((t - 0.24) / 0.86);
            dc.DrawEllipse(Art.Radial(ground, 28 * s, 14 * s, (Art.WithAlpha(tint, 0.55 * flash), 0), (Art.WithAlpha(tint, 0), 1)), null, ground, 28 * s, 14 * s);
        }
        // The icon pops up, overshoots slightly and bobs.
        double pop = t < 0.14 ? 0.45 + 0.67 * Art.Ease(t / 0.14) : t < 0.28 ? 1.12 - 0.12 * Art.Ease((t - 0.14) / 0.14) : 1;
        double lift = (10 * Art.Ease(t / 0.3) + 2.2 * Math.Sin(Math.Min(t, d - 0.4) * 2 * Math.PI * 0.7)) * s;
        double side = 40 * pop * s;
        var rect = new Rect(ground.X - side / 2, ground.Y - 9 * s - lift - side, side, side);
        var middle = new Point(rect.X + side / 2, rect.Y + side / 2);
        dc.DrawEllipse(Art.Radial(middle, side * 0.75, side * 0.75, (Art.WithAlpha(tint, 0.35), 0), (Art.WithAlpha(tint, 0), 1)), null, middle, side * 0.75, side * 0.75);
        Art.DrawGlyph(dc, Kind, Rect.Offset(rect, 0, 1 * s), Color.FromArgb(150, 0, 0, 0));
        Art.DrawGlyph(dc, Kind, rect, tint);
        // The team chat line for this ping, above the icon.
        if (Kind.Chat(language) is { } chat)
        {
            double appear = Art.Ease((t - 0.12) / 0.2);
            var label = Art.Text(chat, 11 * s, Color.FromArgb(242, 255, 255, 255), FontWeights.SemiBold, ppd);
            var shadow = Art.Text(chat, 11 * s, Color.FromArgb(230, 0, 0, 0), FontWeights.SemiBold, ppd);
            var origin = new Point(ground.X - label.Width / 2, rect.Top - 2 * s - label.Height + 3 * (1 - appear) * s);
            dc.PushOpacity(appear);
            dc.DrawText(shadow, new Point(origin.X, origin.Y + 0.8 * s));
            dc.DrawText(label, origin);
            dc.Pop();
        }
        dc.Pop();
    }
}

/// <summary>Borderless, transparent, click-through, always-on-top window that never takes focus.</summary>
sealed class OverlayWindow : Window
{
    public OverlayWindow(FrameworkElement content)
    {
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
        IsHitTestVisible = false; Focusable = false; SizeToContent = SizeToContent.Manual;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Content = content;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        long style = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED));
    }

    /// <summary>Shows the window at a rectangle in physical pixels.</summary>
    public void ShowAt(int x, int y, int width, int height)
    {
        var hwnd = new WindowInteropHelper(this).EnsureHandle();
        // Step onto the target monitor first, so a DPI change there cannot resize the final rectangle.
        SetWindowPos(hwnd, HWND_TOPMOST, x, y, 1, 1, SWP_NOACTIVATE);
        SetWindowPos(hwnd, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
        Show();
        SetWindowPos(hwnd, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
}

/// <summary>Owns the wheel and the landing effects. Positions are physical pixels with y pointing down.</summary>
sealed class OverlayController
{
    OverlayWindow? wheelWindow;
    WheelVisual? wheel;
    readonly List<(OverlayWindow Window, EffectVisual Effect)> effects = [];

    /// <summary>Returns the wheel centre, moved inwards near a screen edge.</summary>
    public Point2 ShowWheel(Point2 anchor, double scale, PlayerColor player, Language language)
    {
        HideWheel(false);
        var (work, dpi) = Screens.At(anchor.X, anchor.Y);
        int side = (int)Math.Round(300 * scale * dpi);
        var center = WheelGeometry.ClampedCenter(anchor, work, side / 2.0);
        wheel = new WheelVisual { Player = player, UiLanguage = language };
        wheelWindow = new OverlayWindow(wheel);
        wheelWindow.ShowAt((int)Math.Round(center.X - side / 2.0), (int)Math.Round(center.Y - side / 2.0), side, side);
        wheel.Open();
        return center;
    }

    public void Select(PingKind kind, double? angle) => wheel?.SetSelection(kind, angle);

    public void HideWheel(bool animated = true)
    {
        if (wheelWindow is not { } window) return;
        wheel?.Stop(); wheelWindow = null; wheel = null;
        if (!animated) { window.Close(); return; }
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(90));
        fade.Completed += (_, _) => window.Close();
        window.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    public void ShowPing(PingKind kind, Point2 anchor, double scale, PlayerColor player, Language language)
    {
        if (effects.Count >= 16) Close(effects[0]);
        var (_, dpi) = Screens.At(anchor.X, anchor.Y);
        int side = (int)Math.Round(240 * scale * dpi);
        // The ground point, below the window centre, is exactly the anchor.
        double centerY = anchor.Y - EffectVisual.GroundOffset * scale * dpi;
        var effect = new EffectVisual(kind, player, language, scale);
        var window = new OverlayWindow(effect);
        var entry = (window, effect);
        effects.Add(entry);
        effect.Finished += () => Close(entry);
        window.ShowAt((int)Math.Round(anchor.X - side / 2.0), (int)Math.Round(centerY - side / 2.0), side, side);
        effect.Start();
    }

    void Close((OverlayWindow Window, EffectVisual Effect) entry)
    {
        if (!effects.Remove(entry)) return;
        entry.Effect.Stop(); entry.Window.Close();
    }

    public void Clear()
    {
        HideWheel(false);
        foreach (var entry in effects.ToArray()) Close(entry);
    }
}
