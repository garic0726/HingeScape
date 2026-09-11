# HingeScape Source Notes

This repository contains the complete HingeScape prototype: the live desktop effect, screenshot test mode, Metal renderer, icon assets, build scripts, safety tests, and development documentation. Compiled output is excluded from version control.

## Build

Install Apple Command Line Tools and run:

```sh
./build.sh
./test.sh
```

`build.sh` invokes the system Swift compiler, targets the minimum macOS version declared by `Info.plist`, embeds the Metal shader source in the executable, and produces `build/HingeScape.app` with an ad-hoc Hardened Runtime signature. No Xcode project or third-party dependency download is required.

## Source layout

- `Sources/HingeScapeApp.swift` — application entry point, setup window, app menu, and local shortcuts.
- `Sources/RootView.swift` — setup and Screenshot Test interfaces.
- `Sources/AppModel.swift` — imported screenshot, calibration, settings, and application state.
- `Sources/GlassRenderer.swift` — Metal perspective, frost, dimming, and transition renderer.
- `Sources/LidAngleSensor.swift` — Apple HID lid-angle reader.
- `Sources/GlobalDesktopController.swift` — ScreenCaptureKit stream, global overlay, hotkeys, safety gates, and recovery.
- `Sources/CaptureSafety.swift` — independently testable motion, pointer, timeout, and user-stop decisions.
- `Sources/ScreenCapturePermissionPreparation.swift` — legacy scoped-reset helper retained for tests; it is not invoked by the app.
- `Tests/PermissionPreparationTests.swift` and `test.sh` — optimized-build safety regression tests.
- `Assets/` — application icon and its design prompt.
- `Info.plist` and `build.sh` — bundle metadata and build entry point.
- `SECURITY-REVIEW.md` — historical review and current security notes.

## Behavioral constants

- Motion start threshold: 2°.
- Same-direction continuation threshold: 1°.
- Stillness timeout: 0.2 seconds.
- Natural fade duration: 0.15 seconds.
- Preview settle delay: 0.5 seconds.
- Preview duration: 8 seconds.
- Sensor polling: 30 Hz while requested.
- Capture: 30 fps while visible, 5 fps while hidden.

## Distribution note

The local build is ad-hoc signed. Screen Recording permission may need to be granted again after recompilation because the code identity changes. Production distribution requires a stable Apple signing identity and the usual notarization workflow.
