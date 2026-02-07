---------------------------------------------------------------
-- playback.lua
-- Transport control, step indicator updates, note triggering.
---------------------------------------------------------------

local Constants = require("constants")
local State     = require("state")

local Playback = {}

---------------------------------------------------------------
-- Step indicators
---------------------------------------------------------------

--- Update step indicator colours to highlight the current playback position.
function Playback.update_step_indicators()
  local indicators = State.step_indicators
  if not indicators or #indicators == 0 then return end

  local song = renoise.song()
  local current_line = song.transport.playback_pos.line
  local current_seq_step = ((current_line - 1) % State.num_steps) + 1

  for s, indicator in ipairs(indicators) do
    if s == current_seq_step then
      indicator.color = Constants.ACTIVE_COLOR
    elseif s % 4 == 1 then
      indicator.color = Constants.BLOCK_START_COLOR
    else
      indicator.color = Constants.INACTIVE_COLOR
    end
  end
end

---------------------------------------------------------------
-- Play / stop button
---------------------------------------------------------------

--- Update the play/stop button text to reflect the transport state.
function Playback.update_play_button()
  local vb = State.vb
  if vb and vb.views["play_stop_button"] then
    local is_playing = renoise.song().transport.playing
    vb.views["play_stop_button"].text = is_playing and "■" or "▶"
  end
end

---------------------------------------------------------------
-- Notifier setup
---------------------------------------------------------------

--- Register an app_new_document notifier that watches playback position.
function Playback.setup_line_change_notifier()
  renoise.tool().app_new_document_observable:add_notifier(function()
    local song = renoise.song()
    song.transport.playback_pos_observable:add_notifier(function()
      if song.transport.playing then
        Playback.update_step_indicators()
      end
    end)
  end)
end

---------------------------------------------------------------
-- Note triggering (legacy internal playback)
---------------------------------------------------------------

--- Trigger notes for active steps at the current step position.
function Playback.trigger_notes()
  for row, data in ipairs(State.sequencer_data) do
    if data.step_states and data.step_states[State.current_step] and data.step_states[State.current_step] > 0 then
      local instrument = renoise.song().instruments[data.instrument]
      local track = renoise.song().tracks[row]
      local note = renoise.song().transport.edit_step
      instrument:trigger_note(note, 100, track.name)
    end
  end
end

--- Handle playback loop (deferred callback).
function Playback.handle_playback()
  if State.is_playing then
    Playback.trigger_notes()
    State.current_step = State.current_step % State.num_steps + 1
    renoise.tool().app:defer(Playback.handle_playback)
  end
end

return Playback
