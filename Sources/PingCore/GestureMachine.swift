import Foundation
import CoreGraphics

/// Pure state machine. Platform code handles clocks, permissions and rendering.
///
/// Chord triggers open the wheel while the modifiers are held; releasing any of
/// them sends, and so does a primary click or trackpad tap while the wheel is
/// open. The primary-button trigger follows the game: Option-click pings,
/// Control-Option-click warns, and holding the button opens the wheel until it
/// is released. Pointer travel works the same for mouse and trackpad.
public final class GestureMachine {
    public enum Phase: Equatable { case idle, arming, open, blocked }
    public enum Action: Equatable {
        case arm(CGPoint), show(CGPoint), hover(PingKind, angle: CGFloat?), hide, dismiss, commit(PingKind, CGPoint)
    }
    /// `consume` tells the event tap to keep a button event from the app below.
    public struct Response: Equatable {
        public var actions: [Action]
        public var consume: Bool
        public init(_ actions: [Action] = [], consume: Bool = false) { self.actions = actions; self.consume = consume }
    }
    public private(set) var phase: Phase = .idle
    public private(set) var selected: PingKind = .regular
    public private(set) var anchor: CGPoint = .zero
    public private(set) var currentModifiers: Modifiers = []
    /// A primary press DotaPing swallowed; its drags and release are swallowed too.
    public private(set) var ownsPrimaryPress = false
    public var trigger: Trigger = .controlOptionCommand
    public var deadZone: CGFloat = WheelGeometry.centerRadius
    private var center: CGPoint = .zero
    private var pointer: CGPoint = .zero
    public init() {}

    public func flagsChanged(_ flags: Modifiers, at point: CGPoint, otherInputHeld: Bool) -> [Action] {
        currentModifiers = flags
        // Modifiers only qualify the press; once the button is down, its release ends the gesture.
        if trigger.usesPrimaryButton { return [] }
        if phase == .blocked {
            if flags.intersection(trigger.modifiers).isEmpty { phase = .idle }
            return []
        }
        if phase == .idle {
            guard flags == trigger.modifiers else { return [] }
            guard !otherInputHeld else { phase = .blocked; return [] }
            begin(at: point)
            return [.arm(point)]
        }
        // Adding a fourth modifier is a different shortcut, never a commit.
        if !flags.subtracting(trigger.modifiers).isEmpty { return cancel() }
        if flags != trigger.modifiers {
            let wasOpen = phase == .open
            phase = flags.intersection(trigger.modifiers).isEmpty ? .idle : .blocked
            return wasOpen ? [.dismiss, .commit(selected, anchor)] : [.hide]
        }
        return []
    }

    public func delayElapsed() -> [Action] {
        guard phase == .arming else { return [] }
        if trigger.usesPrimaryButton { guard ownsPrimaryPress else { return [] } }
        else { guard currentModifiers == trigger.modifiers else { return [] } }
        phase = .open
        return [.show(anchor)]
    }

    public func setWheelCenter(_ point: CGPoint) -> [Action] {
        center = point
        // At an edge the wheel moves inwards, but the original ping anchor stays fixed.
        guard hypot(pointer.x - anchor.x, pointer.y - anchor.y) > 4 else { return [] }
        return moved(to: pointer)
    }

    public func moved(to point: CGPoint) -> [Action] {
        pointer = point
        guard phase == .open else { return [] }
        let next = WheelGeometry.selection(at: point, center: center, deadZone: deadZone)
        selected = next
        return [.hover(next, angle: WheelGeometry.direction(at: point, center: center, deadZone: deadZone))]
    }

    /// Primary button (left click, physical trackpad click or tap-to-click).
    public func primaryDown(at point: CGPoint, otherInputHeld: Bool) -> Response {
        if trigger.usesPrimaryButton {
            guard phase == .idle, !ownsPrimaryPress, !otherInputHeld else { return Response() }
            if currentModifiers == trigger.modifiers {
                begin(at: point); ownsPrimaryPress = true
                return Response([.arm(point)], consume: true)
            }
            if let warning = trigger.warningModifiers, currentModifiers == warning {
                ownsPrimaryPress = true
                return Response([.commit(.warning, point)], consume: true)
            }
            return Response()
        }
        guard phase == .open else { return Response(cancel()) }
        // A click or tap confirms. The chord must then be fully released before the next one.
        ownsPrimaryPress = true
        phase = .blocked
        return Response([.dismiss, .commit(selected, anchor)], consume: true)
    }

    public func primaryDragged(to point: CGPoint) -> Response {
        // Without a press of its own, a drag belongs to the app; keep the original cancel.
        guard ownsPrimaryPress else { return Response(cancel()) }
        return Response(moved(to: point), consume: true)
    }

    public func primaryUp(at point: CGPoint) -> Response {
        guard ownsPrimaryPress else { return Response() }
        ownsPrimaryPress = false
        guard trigger.usesPrimaryButton else { return Response(consume: true) }
        switch phase {
        case .arming:
            // Released before the wheel opened: an ordinary Option-click ping.
            phase = .idle
            return Response([.hide, .commit(.regular, anchor)], consume: true)
        case .open:
            phase = .idle
            return Response([.dismiss, .commit(selected, anchor)], consume: true)
        default:
            return Response(consume: true)
        }
    }

    public func cancel() -> [Action] {
        let hadGesture = phase == .arming || phase == .open
        if trigger.usesPrimaryButton { phase = .idle }
        else { phase = currentModifiers.intersection(trigger.modifiers).isEmpty ? .idle : .blocked }
        selected = .regular
        return hadGesture ? [.hide] : []
    }

    public func reset(blockUntilRelease: Bool = false, modifiers: Modifiers = []) {
        phase = blockUntilRelease ? .blocked : .idle
        selected = .regular
        currentModifiers = modifiers
        ownsPrimaryPress = false
    }

    private func begin(at point: CGPoint) {
        anchor = point; center = point; pointer = point; selected = .regular
        phase = .arming
    }
}
