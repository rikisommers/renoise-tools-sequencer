-- Transport and step indicator management.

local State = require("state")
local Constants = require("constants")

local Playback = {}

-- Update step indicators to highlight the current playback position
function Playback.update_step_indicators()
  print("Running step indicators. Count: " .. #State.step_indicators)
  local song = renoise.song()
  local current_line = song.transport.playback_pos.line

  local current_sequencer_step = ((current_line - 1) % State.num_steps) + 1

  print("playing line t: ", current_line, " sequencer step: ", current_sequencer_step)

  for s, indicator in ipairs(State.step_indicators) do
    if s == current_sequencer_step then
      indicator.color = Constants.ACTIVE_COLOR
    elseif s % 4 == 1 then
      indicator.color = Constants.BLOCK_START_COLOR
    else
      indicator.color = Constants.INACTIVE_COLOR
    end
  end
end

-- Update play/stop button appearance based on transport state
function Playback.update_play_button()
  local vb = State.vb
  if vb.views["play_stop_button"] then
    local is_playing = renoise.song().transport.playing
    vb.views["play_stop_button"].text = is_playing and "■" or "▶"
  end
end

-- Set up line change notifier for step indicator updates
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

return Playback
