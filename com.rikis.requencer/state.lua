-- Centralized mutable application state
-- All modules access state through this shared singleton table.
-- Mutations to fields are visible to all modules that require("state").

local State = {
  -- ViewBuilder instance (created fresh per dialog session)
  vb = nil,

  -- Sequencer settings
  num_steps = 16,
  num_rows = 1,
  current_step = 1,
  is_playing = false,
  is_syncing_pattern = false,

  -- Musical constraints
  global_octave_range = 3,
  global_scale_mode = "None",
  global_scale_key = 1,

  -- Core data
  sequencer_data = {},
  track_mapping = {},
  track_visibility = {},

  -- UI view references (set after ViewBuilder creation)
  step_grid_view = nil,
  step_indicators = {},
  step_indicators_row = nil,
  dialog = nil,
  track_note_rows = {},
  track_volume_rows = {},
  track_delay_rows = {},

  -- Observable notifier references
  instruments_notifier = nil,

  -- Callback set by main.lua to allow track_manager to reopen dialog
  show_sequencer_dialog = nil,
}

-- Safe accessor for a sequencer row
function State:get_row(index)
  return self.sequencer_data[index]
end

-- Get the actual Renoise track index for a sequencer row
function State:get_track_index_for_row(row_index)
  return self.track_mapping[row_index] or row_index
end

-- Remove a row from sequencer data and visibility tables
function State:remove_row(index)
  table.remove(self.sequencer_data, index)
  table.remove(self.track_visibility, index)
end

-- Reset UI-related state for a fresh dialog session
-- Preserves sequencer_data and track_visibility to keep user data
function State:reset_ui()
  self.vb = nil
  self.step_grid_view = nil
  self.step_indicators = {}
  self.step_indicators_row = nil
  self.track_note_rows = {}
  self.track_volume_rows = {}
  self.track_delay_rows = {}
end

-- Full reset of all data for a new session
function State:reset_data()
  self.sequencer_data = {}
  self.track_mapping = {}
  self.track_visibility = {}
  self.num_rows = 1
end

return State
