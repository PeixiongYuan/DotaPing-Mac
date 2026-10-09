import SwiftUI
import AppKit
import PingCore

struct ControlView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let l = model.language
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.isEnabled || model.awaitingPermission }, set: { model.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.pick("Enable DotaPing", "启用 DotaPing"))
                        Text(model.message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.awaitingPermission {
                    HStack {
                        Button(l.pick("Open Accessibility Settings…", "打开辅助功能设置…")) { model.openAccessibility() }
                        Button(l.pick("Check Again", "重新检查")) { model.checkPermission() }
                    }
                } else if model.status == .inputUnavailable {
                    Button(l.pick("Open Input Monitoring Settings…", "打开输入监控设置…")) { model.openInputMonitoring() }
                }
            }
            Section {
                Picker(l.pick("Trigger", "触发"), selection: $model.trigger) {
                    ForEach(Trigger.allCases) { Text($0.title(l)).tag($0) }
                }
            } footer: {
                Text(model.trigger.usage(l)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent(l.pick("Player Color", "玩家颜色")) {
                    HStack(spacing: 5) {
                        ForEach(PlayerColor.allCases) { color in
                            swatch(color).padding(.leading, color == .pink ? 8 : 0)
                        }
                    }
                }
                Slider(value: $model.scale, in: 0.75...1.5, step: 0.05) { Text(l.pick("Size", "大小")) }
                Slider(value: $model.volume, in: 0...1) { Text(l.pick("Volume", "音量")) }
                Picker(l.pick("Sounds", "音效"), selection: $model.soundSet) {
                    Text(l.pick("Built-in", "内置合成")).tag(AppModel.SoundSet.synthesized)
                    Text(l.pick("Dota 2 Original", "Dota 2 原声")).tag(AppModel.SoundSet.game)
                }
                Picker(l.pick("Language", "语言"), selection: $model.language) {
                    ForEach(Language.allCases) { Text($0.name).tag($0) }
                }
            } footer: {
                if let note = soundNote(l) {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(l.pick("Preview", "预览")) {
                preview
            }
            Section {
                HStack {
                    Button(l.pick("Accessibility Settings…", "辅助功能设置…")) { model.openAccessibility() }
                    Button(l.pick("Custom Sounds…", "自定义音效…")) { model.revealCustomSounds() }
                        .help(l.pick("Add a file with the same name to replace a sound: ", "放入同名文件即可替换：")
                              + SoundSynth.names.joined(separator: l.pick(", ", "、")))
                    Spacer()
                    Button(l.pick("Quit", "退出")) { NSApp.terminate(nil) }
                }
            } footer: {
                Text(l.pick("Not affiliated with Valve. No game files are bundled; original sounds are downloaded only if you choose them.",
                            "非 Valve 官方产品。不附带任何游戏文件；仅在你选择时下载原声。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
    }

    private func soundNote(_ l: Language) -> String? {
        switch model.download {
        case .downloading:
            return l.pick("Downloading the game's ping sounds…", "正在下载游戏信号音效…")
        case .failed(let reason):
            return l.pick("Couldn't download the game sounds (\(reason)). Using the built-in sounds.", "游戏音效下载失败（\(reason)），已改用内置合成音效。")
        case .idle:
            guard model.soundSet == .game else { return nil }
            return l.pick("Original sounds from the \(GameSounds.archive) archive, stored on this Mac only. © Valve.",
                          "原声来自 \(GameSounds.archive) 存档，仅保存在本机。© Valve。")
        }
    }

    private func swatch(_ color: PlayerColor) -> some View {
        let selected = model.player == color
        let title = color.title(model.language)
        return Button { model.player = color } label: {
            Circle().fill(Color(nsColor: NSColor(color.rgb)))
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .padding(2)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private var preview: some View {
        let l = model.language
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.09))
                if model.previewVisible {
                    EffectPreview(kind: model.previewKind, player: model.player, language: l, scale: model.scale, token: model.previewToken)
                        .allowsHitTesting(false)
                } else {
                    Text(l.pick("Click a ping below to preview it", "点下方信号预览")).font(.caption).foregroundStyle(Color(white: 0.5))
                }
            }
            .frame(height: max(140, 140*model.scale))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), alignment: .leading, spacing: 2) {
                ForEach(PingKind.wheel + [.regular]) { kind in
                    let active = model.previewVisible && model.previewKind == kind
                    Button { model.preview(kind) } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: Assets.icon(kind, color: .black)).renderingMode(.template)
                                .resizable().frame(width: 16, height: 16)
                            Text(kind.title(l)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(active ? Color.accentColor : Color.primary)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(kind.chat(l) ?? kind.title(l))
                    .accessibilityLabel(l.pick("Preview \(kind.title(l))", "预览\(kind.title(l))"))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EffectPreview: NSViewRepresentable {
    let kind: PingKind
    let player: PlayerColor
    let language: Language
    let scale: Double
    let token: UUID
    final class Coordinator { var token: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.token != token else { return }
        context.coordinator.token = token
        view.subviews.forEach { ($0 as? PingEffectView)?.stop(); $0.removeFromSuperview() }
        let effect = PingEffectView(frame: view.bounds, kind: kind, player: player, language: language, scale: CGFloat(scale))
        effect.autoresizingMask = [.width, .height]
        view.addSubview(effect)
        DispatchQueue.main.async { [weak effect] in effect?.start() }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        nsView.subviews.forEach { ($0 as? PingEffectView)?.stop() }
    }
}
