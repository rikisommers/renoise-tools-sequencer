-- Step play column: 0 = cleared, 1 = play, 2 = stop. UI button cycles all three states.

local State = require("state")
local Constants = require("constants")
local MusicTheory = require("music_theory")
local PatternWriter = require("pattern_writer")

local StepState = {}

function StepState.get_step_note(row_index, step)
  local row = State.sequencer_data[row_index]
  if not row then return 48 end

  if row.step_notes and row.step_notes[step] then
    return row.step_notes[step]
  end
  return row.note_value or row.base_note_value or 48
end

-- Returns text and color for a step button given its state (0/1/2).
function StepState.get_button_appearance(state, step)
  if state == 1 then
    return "▶", {147, 245, 66}   -- play: green
  elseif state == 2 then
    return "■", {245, 66, 93}    -- stop: red
  end
  return "", State.empty_step_color(step or 2)  -- clear: dark (lighter on beat starts)
end

local function update_play_button_ui(row_index, step, state, note_value)
  local vb = State.vb
  if not vb then return end

  local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
  local view = vb.views[button_id]
  if not view then return end

  if state == 1 then
    view.text = MusicTheory.note_value_to_string(note_value)
    view.color = {147, 245, 66}
  elseif state == 2 then
    view.text = "■"
    view.color = {245, 66, 93}
  else
    view.text = ""
    view.color = State.empty_step_color(step)
  end
  view.width = Constants.cellSize
end

local function ensure_row_track(row_index)
  if not State.track_mapping[row_index] then
    print("ERROR: Row " .. row_index .. " has no pattern track mapping")
    return false
  end
  return true
end

-- UI click: cycle through 0 (clear) -> 1 (play) -> 2 (stop) -> 0 ...
-- In arp mode: toggle trigger note on/off (no stop state)
function StepState.toggle_step_playing(row_index, step)
  local row = State.sequencer_data[row_index]
  if not row then return end

  if not row.step_states then row.step_states = {} end

  -- Arp mode: clicking step button sets/clears trigger note
  if row.arp_enabled then
    if not row.arp_trigger_notes then row.arp_trigger_notes = {} end
    if not row.step_notes then row.step_notes = {} end

    if row.arp_trigger_notes[step] then
      -- Clear trigger note
      row.arp_trigger_notes[step] = nil
      row.step_states[step] = 0
      row.step_notes[step]  = nil
      if ensure_row_track(row_index) then
        PatternWriter.clear_step_from_pattern(row_index, step)
      end
      update_play_button_ui(row_index, step, 0)
    else
      -- Set trigger note (use existing step note or track base note)
      local pitch = (row.step_notes[step]) or row.note_value or row.base_note_value or 48
      row.arp_trigger_notes[step] = pitch
      row.step_states[step] = 1
      row.step_notes[step]  = pitch

      local vb = State.vb
      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = MusicTheory.note_value_to_string(pitch)
        vb.views[btn_id].color = Constants.PIANO_ROLL_TRIGGER_COLOR
        vb.views[btn_id].width = Constants.cellSize
      end
    end

    -- Regenerate arp
    local Arp = require("arpeggiator")
    Arp.apply_to_row(row_index)
    return
  end

  -- Normal mode: cycle 0→1→2→0
  local current_state = row.step_states[step] or 0
  local new_state = (current_state + 1) % 3

  row.step_states[step] = new_state

  print("Step state changed:")
  print("  Row: " .. row_index .. " Step: " .. step)
  print("  " .. current_state .. " -> " .. new_state)

  if new_state == 0 then
    if ensure_row_track(row_index) then
      PatternWriter.update_note_in_pattern(row_index, step, false)
    end
    update_play_button_ui(row_index, step, 0)

  elseif new_state == 1 then
    local note_value = StepState.get_step_note(row_index, step)
    if ensure_row_track(row_index) then
      PatternWriter.update_step_note_in_pattern(row_index, step, note_value)
    end
    update_play_button_ui(row_index, step, 1, note_value)

  elseif new_state == 2 then
    if ensure_row_track(row_index) then
      PatternWriter.write_note_off_to_step(row_index, step)
    end
    update_play_button_ui(row_index, step, 2)
  end

  require("piano_roll").update_display(row_index)
  require("sub_rows").refresh_indicators(row_index)
end

return StepState
