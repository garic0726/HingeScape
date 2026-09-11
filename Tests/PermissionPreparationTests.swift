import Foundation
import ScreenCaptureKit

@main
struct PermissionPreparationTests {
    // Not assert(): that is compiled out under -O and would pass vacuously.
    static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        let suite = "app.hingescape.permission-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        typealias Preparation = ScreenCapturePermissionPreparation
        check(Preparation.needsReset(identity: "build-a", defaults: defaults), "first launch needs reset")
        // A failure does not write a successful migration marker.
        check(Preparation.needsReset(identity: "build-a", defaults: defaults), "failed reset retried")
        Preparation.recordSuccess(identity: "build-a", defaults: defaults)
        check(!Preparation.needsReset(identity: "build-a", defaults: defaults), "success recorded")
        let reopened = UserDefaults(suiteName: suite)!
        check(!Preparation.needsReset(identity: "build-a", defaults: reopened), "marker persisted")
        check(Preparation.needsReset(identity: "build-b", defaults: reopened), "new build needs reset")
        Preparation.recordSuccess(identity: "build-b", defaults: reopened)
        check(!Preparation.needsReset(identity: "build-b", defaults: reopened), "new build recorded")

        // tccutil must never run without a client: that resets every app.
        check(Preparation.resetArguments(for: "") == nil, "empty client rejected")
        check(Preparation.resetArguments(for: " \n") == nil, "blank client rejected")
        check(Preparation.resetArguments(for: Preparation.bundleID)
              == ["reset", "ScreenCapture", "app.hingescape.mac"], "reset scoped to this app")

        // A stop from the system's screen-sharing control ends capture for good.
        check(CaptureSafety.isUserStop(SCStreamError(.userStopped)), "user stop recognized")
        check(CaptureSafety.isUserStop(NSError(domain: SCStreamErrorDomain,
                                               code: SCStreamError.Code.userStopped.rawValue)),
              "user stop recognized from NSError")
        check(!CaptureSafety.isUserStop(SCStreamError(.internalError)), "other stream errors still retried")
        check(!CaptureSafety.isUserStop(NSError(domain: NSCocoaErrorDomain,
                                                code: SCStreamError.Code.userStopped.rawValue)),
              "same code from another domain ignored")

        // Timeouts use a clock that never steps backwards.
        let first = Monotonic.now, second = Monotonic.now
        check(first > 0 && second >= first, "monotonic clock advances")

        // The effect shows only while the lid moves; it never returns on a timer.
        let t0: TimeInterval = 1000
        var gate = EffectGate()
        check(!gate.update(pointerUsed: false, lidAngle: 100, frameReady: true, now: t0), "off before the lid moves")
        check(!gate.update(pointerUsed: false, lidAngle: 101, frameReady: true, now: t0 + 0.1), "1° jitter isn't movement")
        check(gate.update(pointerUsed: false, lidAngle: 98, frameReady: true, now: t0 + 0.2), "lid movement shows it")
        check(gate.update(pointerUsed: false, lidAngle: 98, frameReady: true, now: t0 + 0.35), "on 0.15 s after stopping")
        check(!gate.update(pointerUsed: false, lidAngle: 98, frameReady: true, now: t0 + 0.45), "off once still for 0.2 s")
        check(!gate.update(pointerUsed: false, lidAngle: 99, frameReady: true, now: t0 + 60), "stays off: no timer, 1° not enough")
        check(gate.update(pointerUsed: false, lidAngle: 96, frameReady: true, now: t0 + 61), "next lid movement brings it back")
        check(gate.update(pointerUsed: false, lidAngle: 94, frameReady: true, now: t0 + 61.4), "keeps showing while moving")
        check(gate.update(pointerUsed: false, lidAngle: 94, frameReady: true, now: t0 + 61.55), "…between readings too")
        check(gate.update(pointerUsed: false, lidAngle: 92, frameReady: true, now: t0 + 61.6), "…still moving")

        // Pointer use turns it off at once; only lid movement after it brings it back.
        check(!gate.update(pointerUsed: true, lidAngle: 91, frameReady: true, now: t0 + 61.9), "pointer use turns it off")
        check(!gate.update(pointerUsed: false, lidAngle: 90, frameReady: true, now: t0 + 62.0), "1° after pointer use isn't enough")
        check(gate.update(pointerUsed: false, lidAngle: 89, frameReady: true, now: t0 + 62.1), "2° after pointer use brings it back")

        // A slow tilt stays on: once moving, each further 1° the same way counts.
        var slow = EffectGate()
        _ = slow.update(pointerUsed: false, lidAngle: 100, frameReady: true, now: t0)
        check(slow.update(pointerUsed: false, lidAngle: 98, frameReady: true, now: t0 + 0.1), "slow tilt starts with 2°")
        check(slow.update(pointerUsed: false, lidAngle: 97, frameReady: true, now: t0 + 0.25), "1° more the same way")
        check(slow.update(pointerUsed: false, lidAngle: 97, frameReady: true, now: t0 + 0.4),
              "…keeps it on past 0.2 s from the 2° start")
        check(slow.update(pointerUsed: false, lidAngle: 96, frameReady: true, now: t0 + 0.44), "…and again")
        check(slow.update(pointerUsed: false, lidAngle: 96, frameReady: true, now: t0 + 0.58), "…on between steps")
        check(slow.update(pointerUsed: false, lidAngle: 97, frameReady: true, now: t0 + 0.6), "1° back: on until the timeout")
        check(!slow.update(pointerUsed: false, lidAngle: 96, frameReady: true, now: t0 + 0.66), "…but it doesn't extend it")

        // Sensor flicker on a still lid flips direction, so it can't hold the effect on.
        var jitter = EffectGate()
        _ = jitter.update(pointerUsed: false, lidAngle: 100, frameReady: true, now: t0)
        _ = jitter.update(pointerUsed: false, lidAngle: 98, frameReady: true, now: t0 + 0.1)
        _ = jitter.update(pointerUsed: false, lidAngle: 97, frameReady: true, now: t0 + 0.3)
        for step in 1...20 {
            _ = jitter.update(pointerUsed: false, lidAngle: step % 2 == 0 ? 97 : 98, frameReady: true,
                              now: t0 + 0.3 + Double(step) * 0.1)
        }
        check(!jitter.update(pointerUsed: false, lidAngle: 98, frameReady: true, now: t0 + 2.4),
              "flicker on a still lid can't hold it on")

        // Pointer use: slow drift adds up; clicks and scrolls count even between checks.
        var pointer = PointerActivity()
        check(!pointer.update(location: CGPoint(x: 100, y: 100), buttonsDown: false, secondsSinceInput: 50),
              "first pointer reading is a starting point")
        check(!pointer.update(location: CGPoint(x: 100.4, y: 100), buttonsDown: false, secondsSinceInput: 50.1),
              "0.4 pt isn't use yet")
        check(!pointer.update(location: CGPoint(x: 100.8, y: 100), buttonsDown: false, secondsSinceInput: 50.2),
              "0.8 pt in total isn't either")
        check(pointer.update(location: CGPoint(x: 101.2, y: 100), buttonsDown: false, secondsSinceInput: 50.3),
              "slow drift past 1 pt counts")
        check(!pointer.update(location: CGPoint(x: 101.2, y: 100), buttonsDown: false, secondsSinceInput: 50.4),
              "a still pointer isn't use")
        check(pointer.update(location: CGPoint(x: 101.2, y: 100), buttonsDown: true, secondsSinceInput: 50.5),
              "a held button counts")
        check(pointer.update(location: CGPoint(x: 101.2, y: 100), buttonsDown: false, secondsSinceInput: 0.01),
              "a click or scroll since the last check counts")
        check(!pointer.update(location: CGPoint(x: 101.2, y: 100), buttonsDown: false, secondsSinceInput: 0.03),
              "…once")

        // A preview starts once the pointer settles after the click; pointer use ends it.
        var preview = EffectGate()
        _ = preview.update(pointerUsed: true, lidAngle: 120, frameReady: true, now: t0)
        preview.requestPreview(at: t0)
        _ = preview.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 0.2)
        check(!preview.previewActive(at: t0 + 0.2), "preview waits for the pointer to settle")
        _ = preview.update(pointerUsed: false, lidAngle: 120, frameReady: false, now: t0 + 0.6)
        check(!preview.previewActive(at: t0 + 0.6), "preview waits for a current frame")
        check(preview.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 0.7), "settled preview shows")
        check(preview.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 5), "preview runs with the lid still")
        check(!preview.update(pointerUsed: true, lidAngle: 120, frameReady: true, now: t0 + 6), "pointer use hides preview")
        check(!preview.previewActive(at: t0 + 6), "pointer use ends preview")
        check(!preview.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 20), "ended preview stays off")

        // Even with no pointer use seen yet, a preview waits the settle time,
        // so movement in the first update can still be noticed.
        var fresh = EffectGate()
        fresh.requestPreview(at: t0)
        _ = fresh.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 0.1)
        check(!fresh.previewActive(at: t0 + 0.1), "preview waits after request")
        _ = fresh.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 0.5)
        check(fresh.previewActive(at: t0 + 0.5), "preview starts after settle time")
        check(!fresh.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 8.6),
              "after 8 s with the lid still, the effect turns off")

        // A preview whose pointer never settles is dropped, not started later.
        var busy = EffectGate()
        busy.requestPreview(at: t0)
        for step in 0...60 {
            _ = busy.update(pointerUsed: true, lidAngle: 120, frameReady: true, now: t0 + Double(step) * 0.1)
        }
        _ = busy.update(pointerUsed: false, lidAngle: 120, frameReady: true, now: t0 + 7)
        check(!busy.previewActive(at: t0 + 7), "stale preview request dropped")

        print("PASS: permission marker, scoped tccutil arguments, user-stopped capture, effect gate, pointer activity")
    }
}
