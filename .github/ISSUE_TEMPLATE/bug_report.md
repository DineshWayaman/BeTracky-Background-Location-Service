---
name: Bug report
about: Something is not working as expected
title: '[Bug] '
labels: bug
assignees: DineshWayaman
---

## Describe the bug

A clear description of what the bug is.

## Steps to reproduce

1. Call `startService(...)` with these parameters: ...
2. ...
3. See error / unexpected behaviour

## Expected behaviour

What you expected to happen.

## Actual behaviour

What actually happened. Include any error messages or stack traces.

## Code sample

```dart
// Minimal reproduction
await BeTrackyBackgroundLocation.startService(
  distanceFilter: 0,
  accuracy: LocationAccuracy.high,
  startOnBoot: false,
  foregroundService: true,
);
```

## Environment

| Field | Value |
|-------|-------|
| Package version | e.g. 2.1.1 |
| Flutter version (`flutter --version`) | |
| Dart version | |
| Platform | Android / iOS |
| Android API level / iOS version | |
| Device / Emulator | |

## Additional context

Any other context, logs, or screenshots.
