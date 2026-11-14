-- Sub-row features per sequencer row: Note (N), Volume (V), Delay (D),
-- Piano roll (P) and Repeat (R).
--
-- Collapsing a sub-row only hides it; values stay in sequencer data and the
-- pattern. Each feature's toggle button indicates whether it holds values:
--   open                  -> BUTTON_COLOR_ACTIVE
--   closed, has values    -> BUTTON_COLOR_HAS_VALUES + "•"
--   closed, no values     -> BUTTON_COLOR_INACTIVE
--
-- Note (N) and Piano roll (P) are two views of the same per-step pitch data:
-- they share the "has values" state and clear action, and are mutually
-- exclusive (opening one closes the other).

local State         = require("state")
local Constants     = require("constants")
local MusicTheory   = require("music_theory")
local PatternWriter = require("pattern_writer")

local SubRows = {}

SubRows.FEATURES = {
  note   = { label = "N", toggle = "note_toggle_",       rows = "track_note_rows",       vis = "note_visible",   data = "note" },
  volume = { label = "V", toggle = "volume_toggle_",     rows = "track_volume_rows",     vis = "volume_visible", data = "volume" },
  delay  = { label = "D", toggle = "delay_toggle_",      rows = "track_delay_rows",      vis = "delay_visible",  data = "delay" },
  piano  = { label = "P", toggle = "piano_roll_toggle_", rows = "track_piano_roll_rows", vis = nil,              data = "note" },
  rep    = { label = "R", toggle = "repeat_toggle_",     rows = "track_repeat_rows",     vis = "repeat_visible", data = "rep" },
}
SubRows.ORDER = {"note", "volume", "delay", "piano", "rep"}

local function visibility(row_index)
  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = State.create_default_visibility()
  end
  return State.track_visibility[row_index]
end

-- Set a rotary value without triggering its own notifier logic
local function set_rotary_quietly(rotary_id, value)
  local vb = State.vb
  if not vb or not vb.views[rotary_id] then return end
  State.updating_rotary[rotary_id] = true
  vb.views[rotary_id].value = value
  State.updating_rotary[rotary_id] = nil
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------

function SubRows.is_visible(row_index, key)
  local f = SubRows.FEATURES[key]
  if key == "piano" then
    local row = State.sequencer_data[row_index]
    return row and row.piano_roll_visible or false
  end
  return visibility(row_index)[f.vis] or false
end

function SubRows.set_visible(row_index, key, visible)
  local f = SubRows.FEATURES[key]
  if key == "piano" then
    local row = State.sequencer_data[row_index]
    if row then row.piano_roll_visible = visible end
  else
    visibility(row_index)[f.vis] = visible
  end

  local view = State[f.rows][row_index]
  if view then view.visible = visible end

  if visible then
    if key == "delay" then
      -- Show the track's delay column when opening (never hidden on collapse,
      -- so existing delay values remain visible in the pattern editor)
      local song = renoise.song()
      local ti = State:get_track_index_for_row(row_index)
      if ti and ti <= #song.tracks and song.tracks[ti].type == renoise.Track.TRACK_TYPE_SEQUENCER then
        song.tracks[ti].delay_column_visible = true
      end
    elseif key == "piano" then
      require("piano_roll").update_display(row_index)
    end
  end
end

-- Toggle a sub-row open/closed. N and P are exclusive views of the same data.
function SubRows.toggle(row_index, key)
  local now_visible = not SubRows.is_visible(row_index, key)
  SubRows.set_visible(row_index, key, now_visible)

  if now_visible and (key == "note" or key == "piano") then
    local other = (key == "note") and "piano" or "note"
    if SubRows.is_visible(row_index, other) then
      SubRows.set_visible(row_index, other, false)
    end
  end

  SubRows.refresh_indicators(row_index)
  print("Sub-row " .. key .. " for row " .. row_index .. " visible: " .. tostring(now_visible))
end

---------------------------------------------------------------------------
-- Has-values checks
---------------------------------------------------------------------------

function SubRows.has_values(row_index, key)
  local row = State.sequencer_data[row_index]
  if not row then return false end
  local kind = SubRows.FEATURES[key].data

  if kind == "note" then
    if row.arp_enabled and row.arp_trigger_notes and next(row.arp_trigger_notes) then
      return true
    end
    local track_note = row.note_value or row.base_note_value or 48
    for s = 1, State.num_steps do
      local n = row.step_notes and row.step_notes[s]
      if n and n ~= track_note then return true end
    end
  elseif kind == "volume" then
    for s = 1, State.num_steps do
      local v = row.step_volumes and row.step_volumes[s]
      if v and v < 127 then return true end
    end
  elseif kind == "delay" then
    for s = 1, State.num_steps do
      local d = row.step_delays and row.step_delays[s]
      if d and d > 0 then return true end
    end
  elseif kind == "rep" then
    for s = 1, State.num_steps do
      if row.step_repeats and row.step_repeats[s] then return true end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Indicators
---------------------------------------------------------------------------

function SubRows.refresh_indicator(row_index, key)
  local vb = State.vb
  if not vb then return end
  local f = SubRows.FEATURES[key]
  local button = vb.views[f.toggle .. tostring(row_index)]
  if not button then return end

  local has = SubRows.has_values(row_index, key)
  if SubRows.is_visible(row_index, key) then
    button.color = Constants.BUTTON_COLOR_ACTIVE
  elseif has then
    button.color = Constants.BUTTON_COLOR_HAS_VALUES
  else
    button.color = Constants.BUTTON_COLOR_INACTIVE
  end
  button.text = has and (f.label .. "•") or f.label
end

function SubRows.refresh_indicators(row_index)
  for _, key in ipairs(SubRows.ORDER) do
    SubRows.refresh_indicator(row_index, key)
  end
end

function SubRows.refresh_all_indicators()
  for r = 1, #State.sequencer_data do
    if State.sequencer_data[r] then SubRows.refresh_indicators(r) end
  end
end

---------------------------------------------------------------------------
-- Clear
---------------------------------------------------------------------------

local function clear_notes(row_index)
  local row = State.sequencer_data[row_index]
  local vb = State.vb
  local track_note = row.note_value or row.base_note_value or 48
  local base = row.base_note_value or 48

  if row.arp_enabled then
    -- Pitch data for arp rows lives in the trigger notes: reset them to the track note
    if row.arp_trigger_notes then
      for s, _ in pairs(row.arp_trigger_notes) do
        row.arp_trigger_notes[s] = track_note
        if row.step_notes then row.step_notes[s] = track_note end
        local btn = vb and vb.views["step_button_" .. row_index .. "_" .. s]
        if btn then btn.text = MusicTheory.note_value_to_string(track_note) end
      end
    end
    require("arpeggiator").apply_to_row(row_index)
  else
    row.step_notes = {}
    for s = 1, State.num_steps do
      if row.step_states and row.step_states[s] == 1 then
        PatternWriter.update_step_note_in_pattern(row_index, s, track_note)
        local btn = vb and vb.views["step_button_" .. row_index .. "_" .. s]
        if btn then
          btn.text = MusicTheory.note_value_to_string(track_note)
          btn.width = Constants.cellSize
        end
      end
    end
  end

  local pct = MusicTheory.note_to_percentage(track_note, base, State.global_octave_range)
  for s = 1, State.num_steps do
    set_rotary_quietly("step_note_rotary_" .. row_index .. "_" .. s, pct)
  end
  require("piano_roll").update_display(row_index)
end

local function clear_volumes(row_index)
  local row = State.sequencer_data[row_index]
  row.step_volumes = {}
  for s = 1, State.num_steps do
    set_rotary_quietly("step_volume_rotary_" .. row_index .. "_" .. s, 100)
    if row.step_states and row.step_states[s] == 1 then
      PatternWriter.update_step_volume_in_pattern(row_index, s, 128)
    end
  end
end

local function clear_delays(row_index)
  local row = State.sequencer_data[row_index]
  row.step_delays = {}
  for s = 1, State.num_steps do
    set_rotary_quietly("step_delay_rotary_" .. row_index .. "_" .. s, 0)
    PatternWriter.update_step_delay_in_pattern(row_index, s, 0)
  end
end

local function clear_repeats(row_index)
  local row = State.sequencer_data[row_index]
  local vb = State.vb
  row.step_repeats = {}
  PatternWriter.write_repeats_for_row(row_index)
  for s = 1, State.num_steps do
    local btn = vb and vb.views["repeat_step_" .. row_index .. "_" .. s]
    if btn then
      btn.text = "--"
      btn.color = Constants.BUTTON_COLOR_INACTIVE
    end
  end
end

function SubRows.clear(row_index, key)
  if not State.sequencer_data[row_index] then return end
  local kind = SubRows.FEATURES[key].data
  if kind == "note" then
    clear_notes(row_index)
  elseif kind == "volume" then
    clear_volumes(row_index)
  elseif kind == "delay" then
    clear_delays(row_index)
  elseif kind == "rep" then
    clear_repeats(row_index)
  end
  SubRows.refresh_indicators(row_index)
  print("Cleared " .. key .. " values for row " .. row_index)
end

---------------------------------------------------------------------------
-- Layout helpers (keep sub-rows column-aligned with the main step row)
---------------------------------------------------------------------------

local function spacer(width)
  return State.vb:text{ width = width, height = Constants.cellSize, text = "" }
end

-- Wrap a left-area view in a fixed-width container (Constants.LEFT_AREA_WIDTH)
-- so step columns line up across the step row, sub-rows and header.
function SubRows.fixed_left(view)
  return State.vb:horizontal_aligner{
    mode  = "left",
    width = Constants.LEFT_AREA_WIDTH,
    view,
  }
end

-- Left area mirroring the step row's control slots.
-- `content` maps slot index -> view (must have that slot's width);
-- empty slots become spacers.
function SubRows.create_left_area(content)
  local area = State.vb:row{ spacing = Constants.control_spacing }
  for i, w in ipairs(Constants.LEFT_SLOTS) do
    area:add_child((content and content[i]) or spacer(w))
  end
  return SubRows.fixed_left(area)
end

-- Right area mirroring the step row's trailing buttons: M, S, clear(↩), x.
-- Clear sits under the track clear button; pass key = nil for spacers only.
function SubRows.add_right_area(parent, row_index, key)
  parent:add_child(spacer(Constants.cellSize))   -- under M
  parent:add_child(spacer(Constants.cellSize))   -- under S
  if key then
    parent:add_child(SubRows.create_clear_button(row_index, key))
  else
    parent:add_child(spacer(Constants.cellSize))
  end
end

-- Label text sized to a slot
function SubRows.slot_label(text, width)
  return State.vb:text{
    width = width or Constants.cellSizeLg,
    height = Constants.cellSize,
    text = text,
    align = "right",
  }
end

-- Clear button aligned with the track clear button on the right of each sub-row
function SubRows.create_clear_button(row_index, key)
  local vb = State.vb
  return vb:button{
    text = "↩",
    width = Constants.cellSize,
    height = Constants.cellSize,
    color = Constants.BUTTON_COLOR_OFF,
    tooltip = "Clear all " .. SubRows.FEATURES[key].label .. " values for this row",
    notifier = function()
      SubRows.clear(row_index, key)
    end
  }
end

return SubRows
