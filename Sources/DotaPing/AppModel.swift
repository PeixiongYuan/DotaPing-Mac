import AppKit
import Combine
import PingCore

final class AppModel: ObservableObject {
    enum Status { case off, ready, needsPermission, missingPermission, permissionRevoked, inputPaused, inputUnavailable }
    @Published private(set) var isEnabled = false
    @Published private(set) var awaitingPermission = false
    @Published private(set) var status: Status = .off
    @Published var language: Language {
        didSet { defaults.set(language.rawValue, forKey: "language"); onStateChange?() }
    }
    @Published var trigger: Trigger {
        didSet { defaults.set(trigger.rawValue, forKey: "trigger"); restartInputIfNeeded() }
    }
    @Published var player: PlayerColor {
        didSet { defaults.set(player.rawValue, forKey: "playerColor") }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: "volume") }
    }
    @Published var scale: Double {
        didSet { defaults.set(scale, forKey: "effectScale"); restartInputIfNeeded() }
    }
    @Published private(set) var previewKind: PingKind = .enemyWard
    @Published private(set) var previewToken = UUID()
    @Published private(set) var previewVisible = false
    var onStateChange: (() -> Void)?
    let defaults: UserDefaults
    private let input = GlobalInput()
    private let overlay = OverlayController()
    private let sound = SoundPlayer()
    private var previewCleanup: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var observations: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .english
        trigger = Trigger(rawValue: defaults.string(forKey: "trigger") ?? "") ?? .controlOptionCommand
        player = PlayerColor(rawValue: defaults.integer(forKey: "playerColor")) ?? .blue
        volume = defaults.object(forKey: "volume") == nil ? 0.55 : min(max(defaults.double(forKey: "volume"), 0), 1)
        scale = defaults.object(forKey: "effectScale") == nil ? 1 : min(max(defaults.double(forKey: "effectScale"), 0.75), 1.5)
        input.onAction = { [weak self] action in self?.handle(action) }
        input.onUnavailable = { [weak self] in
            self?.setEnabled(false)
            self?.status = .inputPaused
        }
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.checkPermission() })
        observations.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelEffects() })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.didActivateApplicationNotification] {
            observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancelEffects() })
        }
    }
    func restoreState() {
        if defaults.bool(forKey: "enabled") {
            if GlobalInput.isTrusted { setEnabled(true) }
            else { status = .missingPermission }
        }
    }
    func setEnabled(_ value: Bool) {
        if !value {
            awaitingPermission = false
            permissionTimer?.invalidate(); permissionTimer = nil
            input.stop(); overlay.clear(); sound.stopAll(); stopPreview()
            isEnabled = false; defaults.set(false, forKey: "enabled")
            status = .off
            onStateChange?()
            return
        }
        guard GlobalInput.isTrusted else {
            awaitingPermission = true
            status = .needsPermission
            GlobalInput.requestPermission()
            permissionTimer?.invalidate()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkPermission() }
            onStateChange?()
            return
        }
        do {
            try input.start(trigger: trigger, scale: scale)
            isEnabled = true; awaitingPermission = false
            permissionTimer?.invalidate(); permissionTimer = nil
            defaults.set(true, forKey: "enabled")
            status = .ready
        } catch {
            isEnabled = false; awaitingPermission = false
            permissionTimer?.invalidate(); permissionTimer = nil
            defaults.set(false, forKey: "enabled")
            status = error as? GlobalInput.StartError == .permission ? .needsPermission : .inputUnavailable
        }
        onStateChange?()
    }
    func checkPermission() {
        if awaitingPermission && GlobalInput.isTrusted { setEnabled(true) }
        else if isEnabled && !GlobalInput.isTrusted {
            setEnabled(false); status = .permissionRevoked
        }
    }
    /// Rendered on demand, so a language switch also updates the current message.
    var message: String {
        let l = language
        switch status {
        case .off: return l.pick("Off. You can still preview pings below.", "已关闭。下方仍可预览。")
        case .ready: return trigger.ready(l)
        case .needsPermission: return l.pick("Needs Accessibility permission (Privacy & Security → Accessibility). Turns on once allowed.",
                                             "需要辅助功能权限（隐私与安全性 → 辅助功能），授权后自动开启。")
        case .missingPermission: return l.pick("Was on last time, but Accessibility permission is missing.", "上次已开启，但缺少辅助功能权限。")
        case .permissionRevoked: return l.pick("Accessibility permission was turned off.", "辅助功能权限已被关闭。")
        case .inputPaused: return l.pick("Global input paused. Check Accessibility permission.", "全局输入已暂停，请检查辅助功能权限。")
        case .inputUnavailable: return l.pick("Can't listen for global input. Check Accessibility, and Input Monitoring if macOS asks for it.",
                                              "无法监听全局输入。请检查辅助功能权限；如系统要求，也开启输入监控。")
        }
    }
    func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    func openTrackpadSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Trackpad.prefPane"))
    }
    func revealCustomSounds() { SoundPlayer.revealCustomFolder() }
    func preview(_ kind: PingKind) {
        previewCleanup?.cancel()
        previewKind = kind; previewToken = UUID(); previewVisible = true
        sound.play(kind, volume: volume)
        let cleanup = DispatchWorkItem { [weak self] in self?.previewVisible = false }
        previewCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now()+kind.effectDuration+0.1, execute: cleanup)
    }
    func stopPreview() {
        previewCleanup?.cancel(); previewCleanup = nil; previewVisible = false
    }
    func cancelEffects() { input.cancelCurrent(); overlay.clear(); sound.stopAll(); stopPreview() }
    func shutdown() {
        // Preserve the user's enabled preference across an intentional app quit.
        permissionTimer?.invalidate(); input.stop(); overlay.clear(); sound.stopAll(); stopPreview()
    }
    private func restartInputIfNeeded() {
        cancelEffects()
        if isEnabled { setEnabled(true) }
        onStateChange?()
    }
    private func handle(_ action: GestureMachine.Action) {
        guard isEnabled else { return }
        switch action {
        case .show(let anchor): input.setWheelCenter(overlay.showWheel(at: anchor, scale: scale, player: player, language: language))
        case .hover(let kind, let angle): overlay.select(kind, angle: angle)
        case .hide: overlay.hideWheel(animated: false)
        case .dismiss: overlay.hideWheel()
        case .commit(let kind, let anchor):
            overlay.showPing(kind, at: anchor, scale: scale, player: player, language: language)
            sound.play(kind, volume: volume)
        case .arm: break
        }
    }
}
