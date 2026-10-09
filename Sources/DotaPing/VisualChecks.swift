import AppKit
import AVFoundation
import SwiftUI
import PingCore

/// Captures this app's own renderer, not the desktop. Does not request screen
/// recording permission, create input taps, or alter the user's preferences.
enum VisualChecks {
    static let backdrop = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1)
    static func bitmap(size: CGSize, pixelScale: CGFloat = 2, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width*pixelScale), pixelsHigh: Int(size.height*pixelScale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = graphics
        // NSGraphicsContext derives the pixel transform from rep.size.
        backdrop.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    static func draw(_ view: NSView, at point: CGPoint) {
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState(); context.translateBy(x: point.x, y: point.y)
        view.draw(view.bounds)
        // Composite the transparent app layer onto the export backdrop. Some
        // image viewers ignore alpha; opaque exports also show the actual glow.
        context.setBlendMode(.destinationOver)
        context.setFillColor(backdrop.cgColor)
        context.fill(view.bounds)
        context.restoreGState()
    }
    static func save(_ rep: NSBitmapImageRep, to url: URL) throws {
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
    static func run(to directory: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try checkEffectLifecycle()
        let order = PingKind.wheel + [.regular]
        for scale in [0.75, 1.0, 1.5] {
            let side = CGFloat(300*scale), spacing = CGFloat(16)
            let rep = bitmap(size: CGSize(width: side*3+spacing*4, height: side*3+spacing*4)) {
                for (index, kind) in order.enumerated() {
                    let view = WheelView(frame: CGRect(x: 0, y: 0, width: side, height: side))
                    let angle: CGFloat? = kind == .regular ? nil : CGFloat(PingKind.wheel.firstIndex(of: kind)!) * .pi/4
                    view.setSelection(kind, angle: angle, animated: false)
                    draw(view, at: CGPoint(x: spacing+CGFloat(index%3)*(side+spacing), y: spacing+CGFloat(2-index/3)*(side+spacing)))
                }
            }
            try save(rep, to: directory.appendingPathComponent("wheel-\(Int(scale*100))-retina.png"))
        }
        // 1x output also catches reliance on Retina-only sampling; it also
        // uses a Dire player colour.
        let view = WheelView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        view.player = .pink
        view.setSelection(.attack, angle: .pi/4, animated: false)
        try save(bitmap(size: CGSize(width: 300, height: 300), pixelScale: 1) { draw(view, at: .zero) }, to: directory.appendingPathComponent("wheel-100-1x.png"))
        let times = [0.06, 0.2, 0.45, 1.2, 1.8, 2.6]
        let phases = bitmap(size: CGSize(width: 200*CGFloat(times.count), height: 200*9)) {
            for (row, kind) in order.enumerated() {
                for (column, time) in times.enumerated() {
                    let effect = PingEffectView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), kind: kind, player: .blue, language: .english, scale: 1)
                    effect.seek(to: time)
                    draw(effect, at: CGPoint(x: column*200, y: (8-row)*200))
                }
            }
        }
        try save(phases, to: directory.appendingPathComponent("effect-phases-retina.png"))
        let colors = bitmap(size: CGSize(width: 200*5, height: 200*2)) {
            for color in PlayerColor.allCases {
                let effect = PingEffectView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), kind: .regular, player: color, language: .english, scale: 1)
                effect.seek(to: 0.45)
                draw(effect, at: CGPoint(x: (color.rawValue%5)*200, y: (color.isRadiant ? 1 : 0)*200))
            }
        }
        try save(colors, to: directory.appendingPathComponent("player-colors-retina.png"))
        try controlWindow(.controlOptionCommand, .english, appearance: .aqua, to: directory.appendingPathComponent("window-light.png"))
        try controlWindow(.controlOptionCommand, .english, appearance: .darkAqua, to: directory.appendingPathComponent("window-dark.png"))
        try controlWindow(.optionClick, .english, appearance: .darkAqua, to: directory.appendingPathComponent("window-option-click.png"))
        try controlWindow(.controlOptionCommand, .chinese, appearance: .darkAqua, to: directory.appendingPathComponent("window-zh.png"))
        // A single wheel and a row of landed pings in each language, for the READMEs.
        for language in Language.allCases {
            let suffix = language == .english ? "" : "-zh"
            let single = WheelView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            single.language = language
            single.setSelection(.enemyWard, angle: -.pi/4, animated: false)
            try save(bitmap(size: CGSize(width: 300, height: 300)) { draw(single, at: .zero) }, to: directory.appendingPathComponent("readme-wheel\(suffix).png"))
            let landed = bitmap(size: CGSize(width: 160*5, height: 170)) {
                for (index, kind) in [PingKind.regular, .caution, .attack, .enemyWard, .friendlyWard].enumerated() {
                    let effect = PingEffectView(frame: CGRect(x: 0, y: 0, width: 160, height: 170), kind: kind, player: .blue, language: language, scale: 1)
                    effect.seek(to: 0.7)
                    draw(effect, at: CGPoint(x: index*160, y: 0))
                }
            }
            try save(landed, to: directory.appendingPathComponent("readme-pings\(suffix).png"))
        }
        try movie(to: directory.appendingPathComponent("DotaPing-effects-demo.mov"))
        print("Visual snapshots and renderer demo saved: \(directory.path)")
    }
    /// Settings come from the volatile registration domain; nothing is written.
    private static func controlWindow(_ trigger: Trigger, _ language: Language, appearance: NSAppearance.Name, to url: URL) throws {
        let defaults = UserDefaults(suiteName: "local.dotaping.visual-check")!
        defaults.register(defaults: ["trigger": trigger.rawValue, "language": language.rawValue, "playerColor": PlayerColor.blue.rawValue, "volume": 0.55, "effectScale": 1.0])
        let model = AppModel(defaults: defaults)
        let host = NSHostingView(rootView: ControlView(model: model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 780), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "VisualChecks", code: 5) }
        host.cacheDisplay(in: host.bounds, to: rep)
        try save(rep, to: url)
    }
    private static func checkEffectLifecycle() throws {
        let size = CGSize(width: 240, height: 240)
        func pixels(_ rep: NSBitmapImageRep) -> Data {
            Data(bytes: rep.bitmapData!, count: rep.bytesPerRow*rep.pixelsHigh)
        }
        let empty = pixels(bitmap(size: size) {})
        for kind in PingKind.allCases {
            let effect = PingEffectView(frame: CGRect(origin: .zero, size: size), kind: kind, player: .blue, language: .english, scale: 1)
            effect.seek(to: 0.25)
            let early = pixels(bitmap(size: size) { draw(effect, at: .zero) })
            effect.seek(to: kind.effectDuration-0.5)
            let late = pixels(bitmap(size: size) { draw(effect, at: .zero) })
            effect.seek(to: kind.effectDuration+0.01)
            let finished = pixels(bitmap(size: size) { draw(effect, at: .zero) })
            effect.seek(to: 0.6); effect.stop()
            let stopped = pixels(bitmap(size: size) { draw(effect, at: .zero) })
            guard early != empty, early != late, late != empty, finished == empty, stopped == empty else {
                throw NSError(domain: "VisualChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "Animation/stop check failed: \(kind.title(.english))"])
            }
        }
        print("PASS 9 effects: visible animation changes, finish clean and stop immediately (36 pixel comparisons).")
    }
    private static func movie(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let size = CGSize(width: 960, height: 720), fps = 30, frames = 360
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height), kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        let wheel = WheelView(frame: CGRect(x: 0, y: 0, width: 450, height: 450))
        let order = PingKind.wheel + [.regular]
        var previous = -1
        for frame in 0..<frames {
            let t = Double(frame)/Double(fps)
            let rep = bitmap(size: size, pixelScale: 1) {
                if t < 7 {
                    let segment = max(-1, Int((t-0.6)/0.65))
                    let kind: PingKind = t < 0.6 ? .regular : (segment < 8 ? PingKind.wheel[segment] : .regular)
                    let angle: CGFloat? = kind == .regular ? nil : CGFloat(segment) * .pi/4 + CGFloat(sin(t*7))*0.15
                    if segment != previous { wheel.setSelection(wheel.selected, angle: wheel.direction, animated: false); previous = segment }
                    wheel.setSelection(kind, angle: angle)
                    wheel.sampleTransition(elapsed: t < 0.6 ? 1 : (t-0.6).truncatingRemainder(dividingBy: 0.65))
                    draw(wheel, at: CGPoint(x: 255, y: 135))
                    caption("Ping wheel: hovered sector, direction pointer, name", center: CGPoint(x: 480, y: 70))
                } else {
                    let age = (t-7).truncatingRemainder(dividingBy: 2.5)
                    for (index, kind) in order.enumerated() {
                        let effect = PingEffectView(frame: CGRect(x: 0, y: 0, width: 240, height: 200), kind: kind, player: .blue, language: .english, scale: 1.1)
                        effect.seek(to: age)
                        draw(effect, at: CGPoint(x: 120+(index%3)*240, y: 65+(2-index/3)*205))
                    }
                    caption("Nine pings: closing ring, pulses, rising icon, chat line", center: CGPoint(x: 480, y: 35))
                }
            }
            while !input.isReadyForMoreMediaData { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw NSError(domain: "VisualChecks", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.setFillColor(backdrop.cgColor); context.fill(CGRect(origin: .zero, size: size))
            context.draw(rep.cgImage!, in: CGRect(origin: .zero, size: size))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else { throw writer.error ?? NSError(domain: "VisualChecks", code: 2) }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "VisualChecks", code: 3) }
    }
    private static func caption(_ string: String, center: CGPoint) {
        let text = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor(white: 0.8, alpha: 1)])
        text.draw(at: CGPoint(x: center.x-text.size().width/2, y: center.y))
    }
}
