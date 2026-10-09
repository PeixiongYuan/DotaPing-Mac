import Foundation
import CoreGraphics
import CryptoKit
import PingCore

private var failures = 0
private var assertions = 0
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    if actual != expected {
        failures += 1
        print("FAIL \(file):\(line): \(actual) != \(expected)")
    }
}
private func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(value, true, file: file, line: line)
}
private typealias Response = GestureMachine.Response

final class GestureTests {
    let chord: Modifiers = [.control, .option, .command]
    let anchor = CGPoint(x: 600, y: 400)

    func open(_ machine: GestureMachine) {
        XCTAssertEqual(machine.flagsChanged(chord, at: anchor, otherInputHeld: false), [.arm(anchor)])
        XCTAssertEqual(machine.delayElapsed(), [.show(anchor)])
    }
    func dotaMachine() -> GestureMachine {
        let machine = GestureMachine(); machine.trigger = .optionClick; return machine
    }

    // MARK: Chord triggers

    func testEightDirectionsAndCentralDeadZone() {
        let vectors: [CGPoint] = [.init(x: 0,y: 100), .init(x: 100,y: 100), .init(x: 100,y: 0), .init(x: 100,y: -100),
                                  .init(x: 0,y: -100), .init(x: -100,y: -100), .init(x: -100,y: 0), .init(x: -100,y: 100)]
        for (index, vector) in vectors.enumerated() {
            XCTAssertEqual(WheelGeometry.selection(at: vector, center: .zero, deadZone: WheelGeometry.centerRadius), PingKind.wheel[index])
        }
        XCTAssertEqual(WheelGeometry.selection(at: CGPoint(x: 66, y: 0), center: .zero, deadZone: WheelGeometry.centerRadius), .regular)
        XCTAssertEqual(WheelGeometry.selection(at: CGPoint(x: 67, y: 0), center: .zero, deadZone: WheelGeometry.centerRadius), .onMyWay)
    }
    func testShortPressNeverPingsAndLateTimerDoesNothing() {
        let machine = GestureMachine()
        _ = machine.flagsChanged(chord, at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [.hide])
        XCTAssertEqual(machine.delayElapsed(), [])
    }
    func testReleaseCommitsExactlyOnceAtOriginalAnchor() {
        let machine = GestureMachine(); open(machine)
        XCTAssertEqual(machine.moved(to: CGPoint(x: 500, y: 400)), [.hover(.defend, angle: -.pi/2)])
        XCTAssertEqual(machine.flagsChanged([.control, .option], at: .zero, otherInputHeld: false), [.dismiss, .commit(.defend, anchor)])
        XCTAssertEqual(machine.flagsChanged([.option], at: .zero, otherInputHeld: false), [])
        XCTAssertEqual(machine.flagsChanged([], at: .zero, otherInputHeld: false), [])
        XCTAssertEqual(machine.phase, .idle)
    }
    func testAllReleaseOrdersCommitExactlyOnce() {
        let keys: [Modifiers] = [.control, .option, .command]
        for first in keys {
            for second in keys where second != first {
                let machine = GestureMachine(); open(machine)
                var remaining = chord
                var commits = 0
                for key in [first, second] + keys.filter({ $0 != first && $0 != second }) {
                    remaining.subtract(key)
                    for action in machine.flagsChanged(remaining, at: anchor, otherInputHeld: false) {
                        if case .commit = action { commits += 1 }
                    }
                }
                XCTAssertEqual(commits, 1)
                XCTAssertEqual(machine.phase, .idle)
            }
        }
    }
    func testRepressingOneKeyDoesNotCreateSecondPing() {
        let machine = GestureMachine(); open(machine)
        _ = machine.flagsChanged([.control, .option], at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.flagsChanged(chord, at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.delayElapsed(), [])
        _ = machine.flagsChanged([], at: anchor, otherInputHeld: false)
        open(machine)
    }
    func testCancelAndOtherShortcutsRequireFullRelease() {
        let machine = GestureMachine(); open(machine)
        XCTAssertEqual(machine.cancel(), [.hide])
        XCTAssertEqual(machine.flagsChanged([.option], at: anchor, otherInputHeld: false), [])
        _ = machine.flagsChanged(chord, at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.delayElapsed(), [])
        _ = machine.flagsChanged([], at: anchor, otherInputHeld: false)
        open(machine)
    }
    func testFourthModifierCancelsInsteadOfCommitting() {
        let machine = GestureMachine(); open(machine)
        XCTAssertEqual(machine.flagsChanged([.control, .option, .command, .shift], at: anchor, otherInputHeld: false), [.hide])
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [])
    }
    func testExistingDragOrKeyPressDoesNotArm() {
        let machine = GestureMachine()
        XCTAssertEqual(machine.flagsChanged(chord, at: anchor, otherInputHeld: true), [])
        XCTAssertEqual(machine.delayElapsed(), [])
        XCTAssertEqual(machine.phase, .blocked)
    }
    func testResetDuringAnimationCannotCommit() {
        let machine = GestureMachine(); open(machine)
        machine.reset()
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.delayElapsed(), [])
    }
    func testEdgeClampingPreservesActualPingLocation() {
        let machine = GestureMachine()
        let edge = CGPoint(x: -1915, y: 1080)
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let center = WheelGeometry.clampedCenter(anchor: edge, frame: display, radius: 150)
        XCTAssertEqual(center, CGPoint(x: -1770, y: 930))
        _ = machine.flagsChanged(chord, at: edge, otherInputHeld: false)
        _ = machine.delayElapsed()
        XCTAssertEqual(machine.setWheelCenter(center), [])
        _ = machine.moved(to: CGPoint(x: center.x+90, y: center.y))
        XCTAssertEqual(machine.flagsChanged([], at: edge, otherInputHeld: false), [.dismiss, .commit(.onMyWay, edge)])
    }
    func testMovementDuringArmingAppliedAfterWheelOpens() {
        let machine = GestureMachine()
        _ = machine.flagsChanged(chord, at: anchor, otherInputHeld: false)
        _ = machine.moved(to: CGPoint(x: 600, y: 300))
        _ = machine.delayElapsed()
        XCTAssertEqual(machine.setWheelCenter(anchor), [.hover(.assist, angle: .pi)])
    }
    func testEveryChordTrigger() {
        for trigger in Trigger.allCases where !trigger.usesPrimaryButton {
            let machine = GestureMachine(); machine.trigger = trigger
            XCTAssertEqual(machine.flagsChanged(trigger.modifiers, at: anchor, otherInputHeld: false), [.arm(anchor)])
            _ = machine.delayElapsed()
            XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [.dismiss, .commit(.regular, anchor)])
        }
    }
    func testContinuousDirectionAndCenterReset() {
        let machine = GestureMachine(); open(machine)
        let first = CGPoint(x: 600, y: 500), second = CGPoint(x: 610, y: 500)
        XCTAssertEqual(machine.moved(to: first), [.hover(.caution, angle: 0)])
        XCTAssertEqual(machine.moved(to: second), [.hover(.caution, angle: atan2(10, 100))])
        XCTAssertEqual(machine.selected, .caution)
        XCTAssertEqual(machine.moved(to: CGPoint(x: 600, y: 466)), [.hover(.regular, angle: nil)])
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [.dismiss, .commit(.regular, anchor)])
        XCTAssertEqual(machine.moved(to: first), [])
    }
    func testScaledCenterMatchesVisualCircle() {
        for scale: CGFloat in [0.75, 1, 1.5] {
            let machine = GestureMachine(); machine.deadZone = WheelGeometry.centerRadius*scale; open(machine)
            XCTAssertEqual(machine.moved(to: CGPoint(x: anchor.x+66*scale, y: anchor.y)), [.hover(.regular, angle: nil)])
            XCTAssertEqual(machine.moved(to: CGPoint(x: anchor.x+66*scale+0.01, y: anchor.y)), [.hover(.onMyWay, angle: .pi/2)])
        }
    }

    // MARK: Trackpad with a chord trigger

    func testTapConfirmsOnceAndSwallowsTheClick() {
        let machine = GestureMachine(); open(machine)
        _ = machine.moved(to: CGPoint(x: 680, y: 480))
        XCTAssertEqual(machine.primaryDown(at: CGPoint(x: 680, y: 480), otherInputHeld: false), Response([.dismiss, .commit(.attack, anchor)], consume: true))
        XCTAssertEqual(machine.primaryDragged(to: CGPoint(x: 690, y: 480)), Response(consume: true))
        XCTAssertEqual(machine.primaryUp(at: CGPoint(x: 690, y: 480)), Response(consume: true))
        // Releasing the chord afterwards must not send a second ping.
        XCTAssertEqual(machine.flagsChanged([.control], at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.flagsChanged(chord, at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.primaryUp(at: anchor), Response())
        open(machine)
    }
    func testClickBeforeWheelOpensIsAnotherShortcut() {
        let machine = GestureMachine()
        _ = machine.flagsChanged(chord, at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: false), Response([.hide]))
        XCTAssertEqual(machine.primaryUp(at: anchor), Response())
        XCTAssertEqual(machine.delayElapsed(), [])
        XCTAssertEqual(machine.phase, .blocked)
    }
    func testUnownedDragStillCancels() {
        let machine = GestureMachine(); open(machine)
        XCTAssertEqual(machine.primaryDragged(to: anchor), Response([.hide]))
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [])
    }

    // MARK: Option + primary button (the game's gesture)

    func testOptionClickPingsAtClickPoint() {
        let machine = dotaMachine()
        XCTAssertEqual(machine.flagsChanged([.option], at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: false), Response([.arm(anchor)], consume: true))
        XCTAssertEqual(machine.primaryUp(at: anchor), Response([.hide, .commit(.regular, anchor)], consume: true))
        XCTAssertEqual(machine.delayElapsed(), [])
        XCTAssertEqual(machine.phase, .idle)
    }
    func testOptionHoldOpensWheelAndReleaseSends() {
        let machine = dotaMachine()
        _ = machine.flagsChanged([.option], at: anchor, otherInputHeld: false)
        _ = machine.primaryDown(at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.delayElapsed(), [.show(anchor)])
        XCTAssertEqual(machine.setWheelCenter(anchor), [])
        // Physical trackpad press, three-finger drag and mouse drags all arrive as primary drags.
        XCTAssertEqual(machine.primaryDragged(to: CGPoint(x: 600, y: 300)), Response([.hover(.assist, angle: .pi)], consume: true))
        // Letting go of Option first keeps the wheel open; the button decides.
        XCTAssertEqual(machine.flagsChanged([], at: anchor, otherInputHeld: false), [])
        XCTAssertEqual(machine.primaryDragged(to: CGPoint(x: 520, y: 320)), Response([.hover(.friendlyWard, angle: atan2(-80, -80))], consume: true))
        XCTAssertEqual(machine.primaryUp(at: CGPoint(x: 520, y: 320)), Response([.dismiss, .commit(.friendlyWard, anchor)], consume: true))
        XCTAssertEqual(machine.primaryUp(at: anchor), Response())
    }
    func testControlOptionClickSendsWarningOnce() {
        let machine = dotaMachine()
        _ = machine.flagsChanged([.control, .option], at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: false), Response([.commit(.warning, anchor)], consume: true))
        XCTAssertEqual(machine.delayElapsed(), [])
        XCTAssertEqual(machine.primaryDragged(to: CGPoint(x: 700, y: 400)), Response(consume: true))
        XCTAssertEqual(machine.primaryUp(at: anchor), Response(consume: true))
    }
    func testOtherClicksPassThrough() {
        for flags: Modifiers in [[], [.command], [.option, .command], [.option, .shift], [.control]] {
            let machine = dotaMachine()
            _ = machine.flagsChanged(flags, at: anchor, otherInputHeld: false)
            XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: false), Response())
            XCTAssertEqual(machine.primaryUp(at: anchor), Response())
        }
        let machine = dotaMachine()
        _ = machine.flagsChanged([.option], at: anchor, otherInputHeld: false)
        XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: true), Response())
    }
    func testCancelWhileHoldingSwallowsRelease() {
        let machine = dotaMachine()
        _ = machine.flagsChanged([.option], at: anchor, otherInputHeld: false)
        _ = machine.primaryDown(at: anchor, otherInputHeld: false)
        _ = machine.delayElapsed()
        _ = machine.primaryDragged(to: CGPoint(x: 600, y: 500))
        XCTAssertEqual(machine.cancel(), [.hide])
        XCTAssertEqual(machine.primaryDragged(to: CGPoint(x: 600, y: 520)), Response(consume: true))
        XCTAssertEqual(machine.primaryUp(at: anchor), Response(consume: true))
        XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: false), Response([.arm(anchor)], consume: true))
    }
    func testOptionClickAfterResetUsesHeldModifiers() {
        let machine = dotaMachine()
        machine.reset(modifiers: [.option])
        XCTAssertEqual(machine.primaryDown(at: anchor, otherInputHeld: false), Response([.arm(anchor)], consume: true))
        machine.reset()
        XCTAssertEqual(machine.primaryUp(at: anchor), Response())
        XCTAssertEqual(machine.delayElapsed(), [])
    }

    // MARK: Data, artwork and audio

    func testGameDataAndColors() {
        XCTAssertEqual(PingKind.wheel.count, 8)
        XCTAssertEqual(Set(PingKind.wheel).count, 8)
        XCTAssertTrue(!PingKind.wheel.contains(.regular))
        XCTAssertEqual(PingKind.caution.fixedColor, RGB(255, 155, 14))
        XCTAssertEqual(PingKind.enemyWard.color(for: .pink), RGB(225, 51, 51))
        XCTAssertEqual(PingKind.attack.color(for: .pink), PlayerColor.pink.rgb)
        XCTAssertEqual(Set(PlayerColor.allCases.map(\.rgb)).count, 10)
        XCTAssertEqual(PlayerColor.allCases.filter(\.isRadiant).count, 5)
        XCTAssertEqual(Set(PingKind.allCases.map(\.soundName)), Set(SoundSynth.names))
    }
    func testBothLanguagesAreComplete() {
        // English names are the game's dota_pingwheel_* strings.
        XCTAssertEqual(PingKind.wheel.map { $0.title(.english) },
                       ["Caution", "Attack", "On My Way", "Warning", "Assist", "Friendly Ward", "Defend", "Enemy Ward"])
        for language in Language.allCases {
            XCTAssertEqual(Set(PingKind.allCases.map { $0.title(language) }).count, 9)
            XCTAssertEqual(PingKind.allCases.compactMap { $0.chat(language) }.count, 7)
            XCTAssertEqual(Set(PlayerColor.allCases.map { $0.title(language) }).count, 10)
            XCTAssertEqual(Set(Trigger.allCases.map { $0.title(language) }).count, 4)
            XCTAssertTrue(Trigger.allCases.allSatisfy { !$0.usage(language).isEmpty && !$0.ready(language).isEmpty })
        }
        XCTAssertEqual(PingKind.friendlyWard.chat(.chinese), "我们需要视野")
        XCTAssertEqual(Language(rawValue: "missing") ?? .english, .english)
    }
    func testWAVRoundTrip() {
        let pcm = PCM(sampleRate: 44_100, channels: [[0, 0.5, -0.5, 1], [0.25, -0.25, 0, -1]])
        let decoded = WAV.decode(WAV.encode(pcm))
        XCTAssertEqual(decoded?.sampleRate, 44_100)
        XCTAssertEqual(decoded?.channels.count, 2)
        let error = zip(Array(pcm.channels.joined()), Array((decoded?.channels ?? []).joined())).map { abs($0-$1) }.max() ?? 1
        XCTAssertTrue(error < 0.0001)
        XCTAssertTrue(WAV.decode(Data("not audio".utf8)) == nil)
        XCTAssertEqual(WAV.decode(SoundSynth.wav("ping"))?.frameCount, SoundSynth.samples("ping").count)
    }
    func testGameSoundRecipesFollowTheSoundEvents() {
        XCTAssertEqual(Set(GameSoundRecipe.all.map(\.output)), Set(SoundSynth.names))
        XCTAssertEqual(GameSoundRecipe.files, ["ping.wav", "ping_attack.wav", "ping_attack_layer.wav", "ping_defense.wav",
                                              "ping_enemy_ward.wav", "ping_need_ward.wav", "ping_warning.wav", "ping_warning_layer.wav"])
        let ward = GameSoundRecipe.all.first { $0.output == "ping_enemy_ward" }!
        let quiet = ward.mix(main: PCM(sampleRate: 10, channels: [[0.6, -0.6]]), layer: nil)
        XCTAssertEqual(quiet.channels, [[0.3, -0.3]])
        // Attack layer: 0.95 pitch, 0.1 s late, 0.5/0.6 gain, on every channel of a stereo main.
        let attack = GameSoundRecipe.all.first { $0.output == "ping_attack" }!
        let main = PCM(sampleRate: 100, channels: [[Float](repeating: 0, count: 5), [Float](repeating: 0, count: 5)])
        let layer = PCM(sampleRate: 100, channels: [[Float](repeating: 0.6, count: 96)])
        let mixed = attack.mix(main: main, layer: layer)
        XCTAssertEqual(mixed.frameCount, 10 + Int(95/0.95) + 1)
        XCTAssertEqual(mixed.channels[1][9], 0)
        XCTAssertTrue(abs(mixed.channels[1][10] - 0.5) < 0.0001)
        // Loud mixes are scaled below clipping.
        let loud = attack.mix(main: PCM(sampleRate: 100, channels: [[1, 1]]), layer: nil)
        XCTAssertTrue(abs((loud.channels[0].max() ?? 0) - 0.98) < 0.0001)
    }
    /// Run from the repository root (scripts/test.sh does this).
    func testBundledGameSoundsMatchTheirSources() {
        struct Manifest: Decodable { struct File: Decodable { let path: String; let sha256: String }; let files: [File] }
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        guard let json = try? Data(contentsOf: resources.appendingPathComponent("asset-sources.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: json) else { XCTAssertTrue(false); return }
        XCTAssertEqual(Set(manifest.files.map { URL(fileURLWithPath: $0.path).lastPathComponent }), Set(GameSoundRecipe.files))
        var sources: [String: PCM] = [:]
        for file in manifest.files {
            let data = (try? Data(contentsOf: resources.appendingPathComponent(file.path))) ?? Data()
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), file.sha256)
            sources[URL(fileURLWithPath: file.path).lastPathComponent] = WAV.decode(data)
        }
        // Mixed lengths follow the layer settings: Attack 0.1 s + 1.605 s / 0.95, Warning 2.35 s / 1.25.
        for (cue, seconds) in [("ping", 1.9987), ("ping_attack", 1.7894), ("ping_warning", 1.88), ("ping_enemy_ward", 2.9397)] {
            let recipe = GameSoundRecipe.all.first { $0.output == cue }!
            guard let main = sources[recipe.file] else { XCTAssertTrue(false); continue }
            let mixed = recipe.mix(main: main, layer: recipe.layer.flatMap { sources[$0.file] })
            XCTAssertTrue(abs(Double(mixed.frameCount)/Double(mixed.sampleRate) - seconds) < 0.001)
            XCTAssertTrue(mixed.channels.joined().allSatisfy { abs($0) <= 0.98 })
        }
    }
    func testGlyphsFitTheUnitSquare() {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001)
        for kind in PingKind.allCases {
            let box = Glyphs.glyph(kind).path.boundingBoxOfPath
            XCTAssertTrue(unit.contains(box))
            XCTAssertTrue(max(box.width, box.height) > 0.8 && min(box.width, box.height) > 0.35)
        }
    }
    func testSynthesisedCuesAreShortAndClean() {
        for name in SoundSynth.names {
            let samples = SoundSynth.samples(name)
            let seconds = Double(samples.count)/Double(SoundSynth.sampleRate)
            XCTAssertTrue(seconds > 0.3 && seconds < 1.0)
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            XCTAssertTrue(peak > 0.8 && peak <= 0.83)
            // Silent at both ends: no clicks.
            XCTAssertTrue(abs(samples.first ?? 1) < 0.01 && abs(samples.last ?? 1) < 0.01)
            let wav = SoundSynth.wav(name)
            XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(wav.count, 44 + samples.count*2)
        }
        XCTAssertTrue(SoundSynth.samples("unknown").isEmpty)
    }
}

@main
enum Checks {
    static func main() {
        let test = GestureTests()
        let scenarios: [(String, () -> Void)] = [
            ("Eight directions and centre zone", test.testEightDirectionsAndCentralDeadZone),
            ("Short press never pings", test.testShortPressNeverPingsAndLateTimerDoesNothing),
            ("Sends once at the original anchor", test.testReleaseCommitsExactlyOnceAtOriginalAnchor),
            ("Every key-release order", test.testAllReleaseOrdersCommitExactlyOnce),
            ("Re-pressing a key does not send again", test.testRepressingOneKeyDoesNotCreateSecondPing),
            ("Cancel requires a full release", test.testCancelAndOtherShortcutsRequireFullRelease),
            ("Extra modifier cancels", test.testFourthModifierCancelsInsteadOfCommitting),
            ("Existing drag or key press does not arm", test.testExistingDragOrKeyPressDoesNotArm),
            ("No commit after reset", test.testResetDuringAnimationCannotCommit),
            ("Multi-display coordinates and edge anchor", test.testEdgeClampingPreservesActualPingLocation),
            ("Pointer movement during the delay", test.testMovementDuringArmingAppliedAfterWheelOpens),
            ("Every chord trigger", test.testEveryChordTrigger),
            ("Direction updates and return to centre", test.testContinuousDirectionAndCenterReset),
            ("Scaled centre zone matches the drawing", test.testScaledCenterMatchesVisualCircle),
            ("Trackpad tap confirms once", test.testTapConfirmsOnceAndSwallowsTheClick),
            ("Click before the wheel opens passes through", test.testClickBeforeWheelOpensIsAnotherShortcut),
            ("Foreign drag still cancels", test.testUnownedDragStillCancels),
            ("⌥-click sends a Ping", test.testOptionClickPingsAtClickPoint),
            ("⌥-hold, drag and release", test.testOptionHoldOpensWheelAndReleaseSends),
            ("⌃⌥-click sends one Warning", test.testControlOptionClickSendsWarningOnce),
            ("Other clicks pass through", test.testOtherClicksPassThrough),
            ("Cancel while held swallows the release", test.testCancelWhileHoldingSwallowsRelease),
            ("⌥ already held when enabled", test.testOptionClickAfterResetUsesHeldModifiers),
            ("Game data and player colours", test.testGameDataAndColors),
            ("Both languages complete", test.testBothLanguagesAreComplete),
            ("WAV encode and decode", test.testWAVRoundTrip),
            ("Game sound mixing follows the sound events", test.testGameSoundRecipesFollowTheSoundEvents),
            ("Bundled game sounds match their sources", test.testBundledGameSoundsMatchTheirSources),
            ("Glyphs fit the unit square", test.testGlyphsFitTheUnitSquare),
            ("Synthesised cues are short and click-free", test.testSynthesisedCuesAreShortAndClean)
        ]
        for (name, scenario) in scenarios {
            let before = failures
            scenario()
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(scenarios.count) scenarios, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
