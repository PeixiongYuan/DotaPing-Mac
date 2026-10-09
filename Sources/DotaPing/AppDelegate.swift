import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var enableItem: NSMenuItem!
    private var stateItem: NSMenuItem!
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        buildStatusMenu()
        let controller = NSHostingController(rootView: ControlView(model: model))
        window = NSWindow(contentViewController: controller)
        window.title = "DotaPing"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 640))
        window.minSize = NSSize(width: 460, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        model.onStateChange = { [weak self] in self?.updateStatus() }
        model.restoreState(); updateStatus()
        showWindow()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func windowWillClose(_ notification: Notification) { model.cancelEffects() }

    @objc func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleEnabled() { model.setEnabled(!(model.isEnabled || model.awaitingPermission)) }
    @objc private func quit() { NSApp.terminate(nil) }

    private var settingsItems: [NSMenuItem] = []
    private var quitItems: [NSMenuItem] = []

    private func buildMainMenu() {
        let menu = NSMenu()
        let application = NSMenuItem()
        let submenu = NSMenu(title: "DotaPing")
        settingsItems.append(submenu.addItem(withTitle: "", action: #selector(showWindow), keyEquivalent: ","))
        submenu.addItem(.separator())
        quitItems.append(submenu.addItem(withTitle: "", action: #selector(quit), keyEquivalent: "q"))
        application.submenu = submenu; menu.addItem(application)
        NSApp.mainMenu = menu
    }
    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)
        enableItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        menu.addItem(enableItem)
        settingsItems.append(menu.addItem(withTitle: "", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        quitItems.append(menu.addItem(withTitle: "", action: #selector(quit), keyEquivalent: ""))
        (settingsItems + quitItems + [enableItem]).forEach { $0.target = self }
        statusItem.menu = menu
    }
    /// Also called when the language changes.
    private func updateStatus() {
        let l = model.language
        let state = model.isEnabled ? l.pick("On", "已开启") : (model.awaitingPermission ? l.pick("Waiting for Permission", "等待授权") : l.pick("Off", "已关闭"))
        let summary = l.pick("DotaPing: \(state)", "DotaPing：\(state)")
        stateItem.title = summary
        enableItem.state = model.isEnabled ? .on : (model.awaitingPermission ? .mixed : .off)
        enableItem.title = model.awaitingPermission ? l.pick("Cancel", "取消启用") : l.pick("Enable", "启用")
        settingsItems.forEach { $0.title = l.pick("Settings…", "设置…") }
        quitItems.forEach { $0.title = l.pick("Quit DotaPing", "退出 DotaPing") }
        statusItem.button?.toolTip = summary
        statusItem.button?.setAccessibilityLabel(l.pick("DotaPing menu", "DotaPing 菜单"))
        statusItem.button?.image = NSImage(systemSymbolName: model.isEnabled ? "exclamationmark.circle.fill" : "exclamationmark.circle", accessibilityDescription: summary)
    }
}
