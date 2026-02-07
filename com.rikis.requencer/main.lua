---------------------------------------------------------------
-- main.lua
-- Entry point for the Requencer tool.
-- Orchestrates all modules; creates the dialog and registers
-- the menu entry.
---------------------------------------------------------------

local Constants     = require("constants")
local MusicTheory   = require("music_theory")
local State         = require("state")
local PatternWriter = require("pattern_writer")
local TrackManager  = require("track_manager")
local UIBuilder     = require("ui_builder")
local Playback      = require("playback")
local MidiMappings  = require("midi_mappings")

---------------------------------------------------------------
-- Helpers local to the dialog
---------------------------------------------------------------

local function find_steps_index(pattern_length)
  for i, option in ipairs(Constants.NUM_STEPS_OPTIONS) do
    if tonumber(option) == pattern_length then
      return i
    end
  end
  return 1
end

---------------------------------------------------------------
-- Update step count (rebuilds UI rows)
---------------------------------------------------------------

local function update_step_count(new_steps)
  if not State.step_grid_view then return end

  PatternWriter.clear_notes_outside_range(new_steps, State.num_steps)
  State.num_steps = new_steps

  -- Show/hide step indicators
  for s = 1, #State.step_indicators do
    if State.step_indicators[s] then
      State.step_indicators[s].visible = (s <= new_steps)
    end
  end

  if new_steps > #State.step_indicators then
    print("Step count increased beyond current capacity. Please restart the tool.")
    return
  end

  -- Adjust per-row step data
  for r = 1, State.num_rows do
    local row = State.sequencer_data[r]
    if row then
      local old_states  = row.step_states  or {}
      local old_notes   = row.step_notes   or {}
      local old_volumes = row.step_volumes or {}

      row.step_states  = {}
      row.step_notes   = {}
      row.step_volumes = {}

      for s = 1, new_steps do
        row.step_states[s] = old_states[s] or 0
        if old_notes[s]   then row.step_notes[s]   = old_notes[s]   end
        if old_volumes[s]  then row.step_volumes[s]  = old_volumes[s]  end
      end
    end
  end

  -- Rebuild grid UI
  State.step_grid_view:clear()
  for r = 1, #State.sequencer_data do
    if State.sequencer_data[r] then
      State.step_grid_view:add_child(UIBuilder.create_styled_row_group(r, new_steps))
    end
  end

  print("Updated sequencer to " .. new_steps .. " steps")
  TrackManager.apply_global_note_constraints()
end

---------------------------------------------------------------
-- Add-row handler
---------------------------------------------------------------

local function add_sequencer_row()
  local vb   = State.vb
  local song = renoise.song()

  local insert_pos = 1
  for i = 1, #song.tracks do
    if song.tracks[i].type == renoise.Track.TRACK_TYPE_SEQUENCER then
      insert_pos = i + 1
    end
  end

  song:insert_track_at(insert_pos)

  local instrument_name = "Unknown"
  if #song.instruments > 0 then
    instrument_name = song.instruments[1].name
  end

  local track = song.tracks[insert_pos]
  track.name         = "Sequencer_" .. instrument_name
  track.color        = Constants.TRACK_COLOR
  track.output_delay = 0

  local new_idx = State:add_row()
  State.track_mapping[new_idx] = insert_pos
  State.num_rows = State.num_rows + 1

  print("Row " .. new_idx .. " -> Track " .. insert_pos .. " (" .. instrument_name .. ")")

  State.step_grid_view:add_child(UIBuilder.create_styled_row_group(new_idx, State.num_steps))
  TrackManager.apply_global_note_constraints()

  song.selected_track_index = insert_pos
end

---------------------------------------------------------------
-- Main dialog
---------------------------------------------------------------

local function show_sequencer_dialog()
  -- Close existing dialog
  if State.dialog and State.dialog.visible then
    State.dialog:close()
  end

  -- Remove previous instrument notifier
  if State.instruments_notifier then
    pcall(function()
      renoise.song().instruments_observable:remove_notifier(State.instruments_notifier)
    end)
    State.instruments_notifier = nil
  end

  -- Clean up old MIDI mappings
  MidiMappings.cleanup_all_mappings()

  -- Fresh ViewBuilder
  local vb = renoise.ViewBuilder()
  State.vb = vb

  -- Clear UI references (preserve nothing)
  State.step_indicators     = {}
  State.step_grid_view      = nil
  State.step_indicators_row = nil
  State.track_note_rows     = {}
  State.track_volume_rows   = {}
  State.track_delay_rows    = {}

  -- Grid container
  State.step_grid_view = vb:column{
    spacing    = Constants.ROW_SPACING,
    background = "plain",
  }

  -- Step indicators (create max 64, hide unused)
  State.step_indicators_row = UIBuilder.create_step_indicators(64)
  for s = 1, #State.step_indicators do
    if State.step_indicators[s] then
      State.step_indicators[s].visible = (s <= State.num_steps)
    end
  end

  Playback.setup_line_change_notifier()
  Playback.update_step_indicators()

  --------------- Controls row ---------------
  local controls_row = vb:row{
    vb:button{
      text = "+", width = Constants.CELL_SIZE, height = Constants.CELL_SIZE,
      tooltip = "Add Row",
      notifier = add_sequencer_row
    },
    vb:button{
      id = "play_stop_button",
      text = "▶", width = Constants.CELL_SIZE, height = Constants.CELL_SIZE,
      tooltip = "Play/Stop",
      notifier = function()
        renoise.song().transport.playing = not renoise.song().transport.playing
        if not renoise.song().transport.playing then
          for _, ind in ipairs(State.step_indicators) do
            ind.color = Constants.INACTIVE_COLOR
          end
        end
      end
    },
    vb:button{
      text = "↩", font = "bold", width = Constants.CELL_SIZE, height = Constants.CELL_SIZE,
      tooltip = "Clear",
      notifier = function() PatternWriter.clear_pattern_and_sequencer() end
    },
    vb:button{
      text = "Refresh Inst", height = Constants.CELL_SIZE,
      tooltip = "Refresh Instruments to sequencer data",
      notifier = function() TrackManager.refresh_instrument_dropdowns() end
    },
    vb:button{
      text = "Sync Pattern", font = "mono",
      width = Constants.CELL_SIZE, height = Constants.CELL_SIZE,
      tooltip = "Sync Pattern to Sequencer data",
      notifier = function() PatternWriter.sync_pattern_to_sequencer() end
    },

    vb:text{ text = "Steps:" },
    vb:popup{
      id = "steps_dropdown",
      items = Constants.NUM_STEPS_OPTIONS,
      height = Constants.CELL_SIZE, width = Constants.CELL_SIZE * 2,
      value = find_steps_index(Constants.DEFAULT_PATTERN_LENGTH),
      notifier = function(index)
        State.num_steps = tonumber(vb.views.steps_dropdown.items[index])
        update_step_count(State.num_steps)
      end
    },

    vb:text{ text = "Oct Range:" },
    vb:popup{
      id = "octave_range_dropdown",
      items = {"1","2","3","4"},
      height = Constants.CELL_SIZE, width = Constants.CELL_SIZE * 2,
      value = math.max(1, math.min(4, State.global_octave_range)),
      notifier = function(index)
        State.global_octave_range = index
        TrackManager.apply_global_note_constraints()
      end
    },

    vb:text{ text = "Scale:" },
    vb:popup{
      id = "scale_mode_dropdown",
      items = MusicTheory.get_available_scales(),
      height = Constants.CELL_SIZE, value = 1,
      notifier = function(index)
        State.global_scale_mode = vb.views.scale_mode_dropdown.items[index]
        TrackManager.apply_global_note_constraints()
      end
    },

    vb:text{ text = "Key:" },
    vb:popup{
      id = "scale_key_dropdown",
      height = Constants.CELL_SIZE, width = Constants.CELL_SIZE * 2,
      items = Constants.KEY_NAMES,
      value = State.global_scale_key,
      notifier = function(index)
        State.global_scale_key = index
        TrackManager.apply_global_note_constraints()
      end
    },
  }

  --------------- Load or create session ---------------
  State.sequencer_data   = {}
  State.track_visibility = {}
  State.track_mapping    = {}

  local loaded = PatternWriter.load_sequencer_from_pattern()

  if not loaded then
    print("Creating new sequencer session")
    State:add_row()
    State.num_rows = 1
    TrackManager.setup_default_track_group()
  else
    print("Loaded sequencer from existing tracks (num_rows: " .. State.num_rows .. ")")
  end

  -- Build UI rows
  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row then
      if not State.track_visibility[r] then
        State.track_visibility[r] = {note_visible = false, volume_visible = false, delay_visible = false}
      end
      if not row.step_delays then row.step_delays = {} end
      State.step_grid_view:add_child(UIBuilder.create_styled_row_group(r, State.num_steps))
    end
  end

  TrackManager.apply_global_note_constraints()
  PatternWriter.sync_pattern_to_sequencer()

  --------------- Layout ---------------
  local sequencer_section = vb:column{
    spacing = Constants.INDICATOR_SPACING,
    State.step_indicators_row,
    State.step_grid_view,
  }

  local dialog_content = vb:column{
    margin  = Constants.DIALOG_MARGIN,
    spacing = Constants.SECTION_SPACING,
    controls_row,
    sequencer_section,
  }

  --------------- Notifiers ---------------
  renoise.tool().app_idle_observable:add_notifier(function()
    if renoise.song().transport.playing then
      Playback.update_step_indicators()
    end
  end)

  renoise.song().transport.playing_observable:add_notifier(function()
    Playback.update_step_indicators()
    Playback.update_play_button()
  end)

  --------------- Show dialog ---------------
  State.dialog = renoise.app():show_custom_dialog("Requencer", dialog_content, function() end)

  Playback.update_play_button()

  -- Watch for instrument changes
  State.instruments_notifier = function()
    print("Instruments changed, refreshing dropdowns...")
    TrackManager.refresh_instrument_dropdowns()
  end
  renoise.song().instruments_observable:add_notifier(State.instruments_notifier)
end

-- Store reference so track_manager can reopen the dialog
State.show_sequencer_dialog = show_sequencer_dialog

---------------------------------------------------------------
-- Menu entry
---------------------------------------------------------------

renoise.tool():add_menu_entry{
  name   = "Main Menu:Tools:Requencer",
  invoke = show_sequencer_dialog,
}
