namespace DotaPing.Core;

/// <summary>Interface language, chosen in the app (English by default).</summary>
public enum Language { English, Chinese }

public static class Languages
{
    public static string Pick(this Language language, string english, string chinese) => language == Language.English ? english : chinese;
    /// <summary>Each language is listed under its own name.</summary>
    public static string Name(this Language language) => language == Language.English ? "English" : "简体中文";
    public static string Code(this Language language) => language == Language.English ? "en" : "zh-Hans";
    public static Language FromCode(string? code) => code == "zh-Hans" ? Language.Chinese : Language.English;
}

public readonly record struct Rgb(double Red, double Green, double Blue)
{
    public static Rgb Of(int red, int green, int blue) => new(red / 255.0, green / 255.0, blue / 255.0);
}

/// <summary>The default entries of Dota 2's ping wheel (scripts/ping_wheel.vdata), plus the "Question Mark?" seasonal ping.</summary>
public enum PingKind { Caution, Attack, OnMyWay, Warning, Assist, FriendlyWard, Defend, EnemyWard, Question, Regular }

public static class Pings
{
    /// <summary>Clockwise from north. The centre is the ordinary ping.</summary>
    public static readonly IReadOnlyList<PingKind> Wheel =
        [PingKind.Caution, PingKind.Attack, PingKind.OnMyWay, PingKind.Warning, PingKind.Assist,
         PingKind.FriendlyWard, PingKind.Defend, PingKind.EnemyWard, PingKind.Question];
    public static readonly IReadOnlyList<PingKind> All = Enum.GetValues<PingKind>();

    /// <summary>Same identifiers as the macOS PingKind raw values.</summary>
    public static string Id(this PingKind kind) => kind switch
    {
        PingKind.OnMyWay => "onMyWay",
        PingKind.FriendlyWard => "friendlyWard",
        PingKind.EnemyWard => "enemyWard",
        _ => kind.ToString().ToLowerInvariant(),
    };

    /// <summary>Wheel label: the game's dota_pingwheel_* string.</summary>
    public static string Title(this PingKind kind, Language l) => kind switch
    {
        PingKind.Caution => l.Pick("Caution", "小心"),
        PingKind.Attack => l.Pick("Attack", "进攻"),
        PingKind.OnMyWay => l.Pick("On My Way", "我马上到"),
        PingKind.Warning => l.Pick("Warning", "警告"),
        PingKind.Assist => l.Pick("Assist", "援助"),
        PingKind.FriendlyWard => l.Pick("Friendly Ward", "友方守卫"),
        PingKind.Defend => l.Pick("Defend", "防守"),
        PingKind.EnemyWard => l.Pick("Enemy Ward", "敌方守卫"),
        PingKind.Question => l.Pick("Question Mark", "问号"),
        _ => l.Pick("Ping", "信号"),
    };

    /// <summary>Team chat line (DOTA_Chat_Ping_Msg_*); the ordinary, warning and seasonal pings post none.</summary>
    public static string? Chat(this PingKind kind, Language l) => kind switch
    {
        PingKind.Caution => l.Pick("Caution", "小心"),
        PingKind.Attack => l.Pick("Attack", "攻击"),
        PingKind.OnMyWay => l.Pick("On My Way", "前往"),
        PingKind.Assist => l.Pick("Assist", "援助"),
        PingKind.FriendlyWard => l.Pick("We Need Vision", "我们需要视野"),
        PingKind.Defend => l.Pick("Defend", "防守"),
        PingKind.EnemyWard => l.Pick("Enemy Has Vision", "敌人有视野"),
        _ => null,
    };

    /// <summary>One cue per game sound event; Question Mark has none of its own and uses the ordinary one.</summary>
    public static string SoundName(this PingKind kind) => kind switch
    {
        PingKind.Regular or PingKind.Assist or PingKind.Question => "ping",
        PingKind.Warning or PingKind.Caution => "ping_warning",
        PingKind.OnMyWay => "ping_waypoint",
        PingKind.Attack => "ping_attack",
        PingKind.EnemyWard => "ping_enemy_ward",
        PingKind.FriendlyWard => "ping_friendly_ward",
        _ => "ping_defense",
    };

    /// <summary>Fixed effect colour from ping_wheel.vdata; null means the pinging player's colour.</summary>
    public static Rgb? FixedColor(this PingKind kind) => kind switch
    {
        PingKind.Caution => Rgb.Of(255, 155, 14),
        PingKind.EnemyWard => Rgb.Of(225, 51, 51),
        PingKind.FriendlyWard => Rgb.Of(10, 255, 10),
        _ => null,
    };

    public static Rgb Color(this PingKind kind, PlayerColor player) => kind.FixedColor() ?? player.Rgb();

    /// <summary>Seconds the desktop effect stays visible.</summary>
    public static double EffectDuration(this PingKind kind) => kind == PingKind.Regular ? 2.0 : 3.0;
}

/// <summary>The ten in-game player slot colours.</summary>
public enum PlayerColor { Blue, Teal, Purple, Yellow, Orange, Pink, Olive, LightBlue, DarkGreen, Brown }

public static class PlayerColors
{
    static readonly string[] English = ["Blue", "Teal", "Purple", "Yellow", "Orange", "Pink", "Olive", "Light Blue", "Dark Green", "Brown"];
    static readonly string[] Chinese = ["蓝", "青绿", "紫", "黄", "橙", "粉", "橄榄绿", "浅蓝", "深绿", "棕"];
    public static readonly IReadOnlyList<PlayerColor> All = Enum.GetValues<PlayerColor>();

    public static bool IsRadiant(this PlayerColor color) => (int)color < 5;
    public static string Name(this PlayerColor color, Language l) => (l == Language.English ? English : Chinese)[(int)color];
    public static string Title(this PlayerColor color, Language l) => l == Language.English
        ? $"{(color.IsRadiant() ? "Radiant" : "Dire")} {(int)color % 5 + 1} · {color.Name(l)}"
        : $"{(color.IsRadiant() ? "天辉" : "夜魇")} {(int)color % 5 + 1} 号位 · {color.Name(l)}";

    public static Rgb Rgb(this PlayerColor color) => color switch
    {
        PlayerColor.Blue => Core.Rgb.Of(51, 117, 255),
        PlayerColor.Teal => Core.Rgb.Of(102, 255, 191),
        PlayerColor.Purple => Core.Rgb.Of(191, 0, 191),
        PlayerColor.Yellow => Core.Rgb.Of(243, 240, 11),
        PlayerColor.Orange => Core.Rgb.Of(255, 107, 0),
        PlayerColor.Pink => Core.Rgb.Of(254, 134, 194),
        PlayerColor.Olive => Core.Rgb.Of(161, 180, 71),
        PlayerColor.LightBlue => Core.Rgb.Of(101, 217, 247),
        PlayerColor.DarkGreen => Core.Rgb.Of(0, 131, 33),
        _ => Core.Rgb.Of(164, 105, 0),
    };
}

[Flags]
public enum Modifiers { None = 0, Control = 1, Alt = 2, Win = 4, Shift = 8 }

/// <summary>
/// A held modifier chord (no mouse button needed, comfortable on a touchpad)
/// or the game's own gesture: Alt plus the left button. The Windows key is
/// avoided because releasing it opens the Start menu.
/// </summary>
public enum Trigger { HoldCtrlAltShift, HoldCtrlAlt, AltClick }

public static class Triggers
{
    public static readonly IReadOnlyList<Trigger> All = Enum.GetValues<Trigger>();

    public static bool UsesPrimaryButton(this Trigger trigger) => trigger == Trigger.AltClick;

    public static Modifiers Modifiers(this Trigger trigger) => trigger switch
    {
        Trigger.HoldCtrlAltShift => Core.Modifiers.Control | Core.Modifiers.Alt | Core.Modifiers.Shift,
        Trigger.HoldCtrlAlt => Core.Modifiers.Control | Core.Modifiers.Alt,
        _ => Core.Modifiers.Alt,
    };

    /// <summary>With the left-button trigger, adding Ctrl sends the game's warning ping.</summary>
    public static Modifiers? WarningModifiers(this Trigger trigger) =>
        trigger.UsesPrimaryButton() ? Core.Modifiers.Control | Core.Modifiers.Alt : null;

    public static string Keys(this Trigger trigger) => trigger switch
    {
        Trigger.HoldCtrlAltShift => "Ctrl+Alt+Shift",
        Trigger.HoldCtrlAlt => "Ctrl+Alt",
        _ => "Alt",
    };

    public static string Title(this Trigger trigger, Language l) => trigger.UsesPrimaryButton()
        ? l.Pick("Alt + Left Click (as in game)", "Alt + 左键（与游戏相同）")
        : l.Pick($"Hold {trigger.Keys()}", $"按住 {trigger.Keys()}");

    public static string Ready(this Trigger trigger, Language l) => trigger.UsesPrimaryButton()
        ? l.Pick("On. Alt-click to ping; hold and drag to open the wheel.", "已开启。Alt 点按发送信号，按住拖动打开轮盘。")
        : l.Pick($"On. Hold {trigger.Keys()} to open the wheel.", $"已开启。按住 {trigger.Keys()} 打开轮盘。");

    public static string Usage(this Trigger trigger, Language l) => trigger.UsesPrimaryButton()
        ? l.Pick("Alt-click to ping, Ctrl+Alt-click to warn. Hold Alt and drag with the left button to open the wheel; release to send. On a touchpad, press and drag. While this is on, Alt-clicks belong to DotaPing.",
                 "Alt 点按发信号，Ctrl+Alt 点按发警告；按住 Alt 用左键拖动打开轮盘，松开发送。触摸板可按下拖动。开启后 Alt 点按由本程序占用。")
        : l.Pick("Hold for about 0.2 s to open the wheel, move the pointer to choose, release to send. On a touchpad, slide one finger to choose and tap to send at once. Two-finger tap or Esc cancels.",
                 "按住约 0.2 秒打开轮盘，移动指针选择，松开发送。触摸板上单指滑动即可选择，轻点立即发送。双指轻点或 Esc 取消。");
}

public readonly record struct Point2(double X, double Y);

public readonly record struct Rect2(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
}

public static class WheelGeometry
{
    /// <summary>Angular width of one wheel slot.</summary>
    public static readonly double Sector = 2 * Math.PI / Pings.Wheel.Count;
    public const double CenterRadius = 66;
    public const double IconRadius = 102;
    public const double OuterRadius = 140;

    /// <summary>Clockwise from north; null in the ordinary ping region. Coordinates have y increasing upwards.</summary>
    public static double? Direction(Point2 point, Point2 center, double deadZone)
    {
        double dx = point.X - center.X, dy = point.Y - center.Y;
        if (Math.Sqrt(dx * dx + dy * dy) <= deadZone) return null;
        return Math.Atan2(dx, dy);
    }

    public static PingKind Selection(Point2 point, Point2 center, double deadZone)
    {
        double dx = point.X - center.X, dy = point.Y - center.Y;
        if (Math.Sqrt(dx * dx + dy * dy) <= deadZone) return PingKind.Regular;
        int count = Pings.Wheel.Count;
        int index = (int)Math.Floor((Math.Atan2(dx, dy) + Sector / 2) / Sector);
        return Pings.Wheel[(index % count + count) % count];
    }

    public static Point2 ClampedCenter(Point2 anchor, Rect2 frame, double radius)
    {
        static double Clamp(double value, double low, double high) => low > high ? (low + high) / 2 : Math.Min(Math.Max(value, low), high);
        return new Point2(Clamp(anchor.X, frame.MinX + radius, frame.MaxX - radius),
                          Clamp(anchor.Y, frame.MinY + radius, frame.MaxY - radius));
    }
}
