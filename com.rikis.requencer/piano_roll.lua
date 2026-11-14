-- Piano roll sub-panel: visual grid note editor per sequencer row.
-- Scale-locked cells, aligned with the step grid.
-- Supports normal note entry and arp trigger-note placement.
--
-- The grid is a fixed-height window (Constants.PIANO_ROLL_VISIBLE_ROWS) onto
-- every scale note within the row's note range (same range as the N rotaries,
-- set by the global Oct Range). The window scrolls with the ▲/▼ buttons.
-- Cells are addressed by visual position; the note for each position lives in
-- row.piano_view_notes and is recomputed on every update_display().

local State       = require("state")
local Constants   = require("constants")
local MusicTheory = require("music_theory")
local PatternWriter = require("pattern_writer")

local PianoRoll = {}

local VISIBLE = Constants.PIANO_ROLL_VISIBLE_ROWS

-- Ascending list of all scale notes inside the row's note range
function PianoRoll.get_range_notes(row_index)
  local row = State.sequencer_data[row_index]
  if not row then return {} end

  local base = row.base_note_value or 48
  local min_note, max_note = MusicTheory.compute_note_range(base, State.global_octave_range)

  local allowed = nil
  local intervals = Constants.SCALE_INTERVALS[State.global_scale_mode]
  if State.global_scale_mode ~= "None" and intervals then
    allowed = {}
    local root_pc = (State.global_scale_key - 1) % 12
    for _, iv in ipairs(intervals) do allowed[(root_pc + iv) % 12] = true end
  end

  local notes = {}
  for n = min_note, max_note do
    if not allowed or allowed[n % 12] then table.insert(notes, n) end
  end
  return notes
end

-- Compute the visible window (high→low) and clamp the scroll position
local function compute_window(row_index)
  local row = State.sequencer_data[row_index]
  local notes = PianoRoll.get_range_notes(row_index)
  if #notes == 0 then return {}, notes, 1 end

  -- Default scroll: window starting at the bottom of the base note's octave
  if not row.piano_roll_low then
    row.piano_roll_low = math.floor((row.base_note_value or 48) / 12) * 12
  end

  local start = #notes
  for i, n in ipairs(notes) do
    if n >= row.piano_roll_low then start = i; break end
  end
  start = math.max(1, math.min(start, #notes - VISIBLE + 1))

  local window = {}
  for i = math.min(#notes, start + VISIBLE - 1), start, -1 do
    table.insert(window, notes[i])
  end
  return window, notes, start
end

-- Scroll the window by a number of scale steps (positive = up/higher)
function PianoRoll.scroll(row_index, delta)
  local row = State.sequencer_data[row_index]
  if not row then return end
  local _, notes, start = compute_window(row_index)
  if #notes == 0 then return end
  local new_start = math.max(1, math.min(start + delta, #notes - VISIBLE + 1))
  row.piano_roll_low = notes[new_start]
  PianoRoll.update_display(row_index)
end

-- Scroll by roughly an octave (number of scale notes per octave)
local function octave_steps()
  local intervals = Constants.SCALE_INTERVALS[State.global_scale_mode]
  if State.global_scale_mode ~= "None" and intervals then return #intervals end
  return 12
end

-- Determine cell color for a step/note pair
local function get_cell_color(row_index, step, note_value)
  local row = State.sequencer_data[row_index]
  if not row or not note_value then return Constants.BUTTON_COLOR_OFF end

  -- Arp trigger note (yellow) — checked first so it wins over other states
  if row.arp_enabled and row.arp_trigger_notes and row.arp_trigger_notes[step] == note_value then
    return Constants.PIANO_ROLL_TRIGGER_COLOR
  end

  -- Generated arp note (blue)
  if row.arp_enabled and row.arp_notes and row.arp_notes[step] == note_value
      and not (row.arp_trigger_notes and row.arp_trigger_notes[step]) then
    return Constants.PIANO_ROLL_ARP_COLOR
  end

  -- Normal active note (green)
  if not row.arp_enabled and row.step_states and row.step_states[step] == 1 then
    local step_note = (row.step_notes and row.step_notes[step]) or row.note_value or row.base_note_value or 48
    if step_note == note_value then
      return Constants.BUTTON_COLOR_PLAY
    end
  end

  return Constants.BUTTON_COLOR_OFF
end

-- The note sounding at a step (for off-screen indicators), or nil
local function step_sounding_note(row, step)
  if row.arp_enabled then
    return (row.arp_trigger_notes and row.arp_trigger_notes[step]) or (row.arp_notes and row.arp_notes[step])
  end
  if row.step_states and row.step_states[step] == 1 then
    return (row.step_notes and row.step_notes[step]) or row.note_value or row.base_note_value or 48
  end
  return nil
end

local function small_button(text, tooltip, fn)
  return State.vb:button{
    text = text,
    width = Constants.cellSize,
    height = Constants.cellSize,
    tooltip = tooltip,
    notifier = fn,
  }
end

-- Build the ViewBuilder grid for a piano roll row and store it in State
function PianoRoll.create_piano_roll_row(row_index, steps)
  local vb = State.vb
  if not vb then return nil end

  local actual_steps = math.min(steps, State.num_steps)
  local SubRows = require("sub_rows")
  local n_slots = #Constants.LEFT_SLOTS

  local grid_column = vb:column{ spacing = 1 }

  for i = 1, VISIBLE do
    local note_row = vb:row{ spacing = Constants.control_spacing }

    -- Left area mirrors the step row slots: "Piano" label in the instrument
    -- column, note name in the arp popup column, scroll buttons in the
    -- last two (P, R) columns on the top and bottom rows.
    local content = {
      [Constants.SLOT_ARP_POPUP] = vb:text{
        id     = "piano_label_" .. row_index .. "_" .. i,
        width  = Constants.LEFT_SLOTS[Constants.SLOT_ARP_POPUP],
        height = Constants.cellSize,
        text   = "",
        align  = "right"
      },
    }
    if i == 1 then
      content[Constants.SLOT_INSTRUMENT] = SubRows.slot_label("Piano ")
      content[n_slots - 1] = small_button("▲▲", "Scroll up an octave", function() PianoRoll.scroll(row_index, octave_steps()) end)
      content[n_slots]     = small_button("▲", "Scroll up", function() PianoRoll.scroll(row_index, 1) end)
    elseif i == VISIBLE then
      content[n_slots - 1] = small_button("▼▼", "Scroll down an octave", function() PianoRoll.scroll(row_index, -octave_steps()) end)
      content[n_slots]     = small_button("▼", "Scroll down", function() PianoRoll.scroll(row_index, -1) end)
    end
    note_row:add_child(SubRows.create_left_area(content))

    for s = 1, actual_steps do
      local captured_step = s
      local captured_pos  = i
      note_row:add_child(vb:button{
        id       = "piano_cell_" .. row_index .. "_" .. s .. "_" .. i,
        width    = Constants.cellSize,
        height   = Constants.cellSize,
        text     = "",
        color    = Constants.BUTTON_COLOR_OFF,
        notifier = function()
          local row = State.sequencer_data[row_index]
          local note = row and row.piano_view_notes and row.piano_view_notes[captured_pos]
          if note then
            PianoRoll.on_cell_click(row_index, captured_step, note)
          end
        end
      })
    end

    -- Right area: clear on the top row (under track clear), spacers elsewhere
    SubRows.add_right_area(note_row, row_index, (i == 1) and "piano" or nil)

    grid_column:add_child(note_row)
  end

  local wrapper = vb:column{ spacing = 0, grid_column }

  local row = State.sequencer_data[row_index]
  wrapper.visible = (row and row.piano_roll_visible) or false

  State.track_piano_roll_rows[row_index] = wrapper
  PianoRoll.update_display(row_index)
  return wrapper
end

-- Refresh labels and cell colors for a row (call after any note, arp,
-- scale or scroll change)
function PianoRoll.update_display(row_index)
  local vb = State.vb
  if not vb then return end

  local row = State.sequencer_data[row_index]
  if not row then return end

  local window = compute_window(row_index)
  row.piano_view_notes = window

  local top_note    = window[1]
  local bottom_note = window[#window]

  for i = 1, VISIBLE do
    local note_value = window[i]
    local label = vb.views["piano_label_" .. row_index .. "_" .. i]
    if label then
      label.text = note_value and MusicTheory.note_value_to_string(note_value) or ""
    end

    for s = 1, State.num_steps do
      local cell = vb.views["piano_cell_" .. row_index .. "_" .. s .. "_" .. i]
      if cell then
        local color = get_cell_color(row_index, s, note_value)
        -- Off-screen indicator: dim marker on the top/bottom edge
        if color == Constants.BUTTON_COLOR_OFF and top_note then
          local sounding = step_sounding_note(row, s)
          if sounding and ((i == 1 and sounding > top_note) or (i == #window and sounding < bottom_note)) then
            color = Constants.PIANO_ROLL_OFFSCREEN_COLOR
          end
        end
        cell.color = color
      end
    end
  end
end

-- Handle click on a piano roll cell (normal mode or arp mode)
function PianoRoll.on_cell_click(row_index, step, note_value)
  local row = State.sequencer_data[row_index]
  if not row then return end

  local vb = State.vb

  if row.arp_enabled then
    -- Arp mode: set / clear trigger note
    if not row.arp_trigger_notes then row.arp_trigger_notes = {} end
    if not row.step_states then row.step_states = {} end
    if not row.step_notes then row.step_notes = {} end

    if row.arp_trigger_notes[step] == note_value then
      -- Clear trigger note
      row.arp_trigger_notes[step] = nil
      row.step_states[step] = 0
      row.step_notes[step]  = nil
      PatternWriter.clear_step_from_pattern(row_index, step)

      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = ""
        vb.views[btn_id].color = State.empty_step_color(step)
        vb.views[btn_id].width = Constants.cellSize
      end
    else
      -- Set trigger note
      row.arp_trigger_notes[step] = note_value
      row.step_states[step] = 1
      row.step_notes[step]  = note_value

      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = MusicTheory.note_value_to_string(note_value)
        vb.views[btn_id].color = Constants.PIANO_ROLL_TRIGGER_COLOR
        vb.views[btn_id].width = Constants.cellSize
      end
    end

    -- Regenerate arp (lazy require avoids circular dep at module-load time)
    local Arp = require("arpeggiator")
    Arp.apply_to_row(row_index)
  else
    -- Normal mode: click-to-toggle note at this step
    if not row.step_states then row.step_states = {} end
    if not row.step_notes then row.step_notes = {} end

    local current_state = row.step_states[step] or 0
    local current_note  = row.step_notes[step] or row.note_value

    if current_state == 1 and current_note == note_value then
      -- Clear step
      row.step_states[step] = 0
      row.step_notes[step]  = nil
      PatternWriter.update_note_in_pattern(row_index, step, false)

      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = ""
        vb.views[btn_id].color = State.empty_step_color(step)
        vb.views[btn_id].width = Constants.cellSize
      end
    else
      -- Activate step with this note
      row.step_states[step] = 1
      row.step_notes[step]  = note_value
      PatternWriter.update_step_note_in_pattern(row_index, step, note_value)

      local btn_id = "step_button_" .. row_index .. "_" .. step
      if vb and vb.views[btn_id] then
        vb.views[btn_id].text  = MusicTheory.note_value_to_string(note_value)
        vb.views[btn_id].color = Constants.BUTTON_COLOR_PLAY
        vb.views[btn_id].width = Constants.cellSize
      end

      -- Sync linked note (N) rotary without re-triggering its notifier
      local base = row.base_note_value or 48
      local rot_id = "step_note_rotary_" .. row_index .. "_" .. step
      if vb and vb.views[rot_id] then
        State.updating_rotary[rot_id] = true
        vb.views[rot_id].value = MusicTheory.note_to_percentage(note_value, base, State.global_octave_range)
        State.updating_rotary[rot_id] = nil
      end
    end
  end

  PianoRoll.update_display(row_index)
  require("sub_rows").refresh_indicators(row_index)
end

return PianoRoll
