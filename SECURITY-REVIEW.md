# HingeScape — Security & Safety Review

**Date:** 2026-09-11
**Scope:** every file in this folder (7 Swift sources, 1 test, `build.sh`, `Info.plist`, docs, icon assets)
**Result:** No malicious behavior found. No networking, no frame storage, no permissions beyond Screen Recording. Several safety and privacy issues in how capture and the overlay behave.

**Status (2026-09-11):** 9 fixed, 2 mitigated as far as the design allows (#5, #9). See [Remediation](#remediation-2026-09-11). A [second review](#second-review-2026-09-11) of the fixed code found 9 more issues, all fixed. The findings further down describe the code as first reviewed; their line numbers refer to that pre-fix version. The permission inventory reflects the current code.

---

## Remediation (2026-09-11)

| # | Status | Change | Verified by |
|---|---|---|---|
| 1 | Fixed | `didStopWithError` ends live mode when `CaptureSafety.isUserStop` sees `SCStreamError.userStopped`; other errors still retry | `test.sh` (4 cases, incl. bridged `NSError`) |
| 2 | Fixed | `suspend()` always hides the overlay; GLOBAL-README rewritten to match the code | Code review; needs live test |
| 3 | Fixed | `build.sh` signs with `--options runtime` (dropped `--deep`) | `codesign -dv` shows `runtime`; injection test: a test library ran under the old signing and was blocked under the new |
| 4 | Fixed | ⌘⇧Esc registered for the app's lifetime; ⌘⇧G/⌘⇧K registered only while live mode is wanted; menu and setup text updated | Code review; needs live test |
| 5 | Mitigated | The overlay shows only while the lid moves (`EffectGate`). After 0.2 s of lid stillness, the texture and overlay fade out together over 0.15 s. It turns off at once on pointer use: any movement (slow drift included), a held button, or a click or scroll (`PointerActivity`). Only the next lid move (≥ 2°) brings it back. The 8 s preview starts once 0.5 s have passed with the pointer still and ends on pointer use. **Residual** (limited to moments when the lid is moving): dialogs confirmed with the keyboard while the effect shows; the privacy indicator is still covered by a copy of itself | `test.sh` (stillness, jitter, slow tilt, pointer drift, click/scroll, preview); needs live test |
| 6 | Fixed | Automatic TCC reset was removed from application startup. The retained legacy helper still refuses an empty or blank client and is covered by tests, but is not invoked by HingeScape | `test.sh`; call-site review |
| 7 | Fixed | Vendor-agnostic sensor match removed (Apple `0x05AC` only) | Code review; sensor read in harness |
| 8 | Fixed | New `frameIsCurrent` gate: after a Space change, sleep, lock, display change, or restart, the overlay waits for a fresh frame. Real screen-lock handling added (`com.apple.screenIsLocked`/`Unlocked`); inaccurate comment corrected | Code review; needs live test |
| 9 | Mostly fixed | Sensor polled at 30 Hz only while the test page or live mode needs it, and publishes only changes. While hidden, the renderer keeps only the newest frame (no upload, no draw) and snaps to the target angle. Capture drops to 5 fps while the overlay is hidden and returns to 30 fps while it shows. **Residual, by design:** the capture stream keeps running while live mode is on (recording indicator stays lit), so the effect can appear as soon as the lid moves | Harness, renderer probe |
| 10 | Fixed | Fallback window frame instead of `screens.first!`; the hotkey handler holds a retained reference | Build |
| 11 | Fixed | `build.sh` pins the target from `Info.plist` (binary `minos 14.0`) and outputs to `build/`; `test.sh` builds with `-O` using explicit checks; docs updated; dead code removed | `vtool`, `test.sh` |

**Checks run after the fixes:**
- Clean build with no warnings.
- `test.sh` passes.
- Swift 6 strict-concurrency check: same 5 benign warnings as before, none new.
- A headless harness signed with Hardened Runtime, which does not launch the app. It confirmed that the Metal shader compiles, the renderer does no draw work while hidden, the lid sensor reads, and the code identity is readable.

**Not verified end to end.** Scenarios that need a granted Screen Recording permission and real lid movement require a physical MacBook test. HingeScape does not reset Screen Recording permission automatically.

## Second review (2026-09-11)

A review of the fixed and modified code (motion-only effect, pointer rule, and monotonic timeout). All items are fixed.

| # | Severity | Issue | Fix | Verified by |
|---|---|---|---|---|
| S1 | Medium | Timeouts used the wall clock. A backward clock step could delay pointer dismissal and the stillness rule | All timeouts (effect gate, sensor staleness, first frame, retry backoff) use a monotonic clock that never steps back (`Monotonic`, `CLOCK_MONOTONIC`) | Probe reproduced the bug before the fix; gate now takes monotonic seconds |
| S2 | Medium | Pointer movement slower than about 60 pt/s never counted as use; only the click itself was caught, after it landed | Movement is measured from where the pointer last counted as used, so slow drift adds up (`PointerActivity`) | `test.sh`; mutation restoring the old per-tick check fails |
| S3 | Low | If the first frame's upload failed, the black overlay panel could be shown with nothing drawn | `prepareToShow()` returns false without a real picture; the overlay stays hidden | Renderer probe with an un-uploadable frame |
| S4 | Low (UX) | The effect jumped between warped and normal at full tilt on every stop and restart | The texture and overlay fade out together after the stillness gate; appearance begins from a prepared flat frame. Pointer use and failure paths still hide at once | Build and renderer review; needs live test |
| S5 | Low (UX) | Tilts slower than about 5°/s flickered on and off | Starting still needs 2°; once moving, each further 1° in the same direction keeps it on. Sensor jitter flips direction, so it can't hold the effect on | `test.sh` (slow tilt, jitter); 3 mutations fail |
| S6 | Low | Capture ran at 30 fps while the overlay was hidden most of the time | 5 fps while hidden, 30 fps while shown (`updateConfiguration`); the first frame of an appearance may be up to about 0.2 s old | Build; needs live test |
| S7 | Low | The hidden overlay was told to hide 60 times a second | Hides only if visible | Code review |
| S8 | Low | Clicks and scrolls between two checks weren't noticed (scrolling acted on hidden UI; very short taps could be missed) | Reads the time since the last click or scroll (`CGEventSource.secondsSinceLastEventType`): timing only, no event monitor, no permission; about 0.1% of a CPU core | Probe on this Mac; `test.sh` |
| S9 | Docs | This file's permission inventory had stale line links and missed the new pointer/lock inputs | Inventory rewritten for the current code | — |

Found while verifying: attaching or resizing the hidden overlay un-paused the renderer, which could then spin with nothing to draw. The renderer now stays paused while hidden and pauses whenever it has no picture (renderer probe).

**Checks run after the second round:** clean build (Hardened Runtime, `minos 14.0`); `test.sh` passes; 7 targeted mutations of the new logic all fail the tests; renderer probe passes; Swift 6 strict check shows the same 5 benign warnings.

### Manual test checklist

1. `./build.sh && open "build/HingeScape.app"`. Enable live mode, grant Screen Recording, and relaunch if macOS asks.
2. Tilt the lid forward: the effect grows in while the lid moves, including a slow tilt, then begins fading after 0.2 s of stillness and disappears over 0.15 s. Move the lid again: it returns. While it shows, move the pointer slowly, click, or scroll: it turns off at once and stays off until the lid moves. From the menu bar, choose **Preview Live Effect (8 Seconds)**: the effect appears once the pointer is still, stays for eight seconds, and moving the pointer ends it. (#5, S2, S4, S5, S8)
3. While the effect shows, stop the recording from the menu-bar screen-sharing control. The overlay disappears, the status says stopped, and capture does not restart. (#1)
4. With live mode off, press ⌘⇧G in Finder: "Go to Folder" opens. With live mode on, ⌘⇧G stops it. (#4)
5. While tilted, switch Spaces, change the display resolution in System Settings, and lock with ⌃⌘Q then unlock. No old picture flashes and no frozen overlay remains. (#2, #8)
6. ⌘⇧Esc stops everything at any time.

---

## Permission & capability inventory

| Capability | Mechanism | User prompt? | Location |
|---|---|---|---|
| Screen Recording | ScreenCaptureKit; built-in display only; no audio, no cursor; own app excluded; 30 fps while the effect shows, 5 fps otherwise | Yes (TCC) | [GlobalDesktopController.swift:202](Sources/GlobalDesktopController.swift#L202) |
| Legacy scoped TCC-reset helper | Retained for regression coverage but not called by the app | No | [ScreenCapturePermissionPreparation.swift](Sources/ScreenCapturePermissionPreparation.swift) |
| Lid-angle sensor | IOHID feature report (undocumented Apple sensor, Apple vendor ID only); read at 30 Hz only on the test page or in live mode | No | [LidAngleSensor.swift:83](Sources/LidAngleSensor.swift#L83) |
| Global hotkeys | Carbon `RegisterEventHotKey` — ⌘⇧Esc always; ⌘⇧G / ⌘⇧K only while live mode is on. Receives only these combos; not a keylogger | No | [GlobalDesktopController.swift:531](Sources/GlobalDesktopController.swift#L531) |
| Overlay above all apps, Spaces, fullscreen apps | `NSPanel`, level `popUpMenu + 1`, click-through | No | [GlobalDesktopController.swift:242](Sources/GlobalDesktopController.swift#L242) |
| Pointer position, held buttons, time since last click/scroll | `NSEvent.mouseLocation`, `NSEvent.pressedMouseButtons`, `CGEventSource.secondsSinceLastEventType` — polled only while live mode runs; positions and timings only, no event contents | No | [GlobalDesktopController.swift:433](Sources/GlobalDesktopController.swift#L433), [491](Sources/GlobalDesktopController.swift#L491) |
| Screen-lock state | `com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications | No | [GlobalDesktopController.swift:101](Sources/GlobalDesktopController.swift#L101) |
| Read another app's preferences | `UserDefaults(suiteName: "studio.prototype.HingeGlass")`, one `Double` | No | [AppModel.swift:45](Sources/AppModel.swift#L45) |

**Not used:** Accessibility, Input Monitoring, camera, microphone/audio capture, Full Disk Access, global event monitors or event taps, keyboard monitoring (only the hotkeys above are received), Keychain, networking, launch agents.

---

## Findings

### 1. HIGH — Capture auto-restarts after the user stops it in the system UI

- **Where:** [GlobalDesktopController.swift:404-415](Sources/GlobalDesktopController.swift#L404) → `suspend` → [recoverIfReady:289-294](Sources/GlobalDesktopController.swift#L289)
- **Problem:** Any stream stop is treated as a transient failure. When the user stops the recording from the macOS menu-bar screen-sharing control, the stream ends with `SCStreamError.userStopped`; the app suspends, and the 0.25 s recovery timer calls `start(automatically: true)`. `CGPreflightScreenCaptureAccess()` still passes (the grant wasn't revoked), so capture restarts silently. The first frame resets `recoveryFailures` to 0 ([line 399](Sources/GlobalDesktopController.swift#L399)), so the 3-retry limit never stops this loop.
- **Impact:** Overrides the user's explicit consent decision.
- **Fix:** Treat a user stop as a hard stop:
  ```swift
  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
      let userStopped = (error as? SCStreamError)?.code == .userStopped
      Task { @MainActor in
          guard self.stream === stream else { return }
          self.stream = nil
          if userStopped { stop(reason: "Screen Recording was stopped in macOS"); return }
          // ...existing retry logic
      }
  }
  ```

### 2. HIGH — Failsafes leave a frozen overlay covering the screen

- **Where:** [GlobalDesktopController.swift:251-269](Sources/GlobalDesktopController.swift#L251), specifically [line 257](Sources/GlobalDesktopController.swift#L257)
- **Problem:** `suspend()` only hides the overlay when the reason is a session switch. It also invalidates the update timer (lines 254-255), which is the only code that hides the overlay by angle. Every other failsafe path calls `suspend()` and leaves the overlay on screen:
  - capture error — [line 410](Sources/GlobalDesktopController.swift#L410) (image frozen: stream is gone)
  - hinge data stale > 2 s — [line 359](Sources/GlobalDesktopController.swift#L359) (warp frozen)
  - display change — [line 351](Sources/GlobalDesktopController.swift#L351)
  - no first frame after 8 s — [line 365](Sources/GlobalDesktopController.swift#L365)
  - wake retry — [line 241](Sources/GlobalDesktopController.swift#L241)
- **Impact:** A stale, warped full-screen image stays on top while mouse clicks pass through to the real, invisible UI → blind clicks on buttons, files, or dialogs. If the hinge sensor never recovers, the overlay stays until ⌘⇧Esc.
- **Contradicts docs:** [GLOBAL-README.md:19](GLOBAL-README.md) says the overlay is *removed* on capture error, 4 s without callback, 2 s without hinge data, sleep, or display change, and that it won't auto-restart after a screen change. The code suspends instead, uses an 8 s first-frame timeout, and does auto-restart after display changes.
- **Fix:** Make line 257 unconditional (`overlay?.orderOut(nil)`). `resumeRendering()` → `update()` already re-shows it when conditions are met. Then update GLOBAL-README to match the actual behavior.

### 3. MEDIUM — No Hardened Runtime on an app that holds Screen Recording

- **Where:** [build.sh:29](build.sh#L29) — `codesign --force --deep --sign -`
- **Problem:** Ad-hoc signed without Hardened Runtime, so the app accepts `DYLD_INSERT_LIBRARIES` and loads unvalidated libraries.
- **Impact:** Once Screen Recording is granted, any process running as you can launch the app with injected code and record the screen under its grant, with no prompt.
- **Fix:** `codesign --force --options runtime --sign - "$APP_DIR"` (`--deep` is deprecated and unnecessary here). Runtime Metal shader compilation needs no extra entitlement, but test after the change.

### 4. MEDIUM — Global hotkeys hijack common shortcuts from launch

- **Where:** [GlobalDesktopController.swift:434](Sources/GlobalDesktopController.swift#L434); registered in `init` at [line 66](Sources/GlobalDesktopController.swift#L66)
- **Problem:** Carbon hotkeys are consumed system-wide for as long as the app runs, even when live mode is off.
  - **⌘⇧G** — Finder "Go to Folder" and "Find Previous" in most apps stop working; pressing it instead **starts screen capture** ([toggle:108](Sources/GlobalDesktopController.swift#L108)).
  - **⌘⇧K** — Xcode "Clean Build Folder", VS Code "Delete Line" stop working; pressing it **silently overwrites the saved open angle** ([calibrate:111](Sources/GlobalDesktopController.swift#L111)).
- **Fix:** Register ⌘⇧G/⌘⇧K only while live mode is active, or move to uncommon combos (e.g. ⌃⌥⌘). Keep ⌘⇧Esc registered before any capture starts (invariant enforced at [line 132](Sources/GlobalDesktopController.swift#L132)).

### 5. MEDIUM (by design) — What you see is not what you click

- **Where:** [GlobalDesktopController.swift:194-196](Sources/GlobalDesktopController.swift#L194)
- **Problem:** The overlay sits above the menu bar, notifications, and system alerts (including permission dialogs). While the effect is visible, those appear as a delayed, warped copy — including the real screen-recording privacy indicator — while clicks land on the undistorted layout.
- **Mitigation:** Don't interact with dialogs while the effect is showing. Document this prominently. Consider hiding the overlay when a system alert or permission prompt appears.

### 6. LOW — Historical `tccutil` reset helper

- **Where:** [ScreenCapturePermissionPreparation.swift:6, 32, 36-47](Sources/ScreenCapturePermissionPreparation.swift#L32)
- **Current state:** Automatic permission reset has been removed from application startup. The old helper remains only for regression coverage and is not called by HingeScape.
- **Risk if reused:** `tccutil reset ScreenCapture` with an empty client argument resets Screen Recording for every app on the Mac. Any future use must remain explicitly scoped.

### 7. LOW — Sensor fallback matches any vendor's device

- **Where:** [LidAngleSensor.swift:84-87](Sources/LidAngleSensor.swift#L84)
- **Problem:** The third matching strategy accepts any device with sensor usage page 0x20 / usage 0x8A and reads its feature report 1 as an angle. A third-party device could feed garbage angles and drive the overlay.
- **Fix:** Require Apple's vendor ID (`0x05AC`), i.e. drop the third strategy.

### 8. LOW — Stale frames after Space switch, auto-restart, or wake

- **Where:** [GlobalDesktopController.swift:95](Sources/GlobalDesktopController.swift#L95), [line 210](Sources/GlobalDesktopController.swift#L210), [lines 378-379](Sources/GlobalDesktopController.swift#L378)
- **Problem:** `receivedFrame` is not reset on automatic restarts or Space changes, so the next `update()` re-shows the previous texture until a new frame arrives.
- **Also:** The comment at [lines 92-93](Sources/GlobalDesktopController.swift#L92) claims locked sessions are covered. A plain screen lock (⌃⌘Q) posts none of the observed notifications. This is harmless in practice because the system lock shield is above all app windows, but the comment is inaccurate.

### 9. LOW — Energy use

- Hinge sensor polled at 30 Hz for the app's entire lifetime, including the setup screen ([LidAngleSensor.swift:55-59](Sources/LidAngleSensor.swift#L55)).
- While live mode is on, every captured frame is blitted to the GPU with a full mip-chain regeneration, even when the overlay is hidden ([GlassRenderer.swift:39-63](Sources/GlassRenderer.swift#L39)).

### 10. LOW — Latent crashes

- `NSScreen.screens.first!` crashed if no screen existed at launch (historical location: `HingeScapeApp.swift`).
- The Carbon hotkey handler holds `Unmanaged.passUnretained(self)` and is never removed ([GlobalDesktopController.swift:419](Sources/GlobalDesktopController.swift#L419)). Safe today because the controller lives for the app's lifetime; it would become a use-after-free if the controller were ever released.

### 11. INFO — Build, docs, tests, dead code

- `LSMinimumSystemVersion` is 14.0 ([Info.plist:29-30](Info.plist)), but `build.sh` pins no target, so the binary requires the build machine's OS (macOS 27 when built on 2026-09-11).
- README.md describes older v0.4 "Hinge Glass" behavior. The overlay level is documented as `statusBar + 1` ([GLOBAL-README.md:3](GLOBAL-README.md)) and as `floating` ([GLOBAL-README.md:17](GLOBAL-README.md)); the code uses `popUpMenu + 1`.
- The test uses `assert`, which compiles to nothing under `-O` ([Tests/PermissionPreparationTests.swift:10](Tests/PermissionPreparationTests.swift#L10)). It only covers the marker logic, not the `tccutil` call.
- `build.sh` writes the `.app` into the source folder.
- Dead code: `stop(preserveIntent:)` is never called with `true` ([line 308](Sources/GlobalDesktopController.swift#L308)); `lastDelivery` is never read; `LidAngleSensor.velocity` and `AppModel.toggleFullScreen()` are unused; the test page's `distance` has no control ([RootView.swift:198](Sources/RootView.swift#L198)).
- Swift 6 strict-concurrency type-check: 5 Sendable/isolation warnings, all benign (main-queue observer closure, intentional pixel-buffer retention). No errors.

---

## Verified clean

- **No networking.** The compiled binary imports no socket, `URLSession`, or CFNetwork symbols. The only URLs are file URLs and a comment.
- **No frame storage or exfiltration.** Frames go only into Metal textures. The app writes only two `UserDefaults` values (open angle, permission marker) and `NSLog` status strings with no screen content.
- **Single subprocess:** `/usr/bin/tccutil` with fixed arguments.
- **No hidden code.** No bidi, zero-width, or control characters in any source. Metal shader source is a static string.
- **Assets clean.** PNG has no trailing data; its only extra chunk is `caBX` (C2PA provenance from the image generator). ICNS is well-formed with no trailing data.
- **Capture safeguards.** The app excludes its own windows from capture, and aborts rather than capture itself if it can't ([line 166](Sources/GlobalDesktopController.swift#L166)). Wake recovery never triggers a new permission prompt ([line 290](Sources/GlobalDesktopController.swift#L290)). ⌘⇧Esc is a true hard stop (clears `resumeWanted`).

---

## Method

1. Full manual read of every source, doc, `build.sh`, and `Info.plist`.
2. Fresh build (Swift 6.4, macOS 27, arm64) in a scratch directory. No warnings; permission test passes.
3. Linked-library and imported-symbol scan of the binary (`otool -L`, `nm -u`).
4. Hidden-Unicode and control-character scan of all source.
5. Structural check of PNG and ICNS assets for appended payloads.
6. Swift 6 strict-concurrency type-check.
7. Provenance: the folder carries a Safari quarantine flag; no source URL was recorded.

### Post-fix file hashes (SHA-256, 2026-09-11)

```
b8d166364488462b6be028a2e9a331d8428be32f6205b02c7c39a1fc1d845fb7  Sources/AppModel.swift
c6228d647f27cd199a9721b94a0cf69854b554b133994121a17f4f1bd03ddc1b  Sources/CaptureSafety.swift
c01323e36cdbf588162aaad6f3bb893854c7a5b1a246d257fa047064ed453383  Sources/GlassRenderer.swift
75457a69ca51e75801629400093a328de43dd650d48cdbfbb8e69040cf0bdd9b  Sources/GlobalDesktopController.swift
6dea79da44343dd68a6a66320dc88fc0db9402d270f3d6e728ebe1070fb64d5d  Sources/HingeScapeApp.swift
3650c23ef561658ba75330f29dea9d859d208fd037526952edd10c57b20e2378  Sources/LidAngleSensor.swift
6d4cee3cba9843259511262fd7f10d684b61001f05ddcf94bedc8c7e9138f573  Sources/RootView.swift
ccaf15422c19519d8021d8e615e5e286cfd05fbb1a66fe7152e3c20417a5ba9b  Sources/ScreenCapturePermissionPreparation.swift
753c7a89533f49814f6db0b028431cd28179b3ddab462961cbc37a80dc13c7ed  Tests/PermissionPreparationTests.swift
34e3bcfc8ec3f1ffcd1dab94e92d4c68c4b889cd7d03a12a9d69f6dd4733529e  build.sh
e0b8b76245dfa066288684f4b404f95f19bc10948464ccc2442e3cc76074532d  test.sh
958c0c1cfc5e5c383fdee01c847630f7e08bc80f644bc55128ae5ff064c72772  Info.plist
```

### Reviewed (pre-fix) file hashes (SHA-256)

The findings above describe these versions.

```
6b3cd479fd7867f905dd30cbf222710b15e484e0803d3afdb42e8135c07530b7  Sources/AppModel.swift
a8f6cc64d852c6b327092728ecf8aabfb762b7c0e2df75dbf850113930af4f85  Sources/GlassRenderer.swift
05093b67968b3ebf102f2dd6d142be2ccc30c25dc35d76a0434ee95ee4ede2af  Sources/GlobalDesktopController.swift
7cac56ed33e7b6c7b11792a09d67594352ea481472df1cd194bc12ba56365168  Sources/HingeScapeApp.swift
ef3a0aae743ce004d158f79e0accc6e133ab168e09d145e56278b7255255fbc8  Sources/LidAngleSensor.swift
a26ba2f431a3044342b45d75dcf85d09c377bf46c71af9712e8c1b1120e48575  Sources/RootView.swift
bc4218566ecbb8745c8eb750fa00bd1c608529e5cf872cb5224df70e6adeb301  Sources/ScreenCapturePermissionPreparation.swift
4c09e7a17fb9c4764cced1d986eb7bb6f644fec39c489774f6ec285b63dffc49  Tests/PermissionPreparationTests.swift
68dce254cf51f6d0e785c86eb9696e78bf4c85e33772676d83bc7fdd139cc113  build.sh
958c0c1cfc5e5c383fdee01c847630f7e08bc80f644bc55128ae5ff064c72772  Info.plist
```
