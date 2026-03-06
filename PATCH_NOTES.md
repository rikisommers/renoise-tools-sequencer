# Requencer Patch Notes — v1.03

## Bug Fixes

- Fixed crash when changing step count (was calling non-existent `clear()` on grid view)
- Fixed notifiers stacking on every dialog open, causing slowdowns over time
- Fixed step delays being lost when changing the number of steps
- Fixed step count dropdown resetting to 16 after deleting a track
- Removed broken `playback_pos_observable` reference that caused errors on tool load

## Files Changed

### `main.lua`
- Added forward declaration for `show_sequencer_dialog` to allow cross-reference
- `update_step_count()`: Replaced broken `clear()` call with `write_sequencer_to_pattern()` + dialog reopen; added `step_delays` preservation
- `add_sequencer_row()`: Track child views in `State.step_grid_children`
- `show_sequencer_dialog()`: Initialize `step_grid_children`; track children when building rows; store notifier references and remove before re-adding; use `State.num_steps` for dropdown init instead of `DEFAULT_PATTERN_LENGTH`; removed `setup_line_change_notifier()` call

### `state.lua`
- Added `State.step_grid_children = {}` field
- Added `State.idle_notifier` and `State.playing_notifier` fields
- Reset all new fields in `State:reset()`

### `playback.lua`
- Removed `setup_line_change_notifier()` function (used non-existent `playback_pos_observable` API)
