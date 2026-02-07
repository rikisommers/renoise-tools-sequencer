---------------------------------------------------------------
-- state.lua
-- Single source of truth for all mutable application state.
-- Provides accessor/mutator helpers and a reset method.
---------------------------------------------------------------

local State = {}

---------------------------------------------------------------
-- Default values (used by reset and initial load)
---------------------------------------------------------------

local DEFAULTS = {
  num_steps          = 16,
  num_rows           = 1,
  current_step       = 1,
  is_playing         = false,
  is_syncing_pattern = false,

  -- Global musical constraints
  global_octave_range = 3,
  global_scale_mode   = "None",
  global_scale_key    = 1,  -- 1=C .. 12=B
}

---------------------------------------------------------------
-- Instance data (mutable at runtime)
---------------------------------------------------------------

-- Sequencer row data: array of row tables
State.sequencer_data = {}

-- Track mapping: row_index -> Renoise track index
State.track_mapping = {}

-- Track visibility: row_index -> {note_visible, volume_visible, delay_visible}
State.track_visibility = {}

-- UI view references (populated by ui_builder after ViewBuilder creation)
State.step_indicators  = {}
State.step_grid_view   = nil
State.step_indicators_row = nil
State.track_note_rows   = {}
State.track_volume_rows = {}
State.track_delay_rows  = {}

-- Dialog reference
State.dialog = nil

-- ViewBuilder reference (set fresh each time the dialog opens)
State.vb = nil

-- Observable notifier reference for instrument list changes
State.instruments_notifier = nil

-- Callback: show_sequencer_dialog (set by main.lua so track_manager can reopen)
State.show_sequencer_dialog = nil

-- Copy scalar defaults onto State
for k, v in pairs(DEFAULTS) do
  State[k] = v
end

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------

--- Create a default row data table.
-- @return table  Fresh row with sensible defaults.
function State.create_default_row()
  return {
    instrument      = 1,
    note_value      = 48,
    base_note_value = 48,
    step_states     = {},
    step_notes      = {},
    step_volumes    = {},
    step_delays     = {},
    track_volume    = 100,
    is_chord_track  = false,
    chord_type      = "None",
  }
end

--- Safe accessor for a sequencer row.
-- @param index  number  Row index (1-based)
-- @return table|nil
function State:get_row(index)
  return self.sequencer_data[index]
end

--- Add a row with defaults and initialize its step states.
-- @param data  table|nil  Optional partial data to merge over defaults.
-- @return number  The new row index.
function State:add_row(data)
  local row = self.create_default_row()
  if data then
    for k, v in pairs(data) do
      row[k] = v
    end
  end
  -- Ensure step states are initialised for current step count
  if not row.step_states or #row.step_states == 0 then
    row.step_states = {}
    for s = 1, self.num_steps do
      row.step_states[s] = 0
    end
  end
  table.insert(self.sequencer_data, row)
  local idx = #self.sequencer_data
  self.track_visibility[idx] = {note_visible = false, volume_visible = false, delay_visible = false}
  return idx
end

--- Remove a row and shift everything down.
-- @param index  number
function State:remove_row(index)
  table.remove(self.sequencer_data, index)
  table.remove(self.track_visibility, index)
  self.num_rows = #self.sequencer_data
end

--- Reset all runtime state for a fresh dialog session.
-- Preserves nothing -- call before building a new dialog.
function State:reset()
  self.sequencer_data    = {}
  self.track_mapping     = {}
  self.track_visibility  = {}
  self.step_indicators   = {}
  self.step_grid_view    = nil
  self.step_indicators_row = nil
  self.track_note_rows   = {}
  self.track_volume_rows = {}
  self.track_delay_rows  = {}
  self.dialog            = nil
  self.vb               = nil
  self.instruments_notifier = nil

  for k, v in pairs(DEFAULTS) do
    self[k] = v
  end
end

return State
