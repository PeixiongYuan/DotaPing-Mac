import Foundation
import CoreGraphics

/// Interface language, chosen in the app (English by default).
public enum Language: String, CaseIterable, Identifiable {
    case english = "en", chinese = "zh-Hans"
    public var id: String { rawValue }
    /// Each language is listed under its own name.
    public var name: String { self == .english ? "English" : "简体中文" }
    public func pick(_ english: String, _ chinese: String) -> String { self == .english ? english : chinese }
}

/// The default entries of Dota 2's ping wheel (`scripts/ping_wheel.vdata`).
public enum PingKind: String, CaseIterable, Identifiable {
    case caution, attack, onMyWay, warning, assist, friendlyWard, defend, enemyWard, regular
    public var id: String { rawValue }
    /// Clockwise from north. The centre is the ordinary ping.
    public static let wheel: [PingKind] = [.caution, .attack, .onMyWay, .warning, .assist, .friendlyWard, .defend, .enemyWard]
    /// Wheel label: the game's `dota_pingwheel_*` string.
    public func title(_ language: Language) -> String {
        switch self {
        case .caution: return language.pick("Caution", "小心")
        case .attack: return language.pick("Attack", "进攻")
        case .onMyWay: return language.pick("On My Way", "我马上到")
        case .warning: return language.pick("Warning", "警告")
        case .assist: return language.pick("Assist", "援助")
        case .friendlyWard: return language.pick("Friendly Ward", "友方守卫")
        case .defend: return language.pick("Defend", "防守")
        case .enemyWard: return language.pick("Enemy Ward", "敌方守卫")
        case .regular: return language.pick("Ping", "信号")
        }
    }
    /// Team chat line: the game's `DOTA_Chat_Ping_Msg_*` text, without icon and location.
    /// The ordinary and warning pings post no chat message in game.
    public func chat(_ language: Language) -> String? {
        switch self {
        case .caution: return language.pick("Caution", "小心")
        case .attack: return language.pick("Attack", "攻击")
        case .onMyWay: return language.pick("On My Way", "前往")
        case .assist: return language.pick("Assist", "援助")
        case .friendlyWard: return language.pick("We Need Vision", "我们需要视野")
        case .defend: return language.pick("Defend", "防守")
        case .enemyWard: return language.pick("Enemy Has Vision", "敌人有视野")
        case .warning, .regular: return nil
        }
    }
    /// One cue per game sound event; several pings share an event, as in game.
    public var soundName: String {
        switch self {
        case .regular, .assist: return "ping"
        case .warning, .caution: return "ping_warning"
        case .onMyWay: return "ping_waypoint"
        case .attack: return "ping_attack"
        case .enemyWard: return "ping_enemy_ward"
        case .friendlyWard: return "ping_friendly_ward"
        case .defend: return "ping_defense"
        }
    }
    /// Fixed effect colour from ping_wheel.vdata; nil means the pinging player's colour.
    public var fixedColor: RGB? {
        switch self {
        case .caution: return RGB(255, 155, 14)
        case .enemyWard: return RGB(225, 51, 51)
        case .friendlyWard: return RGB(10, 255, 10)
        default: return nil
        }
    }
    public func color(for player: PlayerColor) -> RGB { fixedColor ?? player.rgb }
    /// Seconds the desktop effect stays visible.
    public var effectDuration: Double { self == .regular ? 2.0 : 3.0 }
}

public struct RGB: Equatable, Hashable {
    public let red, green, blue: Double
    public init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = Double(red)/255; self.green = Double(green)/255; self.blue = Double(blue)/255
    }
}

/// The ten in-game player slot colours.
public enum PlayerColor: Int, CaseIterable, Identifiable {
    case blue, teal, purple, yellow, orange, pink, olive, lightBlue, darkGreen, brown
    public var id: Int { rawValue }
    public var isRadiant: Bool { rawValue < 5 }
    public func name(_ language: Language) -> String {
        language == .english
            ? ["Blue", "Teal", "Purple", "Yellow", "Orange", "Pink", "Olive", "Light Blue", "Dark Green", "Brown"][rawValue]
            : ["蓝", "青绿", "紫", "黄", "橙", "粉", "橄榄绿", "浅蓝", "深绿", "棕"][rawValue]
    }
    public func title(_ language: Language) -> String {
        language == .english
            ? "\(isRadiant ? "Radiant" : "Dire") \(rawValue%5+1) · \(name(language))"
            : "\(isRadiant ? "天辉" : "夜魇") \(rawValue%5+1) 号位 · \(name(language))"
    }
    public var rgb: RGB {
        switch self {
        case .blue: return RGB(51, 117, 255)
        case .teal: return RGB(102, 255, 191)
        case .purple: return RGB(191, 0, 191)
        case .yellow: return RGB(243, 240, 11)
        case .orange: return RGB(255, 107, 0)
        case .pink: return RGB(254, 134, 194)
        case .olive: return RGB(161, 180, 71)
        case .lightBlue: return RGB(101, 217, 247)
        case .darkGreen: return RGB(0, 131, 33)
        case .brown: return RGB(164, 105, 0)
        }
    }
}

public struct Modifiers: OptionSet, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let command = Modifiers(rawValue: 4)
    public static let shift = Modifiers(rawValue: 8)
}

/// Either a held modifier chord (no mouse button needed, comfortable on a
/// trackpad) or the game's own gesture: Option plus the primary button.
public enum Trigger: String, CaseIterable, Identifiable {
    case controlOptionCommand, controlOptionShift, controlCommandShift, optionClick
    public var id: String { rawValue }
    public var usesPrimaryButton: Bool { self == .optionClick }
    public func title(_ language: Language) -> String {
        usesPrimaryButton ? language.pick("⌥ + Left Click (as in game)", "⌥ + 左键（与游戏相同）")
                          : language.pick("Hold \(symbols)", "按住 \(symbols)")
    }
    public var symbols: String {
        switch self {
        case .controlOptionCommand: return "⌃⌥⌘"
        case .controlOptionShift: return "⌃⌥⇧"
        case .controlCommandShift: return "⌃⌘⇧"
        case .optionClick: return "⌥ + 左键"
        }
    }
    public var modifiers: Modifiers {
        switch self {
        case .controlOptionCommand: return [.control, .option, .command]
        case .controlOptionShift: return [.control, .option, .shift]
        case .controlCommandShift: return [.control, .command, .shift]
        case .optionClick: return [.option]
        }
    }
    /// With the primary-button trigger, adding Control sends the game's warning ping.
    public var warningModifiers: Modifiers? { usesPrimaryButton ? [.control, .option] : nil }
    public func ready(_ language: Language) -> String {
        usesPrimaryButton
            ? language.pick("On. ⌥-click to ping; hold and drag to open the wheel.", "已开启。⌥ 点按发送信号，按住拖动打开轮盘。")
            : language.pick("On. Hold \(symbols) to open the wheel.", "已开启。按住 \(symbols) 打开轮盘。")
    }
    public func usage(_ language: Language) -> String {
        usesPrimaryButton
            ? language.pick("⌥-click to ping, ⌃⌥-click to warn. Hold ⌥ and drag with the left button to open the wheel; release to send. On a trackpad, press and drag or use three-finger drag. While this is on, ⌥-clicks belong to DotaPing.",
                            "⌥ 点按发信号，⌃⌥ 点按发警告；⌥ 按住左键拖动打开轮盘，松开发送。触控板可按压拖动或三指拖移。开启后 ⌥ 点按由本程序占用。")
            : language.pick("Hold for about 0.2 s to open the wheel, move the pointer to choose, release to send. On a trackpad, slide one finger to choose and tap to send at once. Two-finger tap or Esc cancels.",
                            "按住约 0.2 秒打开轮盘，移动指针选择，松开发送。触控板上单指滑动即可选择，轻点立即发送。双指轻点或 Esc 取消。")
    }
}

public enum WheelGeometry {
    public static let centerRadius: CGFloat = 66
    public static let iconRadius: CGFloat = 102
    public static let outerRadius: CGFloat = 140

    /// Clockwise from north; nil in the ordinary ping region.
    public static func direction(at point: CGPoint, center: CGPoint, deadZone: CGFloat) -> CGFloat? {
        let dx = point.x - center.x, dy = point.y - center.y
        guard hypot(dx, dy) > deadZone else { return nil }
        return atan2(dx, dy)
    }
    /// Coordinates use the AppKit convention: y increases upwards.
    public static func selection(at point: CGPoint, center: CGPoint, deadZone: CGFloat) -> PingKind {
        let dx = point.x - center.x, dy = point.y - center.y
        guard hypot(dx, dy) > deadZone else { return .regular }
        let clockwiseFromNorth = atan2(dx, dy)
        let index = Int(floor((clockwiseFromNorth + .pi / 8) / (.pi / 4)))
        return PingKind.wheel[(index % 8 + 8) % 8]
    }

    public static func clampedCenter(anchor: CGPoint, frame: CGRect, radius: CGFloat) -> CGPoint {
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            low > high ? (low + high) / 2 : min(max(value, low), high)
        }
        return CGPoint(x: clamp(anchor.x, frame.minX + radius, frame.maxX - radius),
                       y: clamp(anchor.y, frame.minY + radius, frame.maxY - radius))
    }
}
