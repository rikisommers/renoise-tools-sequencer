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
  updating_rotary = {},

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
  track_repeat_rows = {},

  -- Observable notifier references
  instruments_notifier = nil,
  idle_notifier = nil,
  playing_notifier = nil,
  lpb_notifier = nil,

  -- Tracked child views of step_grid_view (for manual clear without clear())
  grid_children = {},

  -- Piano roll wrapper columns per row
  track_piano_roll_rows = {},

  -- True while sequencer_data belongs to the currently loaded song
  session_valid = false,

  -- Callback set by main.lua to allow track_manager to reopen dialog
  show_sequencer_dialog = nil,
}

-- True if a step starts a beat (every LPB steps, following the song's LPB)
function State.is_beat_start(step)
  local ok, lpb = pcall(function() return renoise.song().transport.lpb end)
  if not ok or not lpb or lpb < 1 then lpb = 4 end
  return (step - 1) % lpb == 0
end

-- Color for an empty step button (lighter on beat starts)
function State.empty_step_color(step)
  local Constants = require("constants")
  return State.is_beat_start(step) and Constants.STEP_EMPTY_BEAT_COLOR or Constants.STEP_EMPTY_COLOR
end

-- Create a default sequencer row data table
function State.create_default_row()
  return {
    instrument     = 1,
    note_value     = 48,
    base_note_value= 48,
    step_states    = {},
    step_notes     = {},
    step_volumes   = {},
    step_delays    = {},
    track_volume   = 100,
    is_chord_track = false,
    chord_type     = "None",
    -- Piano roll
    piano_roll_visible = false,
    -- Arpeggiator
    arp_enabled       = false,
    arp_mode          = "up",
    arp_trigger_notes = {},
    arp_notes         = {},
    -- Note repeat (track effect R0y)
    repeat_speed   = 3,   -- ticks between retriggers (1..15)
    step_repeats   = {},  -- [step] = true
  }
end

-- Create a default track visibility table
function State.create_default_visibility()
  return {
    note_visible       = false,
    volume_visible     = false,
    delay_visible      = false,
    piano_roll_visible = false,
    repeat_visible     = false,
  }
end

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
  self.track_repeat_rows = {}
  self.track_piano_roll_rows = {}
  self.grid_children = {}
  self.updating_rotary = {}
end

-- Can the in-memory session be reused when (re)opening the dialog?
-- Requires the same song, and every row still mapped to an existing
-- "Sequencer_" track, with no extra sequencer tracks added meanwhile.
function State:can_reuse_session()
  if not self.session_valid or #self.sequencer_data == 0 then return false end

  local song = renoise.song()
  local seq_track_count = 0
  for i = 1, #song.tracks do
    local t = song.tracks[i]
    if t.type == renoise.Track.TRACK_TYPE_SEQUENCER and t.name:match("^Sequencer_") then
      seq_track_count = seq_track_count + 1
    end
  end
  if seq_track_count ~= #self.sequencer_data then return false end

  for r = 1, #self.sequencer_data do
    local ti = self.track_mapping[r]
    local t = ti and song.tracks[ti]
    if not t or t.type ~= renoise.Track.TRACK_TYPE_SEQUENCER or not t.name:match("^Sequencer_") then
      return false
    end
  end
  return true
end

-- Full reset of all data for a new session
function State:reset_data()
  self.sequencer_data = {}
  self.track_mapping = {}
  self.track_visibility = {}
  self.num_rows = 1
end

return State
