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
    elseif State.is_beat_start(s) then
      indicator.color = Constants.BLOCK_START_COLOR
    else
      indicator.color = Constants.INACTIVE_COLOR
    end
  end
end

-- Reset indicators to their idle (beat-shaded) colors
function Playback.reset_step_indicators()
  for s, indicator in ipairs(State.step_indicators) do
    indicator.color = State.is_beat_start(s) and Constants.BLOCK_START_COLOR or Constants.INACTIVE_COLOR
  end
end

-- Re-apply beat shading to indicators and empty step buttons (e.g. after LPB change)
function Playback.refresh_beat_shading()
  local vb = State.vb
  if not vb then return end
  if not renoise.song().transport.playing then
    Playback.reset_step_indicators()
  end
  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row and not row.arp_enabled then
      for s = 1, State.num_steps do
        local state = row.step_states and row.step_states[s] or 0
        local btn = vb.views["step_button_" .. r .. "_" .. s]
        if btn and state == 0 then
          btn.color = State.empty_step_color(s)
        end
      end
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

return Playback
