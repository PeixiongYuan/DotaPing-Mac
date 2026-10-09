import AppKit
import ApplicationServices
import PingCore

final class GlobalInput {
    enum StartError: Error { case permission, eventTap }
    let machine = GestureMachine()
    var onAction: ((GestureMachine.Action) -> Void)?
    var onUnavailable: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var keysDown: Set<Int64> = []
    private var swallowedKeys: Set<Int64> = []
    private var swallowedRight = false
    private var recoveryAttempts = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start(trigger: Trigger, scale: Double) throws {
        stop()
        guard Self.isTrusted else { throw StartError.permission }
        machine.trigger = trigger
        machine.deadZone = WheelGeometry.centerRadius*scale
        let held = Self.modifiers(CGEventSource.flagsState(.combinedSessionState))
        machine.reset(blockUntilRelease: !trigger.usesPrimaryButton && !held.intersection(trigger.modifiers).isEmpty, modifiers: held)
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .mouseMoved,
                                   .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                   .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                   .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let input = Unmanaged<GlobalInput>.fromOpaque(context).takeUnretainedValue()
            return input.receive(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: mask, callback: callback,
                                            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw StartError.eventTap
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: newTap, enable: true)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        keysDown.removeAll(); swallowedKeys.removeAll(); swallowedRight = false; recoveryAttempts = 0
        machine.reset()
    }

    func cancelCurrent() {
        timer?.invalidate(); timer = nil
        dispatch(machine.cancel())
    }
    func setWheelCenter(_ center: CGPoint) { dispatch(machine.setWheelCenter(center)) }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var result: Modifiers = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
    private func point(_ event: CGEvent) -> CGPoint {
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: event.location.x, y: mainTop-event.location.y)
    }
    private var active: Bool { machine.phase == .arming || machine.phase == .open }
    private func receive(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelCurrent()
            recoveryAttempts += 1
            if recoveryAttempts <= 2, Self.isTrusted, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            else { DispatchQueue.main.async { [weak self] in self?.onUnavailable?() } }
            return false
        }
        recoveryAttempts = 0
        switch type {
        case .flagsChanged:
            let held = NSEvent.pressedMouseButtons != 0 || !keysDown.isEmpty
            dispatch(machine.flagsChanged(Self.modifiers(event.flags), at: point(event), otherInputHeld: held))
        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            keysDown.insert(key)
            let wasActive = active
            if swallowedKeys.contains(key) { return true }
            cancelCurrent()
            if wasActive && key == 53 { swallowedKeys.insert(key); return true }
        case .keyUp:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            keysDown.remove(key)
            if swallowedKeys.remove(key) != nil { return true }
        case .mouseMoved:
            dispatch(machine.moved(to: point(event)))
        case .leftMouseDown:
            // The left button itself may already be listed; only other buttons count.
            let held = !keysDown.isEmpty || NSEvent.pressedMouseButtons & ~1 != 0
            return respond(machine.primaryDown(at: point(event), otherInputHeld: held))
        case .leftMouseDragged:
            return respond(machine.primaryDragged(to: point(event)))
        case .leftMouseUp:
            return respond(machine.primaryUp(at: point(event)))
        case .rightMouseDown:
            // Includes a two-finger tap or click on a trackpad.
            let wasActive = active
            cancelCurrent()
            if wasActive { swallowedRight = true; return true }
        case .rightMouseUp:
            if swallowedRight { swallowedRight = false; return true }
        case .rightMouseDragged:
            if swallowedRight { return true }
        case .otherMouseDown, .otherMouseDragged:
            cancelCurrent()
        case .scrollWheel:
            // Trackpads keep sending momentum scrolls after a flick, and two
            // resting fingers can scroll slightly. Never cancel on them; while
            // the wheel is visible keep them from scrolling the app below.
            return machine.phase == .open
        default: break
        }
        return false
    }
    private func respond(_ response: GestureMachine.Response) -> Bool {
        dispatch(response.actions)
        return response.consume
    }
    private func dispatch(_ actions: [GestureMachine.Action]) {
        for action in actions {
            switch action {
            case .arm:
                timer?.invalidate()
                let next = Timer(timeInterval: 0.18, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.timer = nil
                    self.dispatch(self.machine.delayElapsed())
                }
                timer = next; RunLoop.main.add(next, forMode: .common)
            case .hide, .dismiss:
                timer?.invalidate(); timer = nil
                onAction?(action)
            default: onAction?(action)
            }
        }
    }
}
