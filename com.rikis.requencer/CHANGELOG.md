# Changelog

## [1.03] - 2026-03-07

### Fixed
- **Step count change crash** — Changing the step count no longer crashes the tool. The dialog now cleanly rebuilds with a fresh ViewBuilder, preserving all step data.
- **Notifier accumulation** — Opening/closing the dialog multiple times no longer stacks duplicate idle and playback notifiers, preventing performance degradation.
- **Step delays lost on step count change** — Per-step delay values are now preserved when changing the number of steps.
- **Step count resets to 16 on track delete** — The steps dropdown now correctly reflects the current step count when the dialog reopens after deleting a track.
- **Removed broken `playback_pos_observable` usage** — Removed `setup_line_change_notifier()` which referenced a non-existent Renoise API property. Playback position tracking already handled by the idle notifier.
