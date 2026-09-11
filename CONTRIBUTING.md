# Contributing to HingeScape

Thanks for helping improve HingeScape.

## Before submitting a change

1. Keep frame processing local and preserve the no-network design.
2. Do not broaden permissions or add background persistence without documenting the reason.
3. Preserve the immediate pointer and failure safety cutoffs.
4. Run `./test.sh` and `./build.sh` on macOS.
5. Update documentation when behavior, shortcuts, permissions, or compatibility changes.

## Areas that especially benefit from testing

- Different MacBook models and lid-angle sensor identifiers
- Multiple Spaces and full-screen applications
- Sleep, wake, lock, and display reconfiguration
- ScreenCaptureKit behavior across macOS releases
- Metal performance and transition smoothness

Please describe the Mac model and macOS version in bug reports involving live hinge behavior.
