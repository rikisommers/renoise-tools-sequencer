-- Piano roll sub-panel: visual grid note editor per sequencer row.
-- Scale-locked cells, aligned with the step grid.

local State         = require("state")
local C             = require("constants")
local MusicTheory   = require("music_theory")
local PatternWriter = require("pattern_writer")

local PianoRoll = {}

function PianoRoll.get_scale_notes(row_index)
  local row = State.sequencer_data[row_index]
  if not row then return {} end
  local base_note = row.base_note_value or 48
  local notes = MusicTheory.get_scale_notes_in_octave(
    State.global_scale_mode, State.global_scale_key, base_note
  )
  local reversed = {}
  for i = #notes, 1, -1 do table.insert(reversed, notes[i]) end
  return reversed
end

local function get_cell_color(row_index, step, note_value)
  local row = State.sequencer_data[row_index]
  if not row then return C.BUTTON_COLOR_OFF end

  if row.arp_enabled and row.arp_trigger_notes and row.arp_trigger_notes[step] == note_value then
    return C.PIANO_ROLL_TRIGGER_COLOR
  end
  if row.arp_enabled and row.arp_notes and row.arp_notes[step] == note_value
      and not (row.arp_trigger_notes and row.arp_trigger_notes[step]) then
    return C.PIANO_ROLL_ARP_COLOR
  end
  if not row.arp_enabled and row.step_states and row.step_states[step] == 1 then
    local step_note = (row.step_notes and row.step_notes[step]) or row.note_value or row.base_note_value or 48
    if step_note == note_value then return C.BUTTON_COLOR_PLAY end
  end
  return C.BUTTON_COLOR_OFF
end

local function left_controls_width()
  return C.CELL_SIZE_LG * 3 + C.CELL_SIZE * 9 + 6
end

function PianoRoll.create_piano_roll_row(row_index, steps)
  local vb = State.vb
  if not vb then return nil end
  local actual_steps = math.min(steps, State.num_steps)
  local scale_notes  = PianoRoll.get_scale_notes(row_index)
  if #scale_notes == 0 then
    scale_notes = {59, 57, 55, 53, 52, 50, 48}
  end
  local spacer_w = left_controls_width() - C.PIANO_ROLL_LABEL_WIDTH
  local grid_column = vb:column{ spacing = 1 }
  for _, note_value in ipairs(scale_notes) do
    local note_row = vb:row{ spacing = 1 }
    note_row:add_child(vb:text{ width = spacer_w, height = C.CELL_SIZE, text = "" })
    note_row:add_child(vb:text{
      width  = C.PIANO_ROLL_LABEL_WIDTH,
      height = C.CELL_SIZE,
      text   = MusicTheory.note_value_to_string(note_value),
      align  = "center"
    })
    for s = 1, actual_steps do
      local cell_id       = "piano_cell_" .. row_index .. "_" .. s .. "_" .. note_value
      local captured_step = s
      local captured_note = note_value
      note_row:add_child(vb:button{
        id       = cell_id,
        width    = C.CELL_SIZE,
        height   = C.CELL_SIZE,
        text     = "",
        color    = get_cell_color(row_index, s, note_value),
        notifier = function()
          PianoRoll.on_cell_click(row_index, captured_step, captured_note)
        end
      })
    end
    grid_column:add_child(note_row)
  end
  local wrapper = vb:column{ spacing = 0, grid_column }
  local row = State.sequencer_data[row_index]
  wrapper.visible = (row and row.piano_roll_visible) or false
  State.track_piano_roll_rows[row_index] = wrapper
  return wrapper
end

function PianoRoll.update_display(row_index)
  local vb = State.vb
  if not vb then return end
  local row = State.sequencer_data[row_index]
  if not row then return end
  local scale_notes = PianoRoll.get_scale_notes(row_index)
  for _, note_value in ipairs(scale_notes) do
    for s = 1, State.num_steps do
      local cell_id = "piano_cell_" .. row_index .. "_" .. s .. "_" .. note_value
      if vb.views[cell_id] then
        vb.views[cell_id].color = get_cell_color(row_index, s, note_value)
      end
    end
  end
end

function PianoRoll.on_cell_click(row_index, step, note_value)
  local row = State.sequencer_data[row_index]
  if not row then return end
  local vb = State.vb

  if row.arp_enabled then
    if not row.arp_trigger_notes then row.arp_trigger_notes = {} end
    if not row.step_states then row.step_states = {} end
    if not row.step_notes then row.step_notes = {} end

    if row.arp_trigger_notes[step] == note_value then
      row.arp_trigger_notes[step] = nil
      row.step_states[step] = 0
      row.step_notes[step]  = nil
      PatternWriter.clear_step_from_pattern(row_index, step)
      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = "   "
        vb.views[btn_id].color = C.BUTTON_COLOR_OFF
      end
    else
      row.arp_trigger_notes[step] = note_value
      row.step_states[step] = 1
      row.step_notes[step]  = note_value
      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = MusicTheory.note_value_to_string(note_value)
        vb.views[btn_id].color = C.PIANO_ROLL_TRIGGER_COLOR
      end
    end
    local Arp = require("arpeggiator")
    Arp.apply_to_row(row_index)
  else
    if not row.step_states then row.step_states = {} end
    if not row.step_notes then row.step_notes = {} end
    local current_state = row.step_states[step] or 0
    local current_note  = row.step_notes[step]

    if current_state == 1 and current_note == note_value then
      row.step_states[step] = 0
      row.step_notes[step]  = nil
      PatternWriter.update_note_in_pattern(row_index, step, false)
      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = "   "
        vb.views[btn_id].color = C.BUTTON_COLOR_OFF
      end
    else
      row.step_states[step] = 1
      row.step_notes[step]  = note_value
      PatternWriter.update_step_note_in_pattern(row_index, step, note_value)
      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = MusicTheory.note_value_to_string(note_value)
        vb.views[btn_id].color = C.BUTTON_COLOR_PLAY
      end
      local base  = row.base_note_value or 48
      local rot_id = "step_note_rotary_" .. row_index .. "_" .. step
      if vb and vb.views[rot_id] then
        vb.views[rot_id].value = MusicTheory.note_to_percentage(note_value, base, State.global_octave_range)
      end
    end
  end
  PianoRoll.update_display(row_index)
end

return PianoRoll
