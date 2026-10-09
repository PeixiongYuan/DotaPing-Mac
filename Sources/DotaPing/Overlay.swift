import AppKit
import QuartzCore
import PingCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; hidesOnDeactivate = false; isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        animationBehavior = .none; isExcludedFromWindowsMenu = true
    }
}

private let iconIdle = NSColor(srgbRed: 0.86, green: 0.87, blue: 0.88, alpha: 1)
private func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }
private func ease(_ value: Double) -> Double { let t = clamp01(value); return t*t*(3-2*t) }
private func easeOut(_ value: Double) -> Double { let t = clamp01(value); return 1-pow(1-t, 3) }
private func mix(_ a: NSColor, _ b: NSColor, _ amount: Double) -> NSColor {
    a.blended(withFraction: CGFloat(clamp01(amount)), of: b) ?? b
}
private func text(_ string: String, at center: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    let label = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    label.draw(at: CGPoint(x: center.x-label.size().width/2, y: center.y-label.size().height/2))
}

/// Dark wheel with eight sectors. The hovered sector is tinted in the ping's
/// colour, and a pointer on the centre ring shows the direction. Everything is
/// drawn as vectors at the current backing scale; no bitmap is magnified.
final class WheelView: NSView {
    private(set) var selected: PingKind = .regular
    private(set) var direction: CGFloat?
    var player: PlayerColor = .blue { didSet { needsDisplay = true } }
    var language: Language = .english { didSet { needsDisplay = true } }
    private var weights = Array(repeating: 0.0, count: 8)
    private var origins = Array(repeating: 0.0, count: 8)
    private var transitionStart: CFTimeInterval = 0
    private var openingStart: CFTimeInterval?
    private var timer: Timer?

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }
    override var isOpaque: Bool { false }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }

    func open() { openingStart = CACurrentMediaTime(); startTimer() }
    func setSelection(_ kind: PingKind, angle: CGFloat?, animated: Bool = true) {
        direction = kind == .regular ? nil : angle
        if !animated {
            selected = kind; weights = PingKind.wheel.map { $0 == kind ? 1 : 0 }
            origins = weights; transitionStart = 0; stop(); needsDisplay = true
            return
        }
        updateAnimation(at: CACurrentMediaTime())
        if kind != selected {
            origins = weights; selected = kind; transitionStart = CACurrentMediaTime()
            startTimer()
        }
        needsDisplay = true
    }
    func stop() { timer?.invalidate(); timer = nil; layer?.removeAllAnimations() }
    // Diagnostics sample the same interpolation used by the live timer.
    func sampleTransition(elapsed: Double) {
        updateAnimation(at: transitionStart+elapsed); openingStart = nil; needsDisplay = true
    }
    private func startTimer() {
        guard timer == nil else { return }
        let next = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            self.updateAnimation(at: now); self.needsDisplay = true
            if now-self.transitionStart >= 0.12 && (self.openingStart == nil || now-self.openingStart! >= 0.11) {
                self.stop(); self.openingStart = nil
            }
        }
        timer = next; RunLoop.main.add(next, forMode: .common)
    }
    private func updateAnimation(at now: CFTimeInterval) {
        guard transitionStart > 0 else { return }
        let progress = ease((now-transitionStart)/0.12)
        weights = PingKind.wheel.enumerated().map { index, kind in
            origins[index] + ((kind == selected ? 1.0 : 0.0)-origins[index])*progress
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.saveGState()
        let s = bounds.width/300, c = CGPoint(x: bounds.midX, y: bounds.midY)
        if let start = openingStart {
            // Fade in while settling from slightly larger, about the wheel centre.
            let p = ease((CACurrentMediaTime()-start)/0.11)
            context.setAlpha(CGFloat(p))
            let grow = CGFloat(1.06-0.06*p)
            context.translateBy(x: c.x, y: c.y); context.scaleBy(x: grow, y: grow); context.translateBy(x: -c.x, y: -c.y)
        }
        let outer = WheelGeometry.outerRadius*s, inner = WheelGeometry.centerRadius*s
        let diskRect = CGRect(x: c.x-outer, y: c.y-outer, width: outer*2, height: outer*2)
        let disk = NSBezierPath(ovalIn: diskRect)
        NSColor(srgbRed: 0.055, green: 0.06, blue: 0.068, alpha: 0.86).setFill(); disk.fill()
        NSColor(white: 1, alpha: 0.12).setStroke(); disk.lineWidth = 1*s; disk.stroke()

        for (index, kind) in PingKind.wheel.enumerated() {
            let degrees = CGFloat(90-index*45), theta = degrees * .pi/180
            let weight = weights[index], tint = kind.tint(player)
            if weight > 0.001 {
                let sector = NSBezierPath()
                sector.appendArc(withCenter: c, radius: outer-0.5*s, startAngle: degrees+22.5, endAngle: degrees-22.5, clockwise: true)
                sector.appendArc(withCenter: c, radius: inner, startAngle: degrees-22.5, endAngle: degrees+22.5, clockwise: false)
                sector.close()
                tint.withAlphaComponent(0.20*weight).setFill(); sector.fill()
                let rim = NSBezierPath()
                rim.appendArc(withCenter: c, radius: outer-1.8*s, startAngle: degrees-22.5, endAngle: degrees+22.5)
                tint.withAlphaComponent(weight).setStroke(); rim.lineWidth = 2.6*s; rim.stroke()
            }
            let boundary = (degrees+22.5) * .pi/180
            let divider = NSBezierPath()
            divider.move(to: CGPoint(x: c.x+cos(boundary)*inner, y: c.y+sin(boundary)*inner))
            divider.line(to: CGPoint(x: c.x+cos(boundary)*outer, y: c.y+sin(boundary)*outer))
            NSColor(white: 1, alpha: 0.08).setStroke(); divider.lineWidth = 0.6*s; divider.stroke()
            let p = CGPoint(x: c.x+cos(theta)*WheelGeometry.iconRadius*s, y: c.y+sin(theta)*WheelGeometry.iconRadius*s)
            let side = CGFloat(24+6*weight)*s
            let rect = CGRect(x: p.x-side/2, y: p.y-side/2, width: side, height: side)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -0.6*s), blur: 1.5*s, color: NSColor(white: 0, alpha: 0.7).cgColor)
            // Pings with a fixed colour keep a hint of it, so the two wards differ at a glance.
            let idle = kind.fixedColor == nil ? iconIdle.withAlphaComponent(0.78) : mix(iconIdle, tint, 0.5).withAlphaComponent(0.85)
            Assets.draw(kind, in: rect, color: mix(idle, tint, weight))
            context.restoreGState()
        }

        let coreRect = CGRect(x: c.x-inner, y: c.y-inner, width: inner*2, height: inner*2)
        let core = NSBezierPath(ovalIn: coreRect)
        NSColor(srgbRed: 0.035, green: 0.038, blue: 0.044, alpha: 0.96).setFill(); core.fill()
        NSColor(white: 1, alpha: 0.14).setStroke(); core.lineWidth = 1*s; core.stroke()
        if let angle = direction {
            let theta = CGFloat.pi/2-angle
            func point(_ radius: CGFloat, _ offset: CGFloat = 0) -> CGPoint {
                CGPoint(x: c.x+cos(theta+offset)*radius, y: c.y+sin(theta+offset)*radius)
            }
            let pointer = NSBezierPath()
            pointer.move(to: point(inner-1*s, 0.09)); pointer.line(to: point(inner+7*s)); pointer.line(to: point(inner-1*s, -0.09)); pointer.close()
            selected.tint(player).setFill(); pointer.fill()
        }
        if selected == .regular {
            Assets.draw(.regular, in: CGRect(x: c.x-10*s, y: c.y+4*s, width: 20*s, height: 20*s), color: PingKind.regular.tint(player))
            text(PingKind.regular.title(language), at: CGPoint(x: c.x, y: c.y-13*s), size: 13*s, color: .white, weight: .medium)
        } else {
            text(selected.title(language), at: c, size: 14*s, color: .white, weight: .medium)
        }
        context.restoreGState()
    }
}

/// One renderer is used by live overlays, window previews and the exported
/// demo. Following the game's minimap animation, a ring collapses onto the
/// spot and throbs; a wide pulse spreads out; the glyph rises over a ground
/// glow; chat-style text names the ping. Each layer has its own timeline.
final class PingEffectView: NSView {
    let kind: PingKind
    let tint: NSColor
    let effectScale: CGFloat
    let language: Language
    var duration: Double { kind.effectDuration }
    private(set) var elapsed: Double
    private var started: CFTimeInterval = 0
    private var timer: Timer?
    init(frame: NSRect, kind: PingKind, player: PlayerColor, language: Language, scale: CGFloat) {
        self.kind = kind; self.tint = kind.tint(player); self.language = language; self.effectScale = scale; self.elapsed = kind.effectDuration
        super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }
    override var isOpaque: Bool { false }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
    func start() {
        timer?.invalidate(); started = CACurrentMediaTime(); seek(to: 0)
        let next = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.seek(to: CACurrentMediaTime()-self.started)
            if self.elapsed >= self.duration { timer.invalidate(); self.timer = nil }
        }
        timer = next; RunLoop.main.add(next, forMode: .common)
    }
    func seek(to time: Double) { elapsed = time; needsDisplay = true }
    func stop() { timer?.invalidate(); timer = nil; elapsed = duration; layer?.removeAllAnimations(); needsDisplay = true }
    /// The ground point sits this far below the view centre (before scaling).
    static let groundOffset: CGFloat = 22
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        let t = elapsed, d = duration
        guard t >= 0, t < d else { return }
        let s = effectScale
        let ground = CGPoint(x: bounds.midX, y: bounds.midY-Self.groundOffset*s)
        let alpha = ease(t/0.07)*(1-ease((t-(d-0.9))/0.9))
        func ellipse(_ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: CGRect(x: ground.x-radius, y: ground.y-radius*0.5, width: radius*2, height: radius))
        }
        context.saveGState(); context.setAlpha(CGFloat(alpha))
        // Ground glow under the marker.
        context.saveGState()
        context.translateBy(x: ground.x, y: ground.y); context.scaleBy(x: 1, y: 0.5)
        NSGradient(colorsAndLocations: (tint.withAlphaComponent(0.30), 0), (tint.withAlphaComponent(0.12), 0.55), (tint.withAlphaComponent(0), 1))?
            .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 46*s, options: [])
        context.restoreGState()
        // A ring collapses from far out onto the spot in 0.3 s, then throbs.
        let settle = easeOut(t/0.3)
        let throb = t > 0.3 ? 1.4*sin((t-0.3)*2 * .pi*1.5) : 0
        let markerRadius = CGFloat(92-71*settle+throb)*s
        context.saveGState()
        context.setShadow(offset: .zero, blur: 5*s, color: tint.withAlphaComponent(0.8).cgColor)
        tint.withAlphaComponent(0.35+0.6*settle).setStroke()
        let marker = ellipse(markerRadius); marker.lineWidth = CGFloat(1.2+1.2*settle)*s; marker.stroke()
        context.restoreGState()
        // Wide, faint pulses spread outwards once the marker lands.
        for (index, delay) in [0.28, 0.95].enumerated() where t > delay {
            let progress = (t-delay)/1.5
            guard progress < 1 else { continue }
            let pulse = ellipse(CGFloat(21+64*easeOut(progress))*s)
            tint.withAlphaComponent(CGFloat(pow(1-progress, 1.6)*(index == 0 ? 0.75 : 0.45))).setStroke()
            pulse.lineWidth = CGFloat(index == 0 ? 1.6 : 1.0)*s; pulse.stroke()
        }
        // A brief additive flash as the ring lands.
        if t > 0.24 && t < 1.1 {
            let flash = 1-ease((t-0.24)/0.86)
            context.saveGState(); context.setBlendMode(.plusLighter)
            context.translateBy(x: ground.x, y: ground.y); context.scaleBy(x: 1, y: 0.5)
            NSGradient(colors: [tint.withAlphaComponent(CGFloat(0.55*flash)), tint.withAlphaComponent(0)])?
                .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 28*s, options: [])
            context.restoreGState()
        }
        // The glyph pops up, overshoots slightly and bobs.
        let pop: Double
        if t < 0.14 { pop = 0.45+0.67*ease(t/0.14) }
        else if t < 0.28 { pop = 1.12-0.12*ease((t-0.14)/0.14) }
        else { pop = 1 }
        let lift = CGFloat(10*ease(t/0.3)+2.2*sin(min(t, d-0.4)*2 * .pi*0.7))*s
        let side = CGFloat(40*pop)*s
        let rect = CGRect(x: ground.x-side/2, y: ground.y+9*s+lift, width: side, height: side)
        context.saveGState(); context.setAlpha(CGFloat(alpha)*0.45)
        context.setShadow(offset: .zero, blur: 7*s, color: tint.cgColor)
        Assets.draw(kind, in: rect, color: tint)
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1*s), blur: 2*s, color: NSColor(white: 0, alpha: 0.7).cgColor)
        Assets.draw(kind, in: rect, color: tint)
        context.restoreGState()
        // The team chat line for this ping, above the glyph.
        if let chat = kind.chat(language) {
            let appear = ease((t-0.12)/0.2)
            let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.9); shadow.shadowBlurRadius = 2*s; shadow.shadowOffset = NSSize(width: 0, height: -0.5*s)
            let label = NSAttributedString(string: chat, attributes: [.font: NSFont.systemFont(ofSize: 11*s, weight: .medium),
                                                                      .foregroundColor: NSColor(white: 0.95, alpha: 1), .shadow: shadow])
            let size = label.size()
            context.saveGState(); context.setAlpha(CGFloat(alpha*appear))
            label.draw(at: CGPoint(x: ground.x-size.width/2, y: rect.maxY+2*s-CGFloat(3*(1-appear))*s))
            context.restoreGState()
        }
        context.restoreGState()
    }
}

final class OverlayController {
    private var wheel: OverlayPanel?
    private var wheelView: WheelView?
    private var retiring: [(OverlayPanel, DispatchWorkItem)] = []
    private var effects: [(UUID, OverlayPanel, DispatchWorkItem)] = []
    @discardableResult func showWheel(at anchor: CGPoint, scale: Double, player: PlayerColor, language: Language) -> CGPoint {
        hideWheel(animated: false)
        let side = CGFloat(300*scale)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        let center = WheelGeometry.clampedCenter(anchor: anchor, frame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900), radius: side/2)
        let panel = OverlayPanel(frame: CGRect(x: center.x-side/2, y: center.y-side/2, width: side, height: side))
        let view = WheelView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.player = player; view.language = language
        panel.contentView = view; panel.orderFrontRegardless(); view.open()
        wheel = panel; wheelView = view
        return center
    }
    func select(_ kind: PingKind, angle: CGFloat?) { wheelView?.setSelection(kind, angle: angle) }
    func hideWheel(animated: Bool = true) {
        guard let panel = wheel else { return }
        wheelView?.stop(); wheel = nil; wheelView = nil
        guard animated else { panel.orderOut(nil); panel.close(); return }
        NSAnimationContext.runAnimationGroup { context in context.duration = 0.09; panel.animator().alphaValue = 0 }
        let cleanup = DispatchWorkItem { [weak self, weak panel] in
            panel?.close(); self?.retiring.removeAll { $0.0 === panel }
        }
        retiring.append((panel, cleanup))
        DispatchQueue.main.asyncAfter(deadline: .now()+0.10, execute: cleanup)
    }
    func showPing(_ kind: PingKind, at point: CGPoint, scale: Double, player: PlayerColor, language: Language) {
        if effects.count >= 16 { let oldest = effects.removeFirst(); oldest.2.cancel(); closeEffect(oldest.1) }
        let side = CGFloat(240*scale)
        // The ground point (below the view centre) is exactly the anchor.
        let panel = OverlayPanel(frame: CGRect(x: point.x-side/2, y: point.y-side/2+PingEffectView.groundOffset*scale, width: side, height: side))
        let view = PingEffectView(frame: CGRect(x: 0, y: 0, width: side, height: side), kind: kind, player: player, language: language, scale: CGFloat(scale))
        panel.contentView = view; panel.orderFrontRegardless(); view.start()
        let id = UUID()
        let cleanup = DispatchWorkItem { [weak self, weak panel] in
            if let panel { self?.closeEffect(panel) }; self?.effects.removeAll { $0.0 == id }
        }
        effects.append((id, panel, cleanup))
        DispatchQueue.main.asyncAfter(deadline: .now()+kind.effectDuration+0.05, execute: cleanup)
    }
    private func closeEffect(_ panel: OverlayPanel) { (panel.contentView as? PingEffectView)?.stop(); panel.close() }
    func clear() {
        hideWheel(animated: false)
        retiring.forEach { $0.1.cancel(); $0.0.contentView?.layer?.removeAllAnimations(); $0.0.close() }; retiring.removeAll()
        effects.forEach { $0.2.cancel(); closeEffect($0.1) }; effects.removeAll()
    }
}
