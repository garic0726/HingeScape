# Permissions

## Screen Recording

HingeScape requires macOS Screen Recording permission only for Live Desktop mode. Screenshot Test mode does not require it.

The app uses ScreenCaptureKit to capture the built-in display. It excludes its own windows, does not capture audio, does not include the cursor in the captured frame, and never writes frames to disk or sends them over a network.

HingeScape does **not** reset or grant its own permission automatically. macOS remains the sole authority for consent. Because local builds are ad-hoc signed, rebuilding can change the code identity and macOS may ask for permission again. A stable signing certificate is recommended for distributed builds.

## Lid-angle sensor

Live Desktop reads an undocumented Apple HID feature report to obtain the physical lid angle. No permission prompt is available for this interface. The reader matches Apple devices only and stops polling when neither Live Desktop nor Screenshot Test needs live angles.

## Global shortcuts and pointer state

HingeScape registers only three exact Carbon hotkeys: `⌘⇧Esc`, `⌘⇧G`, and `⌘⇧K`. It does not install a keyboard event tap or monitor arbitrary keystrokes.

While Live Desktop runs, it checks pointer position, held-button state, and the elapsed time since the latest click or scroll. These values are used only to dismiss the overlay safely; event contents are not recorded.

## Not requested

HingeScape does not request Accessibility, Input Monitoring, Full Disk Access, camera, microphone, location, contacts, or network access.
