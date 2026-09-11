import Foundation
import ScreenCaptureKit

/// Capture decisions kept free of UI state so the tests can check them.
enum CaptureSafety {
    /// True when the user ended capture from the system's screen-sharing
    /// control. That decision must be honored, never retried.
    static func isUserStop(_ error: Error) -> Bool {
        (error as? SCStreamError)?.code == .userStopped
    }
}

/// Seconds on a clock that never steps backwards and keeps counting through
/// sleep. Timeouts use it so a wall-clock change can't stretch or skip them.
enum Monotonic {
    static var now: TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

/// Decides when the live effect may show: only while the lid is moving. It
/// turns off once the lid has been still for 0.2 s, and at once when the
/// pointer is used (the warped picture doesn't line up with where clicks
/// land). Either way it returns on the next lid movement — never on a timer.
struct EffectGate {
    /// Lid travel, in degrees, that starts movement. Above one degree so
    /// sensor jitter on a still lid doesn't count.
    static let lidStartThreshold = 2.0
    /// Once moving, this much more travel in the same direction keeps the
    /// effect on, so a slow tilt doesn't flicker. Jitter flips direction, so
    /// it can't hold the effect on.
    static let lidContinueThreshold = 1.0
    /// The effect turns off once the lid has been still this long.
    static let lidStillTimeout: TimeInterval = 0.2
    /// A requested preview starts once it has waited this long and the pointer
    /// has been still this long, so the click that asked for it can't cancel it.
    static let previewSettle: TimeInterval = 0.5
    static let previewLength: TimeInterval = 8
    /// A preview whose pointer never settles is dropped, not started later.
    static let previewStartWindow: TimeInterval = 5

    private var lidReference: Double?
    private var lidDirection = 0.0
    private var lastLidMove = -TimeInterval.infinity
    private var lastPointerUse = -TimeInterval.infinity
    private var previewRequestedAt: TimeInterval?
    private var previewUntil = -TimeInterval.infinity

    mutating func requestPreview(at now: TimeInterval) {
        previewRequestedAt = now
    }

    func previewActive(at now: TimeInterval) -> Bool {
        now < previewUntil
    }

    private func lidMoving(at now: TimeInterval) -> Bool {
        lastLidMove > lastPointerUse && now - lastLidMove < Self.lidStillTimeout
    }

    /// Call once per update with monotonic time. Returns whether the effect may show.
    mutating func update(pointerUsed: Bool, lidAngle: Double, frameReady: Bool, now: TimeInterval) -> Bool {
        if pointerUsed {
            lastPointerUse = now
            // Only lid movement after the pointer use brings the effect back.
            lidReference = lidAngle
            previewUntil = -.infinity
        } else if let reference = lidReference {
            let delta = lidAngle - reference
            let continues = lidMoving(at: now) && abs(delta) >= Self.lidContinueThreshold
                && delta * lidDirection > 0
            if abs(delta) >= Self.lidStartThreshold || continues {
                lidReference = lidAngle
                lidDirection = delta > 0 ? 1 : -1
                lastLidMove = now
            }
        } else {
            // The first reading is a starting point, not a movement.
            lidReference = lidAngle
        }
        if let requestedAt = previewRequestedAt {
            if now - requestedAt > Self.previewStartWindow {
                previewRequestedAt = nil
            } else if frameReady, now - max(lastPointerUse, requestedAt) >= Self.previewSettle {
                // A preview is an explicit request, so it runs with the lid still.
                previewRequestedAt = nil
                previewUntil = now + Self.previewLength
            }
        }
        return lidMoving(at: now) || previewActive(at: now)
    }
}

/// Detects pointer use between updates: movement measured from where the
/// pointer last counted as used (so slow drift adds up), a held button, or a
/// click or scroll that began and ended between two updates.
struct PointerActivity {
    /// Pointer travel, in points, that counts as use.
    static let moveThreshold: CGFloat = 1

    private var reference: CGPoint?
    private var lastSecondsSinceInput = TimeInterval.infinity

    /// `secondsSinceInput` is the time since the last click or scroll anywhere;
    /// it drops whenever a new one happens.
    mutating func update(location: CGPoint, buttonsDown: Bool, secondsSinceInput: TimeInterval) -> Bool {
        defer { lastSecondsSinceInput = secondsSinceInput }
        guard let reference else {
            // The first reading is a starting point, not a movement.
            self.reference = location
            return buttonsDown
        }
        var used = buttonsDown || secondsSinceInput < lastSecondsSinceInput
        if abs(location.x - reference.x) + abs(location.y - reference.y) > Self.moveThreshold {
            self.reference = location
            used = true
        }
        return used
    }
}
