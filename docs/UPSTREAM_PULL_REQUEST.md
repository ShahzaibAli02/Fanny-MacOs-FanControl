# Proposed upstream pull request

## Title

Improve Apple-silicon fan monitoring, automatic-control stability, and compact UI

## Summary

This contribution was developed and interactively tested on an Apple M4 Pro
MacBook Pro. It improves the reliability and usability of Fan Control without
claiming to reproduce Apple's private thermal policy.

The principal changes are:

- validate temperature samples and use the highest plausible CPU reading from
  the available CPU-oriented SMC keys;
- retain one-second SMC polling regardless of window visibility, with a guard
  against overlapping helper requests;
- add adjustable asymmetric command-rate limits, cooling hysteresis, target
  deadband, cooling confirmation, and an emergency high-demand bypass;
- add an overlaid, selectable temperature-and-fan-target history chart with
  a rolling time range, hover inspection, and grid;
- replace continuous SwiftUI fan drawing with Core Animation to reduce visible
  UI CPU usage while keeping the fan indicator proportional and monotonic;
- improve normal window behaviour, Dock presence, menu-bar reopening,
  responsive sizing, and compact notebook layouts; and
- add native macOS localizations for English, French, German, Spanish, and
  Simplified Chinese, including translated runtime-generated labels; and
- add an opt-in, bounded CPU/Metal thermal-load utility for local comparisons.

## Safety and scope

- English and French are the only localization variants manually verified in
  the running app. German, Spanish, and Simplified Chinese are included but
  require in-app and native-speaker review before release.

- The app always retains the existing **Reset All to Auto** path.
- Temperature increases and high requests remain fast; cooling-side controls
  are used to reduce acoustic hunting rather than to delay a thermal rise.
- The CPU value is a conservative aggregate of plausible keys. It is labelled
  **CPU**, not as a confirmed physical die sensor.
- The code does not infer that a particular physical fan cools only the CPU or
  only the GPU.
- The privileged helper's command surface is not broadened.

## Manual validation

- ARM64 app and helper compile with macOS 13.0 as the deployment target.
- The local app bundle passes `codesign --verify --deep --strict` after an
  ad-hoc build.
- Interactive M4 Pro testing covered manual fan control, automatic rules,
  window resizing, background operation, history display, and CPU/Metal load
  transitions.
- The optional DMG can fail in a sandboxed local environment after the usable,
  signed `.app` has already been produced; this is an `hdiutil` environment
  limitation rather than an app build failure.

## Review guidance

`docs/FORK_CHANGELOG.md` contains the detailed behavioural record, persisted
setting names, validation bounds, known limitations, and suggested follow-up
work. The changes are substantial and could be split for review into sensor
reliability, automatic-control policy, UI/performance, and test-tool commits.

Thank you for considering the contribution. I would be happy to split or
adjust it to match the project's preferred design and review boundaries.
