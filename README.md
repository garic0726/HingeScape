# HingeScape

**Your desktop, anchored beyond the glass.**

HingeScape is an experimental macOS app that turns a MacBook display into a moving pane of frosted glass. As the lid moves, the desktop appears fixed in space behind it: perspective shifts, depth blur grows with distance from the hinge, and the image darkens subtly. When motion stops, the effect waits 0.2 seconds and then fades away smoothly.

The app provides two modes:

- **Live Desktop** captures the built-in display with ScreenCaptureKit and applies the effect in real time.
- **Screenshot Test** renders an imported desktop screenshot and provides manual controls for calibration and tuning.

## Requirements

- macOS 14 or later
- A Mac with Metal support
- A compatible MacBook lid-angle sensor for Live Desktop mode
- Screen Recording permission for Live Desktop mode
- Apple Command Line Tools for building

The lid-angle interface is undocumented and may not work on every MacBook model. Screenshot Test mode remains available without it.

## Build

```sh
./build.sh
open "build/HingeScape.app"
```

Run the test suite with:

```sh
./test.sh
```

The build uses the system Swift compiler, requires no downloaded dependencies, targets the minimum macOS version in `Info.plist`, and produces a local ad-hoc Hardened Runtime signature.

## Live Desktop

1. Open HingeScape and select **Enable Live Desktop Effect**.
2. Allow Screen Recording if macOS requests it.
3. Open the display to your normal viewing position and press `⌘⇧K` to save the fully open angle.
4. Move the display toward you to reveal the effect.

The effect starts after at least 2° of lid travel. Continued movement in the same direction keeps it active at 1° increments. After motion stops, a 0.2-second gate closes and the transformed texture and overlay fade out together over 0.15 seconds.

Global shortcuts:

- `⌘⇧Esc` — emergency stop and open Settings
- `⌘⇧G` — stop Live Desktop while it is running
- `⌘⇧K` — save the current lid angle as fully open

See [Live Desktop details](GLOBAL-README.md), [permissions](PERMISSIONS.md), and the [security review](SECURITY-REVIEW.md).

## Screenshot Test

Import a full desktop screenshot, enter Effect Settings, and move the lid or disable **Live Hinge** to use the simulated-angle slider. The image fills the display; small edges may be cropped when its aspect ratio differs.

Test-mode shortcuts:

- `⌘H` — hide or show controls
- `Esc` — show controls
- `⌘K` — save the current angle as fully open
- `⌘B` — toggle the original-image comparison
- `⌘Q` — quit

## How it works

The Metal renderer treats the desktop as a fixed plane behind the display. For each output pixel, it traces the viewing ray through the rotated screen to that plane, then applies gap-dependent blur, dimming, and a subtle glass sheen. HingeScape adapts the reference model from a vertical phone hinge to a MacBook's horizontal bottom hinge.

All frame processing stays on the Mac. HingeScape does not record frames to disk, capture audio, or use the network.

## Origins and attribution

HingeScape is an independent macOS implementation inspired by earlier public experiments:

- [DuoLikeAnimation](https://github.com/elijah-semyonov/DuoLikeAnimation) by **Elijah Semyonov** — the original SwiftUI/Metal iPhone prototype. It is published under the MIT License, copyright © 2026 Elijah Semyonov.
- [Duo-animation / DuoFold](https://github.com/Atomicx7/Duo-animation) by **Atomicx7** — the public Android projection-model reference. Its repository does not currently declare a license; HingeScape uses an independent Metal implementation rather than copying its source.
- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) by **Sam Gold** — reference for accessing Apple's lid-angle HID sensor, published under Apache License 2.0.

The physical visual reference used during early development was [this Weibo demonstration](https://weibo.com/2/detail/5341559961948752). The page and cover were accessible, but the web player was not successfully reviewed frame by frame.

See [Third-Party Notices](THIRD-PARTY-NOTICES.md) for the full attribution statement.

## License

No license has yet been selected for HingeScape itself. Until one is added, all rights in this repository's original code are reserved. The upstream projects retain their respective copyrights and licenses.
