# HingeScape Live Desktop

Live Desktop captures the built-in MacBook display and renders the HingeScape glass effect while the lid is moving.

## Controls

- `⌘⇧Esc` immediately stops capture and opens Settings. It remains registered for the app's lifetime.
- `⌘⇧G` stops Live Desktop while it is running or waiting to recover.
- `⌘⇧K` saves the current physical lid angle as the fully open endpoint.
- The menu-bar icon provides preview, start/stop, calibration, Settings, and Quit commands.
- Screenshot Test continues to use `⌘H`, `⌘K`, and `⌘B`; those are local shortcuts, not global hotkeys.

The session shortcuts are registered only while Live Desktop is active, so they do not interfere with Finder, Xcode, or other applications when the effect is off.

## Motion behavior

The effect is limited to the built-in display. It starts after 2° of lid movement. Once active, each additional 1° in the same direction refreshes the movement gate so slow, steady motion does not flicker.

When movement stops:

1. The movement gate remains active for 0.2 seconds.
2. The transformed texture and overlay begin a 0.15-second fade together.
3. The real desktop remains underneath and receives pointer input throughout.

Pointer movement, held buttons, clicks, and scrolling remove the overlay immediately. After pointer use, the effect stays hidden until the lid moves by at least 2° again. Capture failures, sleep, lock, session changes, stale sensor data, and display changes also remove it immediately.

## Capture and rendering

ScreenCaptureKit captures only the built-in display at logical resolution. HingeScape excludes its own process, captures no audio, and omits the cursor. Capture runs at 30 fps while the overlay is visible and 5 fps while hidden. Hidden rendering retains only the newest pending frame.

The overlay is a nonactivating, click-through `NSPanel` above normal application UI. It can join Spaces and full-screen applications without taking keyboard focus. The Metal renderer uploads the current frame, generates mipmaps, and performs the perspective and frost calculation per pixel.

No frame is saved or transmitted. The capture stream remains active while Live Desktop is enabled so a recent frame is ready for the next movement; consequently, macOS continues to show its Screen Recording indicator.

## Preview

**Preview Live Effect (8 Seconds)** tests the renderer without moving the display. The preview waits until the pointer has been still for 0.5 seconds, runs for eight seconds, and ends immediately on pointer use. A request is discarded if the pointer does not settle within five seconds.

## Recovery

The overlay is removed immediately when capture becomes unsafe or stale. HingeScape can resume after wake, unlock, or a transient stream interruption when Screen Recording permission remains valid. A user-initiated stop from macOS's screen-sharing control is final and is never restarted automatically.

After a Space, display, wake, or session change, HingeScape waits for a fresh complete frame before displaying the overlay again. Three consecutive recovery failures stop Live Desktop and require manual re-enabling.

## Limitations

- Only the built-in MacBook display is hinge-driven.
- The captured image is slightly delayed, so the transformed visual position does not exactly match click targets. Pointer use therefore dismisses the overlay.
- Protected video, games, unusual full-screen surfaces, and future macOS releases may require compatibility testing.
- The lid-angle HID interface is undocumented and model support varies.
