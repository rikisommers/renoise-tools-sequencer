-- Renoise API provides the 'renoise' global at runtime
--
-- Requencer - Step Sequencer Tool for Renoise 3.4
-- Entry point: orchestrates all modules and manages the dialog lifecycle.

local Constants = require("constants")
local MusicTheory = require("music_theory")
local State = require("state")
local PatternWriter = require("pattern_writer")
local TrackManager = require("track_manager")
local UIBuilder = require("ui_builder")
local Playback = require("playback")
local MidiMappings = require("midi_mappings")

-- Main dialog creation and orchestration
local function show_sequencer_dialog()
  -- Close existing dialog if open
  if State.dialog and State.dialog.visible then
    State.dialog:close()
  end

  -- Remove previous instrument observable if it exists
  if State.instruments_notifier then
    pcall(function()
      renoise.song().instruments_observable:remove_notifier(State.instruments_notifier)
    end)
    State.instruments_notifier = nil
  end

  -- Clean up MIDI mappings to avoid duplicates
  MidiMappings.cleanup_all_mappings()

  -- Create new ViewBuilder instance to avoid ID conflicts
  State:reset_ui()
  State.vb = renoise.ViewBuilder()
  local vb = State.vb

  -- Create step grid container
  State.step_grid_view = vb:column{
    spacing = Constants.row_spacing,
    style = "plain",
  }

  -- Create step indicators (maximum 64, hide unused)
  State.step_indicators_row = UIBuilder.create_step_indicators(64)

  for s = 1, #State.step_indicators do
    if State.step_indicators[s] then
      State.step_indicators[s].visible = (s <= State.num_steps)
    end
  end

  Playback.update_step_indicators()

  -- Helper to find current step count index in dropdown options
  local function find_steps_index(pattern_length)
    for i, option in ipairs(Constants.num_steps_options) do
      if tonumber(option) == pattern_length then
        return i
      end
    end
    return 1
  end

  -- Update the number of steps in all rows
  local function update_step_count(new_steps)
    if not State.step_grid_view then return end

    State.num_steps = new_steps

    -- Preserve step data for steps 1..new_steps, discard the rest
    for r = 1, State.num_rows do
      local row = State.sequencer_data[r]
      if row then
        local old_states  = row.step_states  or {}
        local old_notes   = row.step_notes   or {}
        local old_volumes = row.step_volumes or {}
        local old_delays  = row.step_delays  or {}

        row.step_states  = {}
        row.step_notes   = {}
        row.step_volumes = {}
        row.step_delays  = {}

        for s = 1, new_steps do
          row.step_states[s] = old_states[s] or 0
          if old_notes[s]   then row.step_notes[s]   = old_notes[s]   end
          if old_volumes[s] then row.step_volumes[s]  = old_volumes[s] end
          if old_delays[s]  then row.step_delays[s]   = old_delays[s]  end
        end
      end
    end

    -- Clear all sequencer track lines then rewrite with new step stride
    local song = renoise.song()
    local pattern = song:pattern(song.selected_pattern_index)
    for r = 1, State.num_rows do
      local track_index = State:get_track_index_for_row(r)
      if track_index and track_index <= #song.tracks then
        local pattern_track = pattern:track(track_index)
        for line_index = 1, pattern.number_of_lines do
          pattern_track:line(line_index):clear()
        end
      end
    end
    PatternWriter.write_sequencer_to_pattern()

    print("Updated sequencer to " .. new_steps .. " steps")
    show_sequencer_dialog()
  end

  -- Controls toolbar
  local controls_row = vb:row{
    -- Add Row button
    vb:button{
      text = "+",
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Add Row",
      notifier = function()
        local song = renoise.song()

        local insert_pos = 1
        for i = 1, #song.tracks do
          local track = song.tracks[i]
          if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
            insert_pos = i + 1
          end
        end

        print("Adding new row at track position: " .. insert_pos)

        song:insert_track_at(insert_pos)

        local instrument_name = "Unknown"
        if #song.instruments > 0 then
          instrument_name = song.instruments[1].name
        end

        local track = song.tracks[insert_pos]
        track.name = "Sequencer_" .. instrument_name
        track.color = {0x60, 0xC0, 0xFF}
        track.output_delay = 0

        local new_row_index = #State.sequencer_data + 1
        State.track_mapping[new_row_index] = insert_pos
        State.num_rows = State.num_rows + 1

        print("Row " .. new_row_index .. " -> Track " .. insert_pos .. " (" .. instrument_name .. ")")

        State.sequencer_data[new_row_index] = {
          instrument = 1,
          note_value = 48,
          base_note_value = 48,
          step_states = {},
          step_notes = {},
          step_volumes = {},
          step_delays = {},
          track_volume = 100,
          is_chord_track = false,
          chord_type = "None"
        }
        for s = 1, State.num_steps do
          State.sequencer_data[new_row_index].step_states[s] = 0
        end

        State.track_visibility[new_row_index] = {note_visible = false, volume_visible = false, delay_visible = false}

        local row_view = UIBuilder.create_styled_row_group(new_row_index, State.num_steps)
        State.step_grid_view:add_child(row_view)
        table.insert(State.grid_children, row_view)
        TrackManager.apply_global_note_constraints()

        song.selected_track_index = insert_pos
      end
    },

    -- Play/Stop button
    vb:button{
      id = "play_stop_button",
      text = "▶",
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Play/Stop",
      notifier = function()
        local song = renoise.song()
        song.transport.playing = not song.transport.playing
        if not song.transport.playing then
          for _, indicator in ipairs(State.step_indicators) do
            indicator.color = Constants.INACTIVE_COLOR
          end
        end
      end
    },

    -- Clear button
    vb:button{
      text = "↩",
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Clear",
      notifier = function()
        PatternWriter.clear_pattern_and_sequencer()
      end
    },

    -- Refresh instruments button
    vb:button{
      text = "Refresh Inst",
      height = Constants.cellSize,
      tooltip = "Refresh Instruments to sequencer data",
      notifier = function()
        TrackManager.refresh_instrument_dropdowns()
      end
    },

    -- Sync pattern button
    vb:button{
      text = "Sync Pattern",
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Sync Pattern to Sequencer data",
      notifier = function()
        PatternWriter.sync_pattern_to_sequencer()
      end
    },

    -- Steps dropdown
    vb:text{ text = "Steps:" },
    vb:popup{
      id = "steps_dropdown",
      items = Constants.num_steps_options,
      height = Constants.cellSize,
      width = Constants.cellSize * 2,
      value = find_steps_index(State.num_steps),
      notifier = function(index)
        State.num_steps = tonumber(vb.views.steps_dropdown.items[index])
        update_step_count(State.num_steps)
      end
    },

    -- Octave range dropdown
    vb:text{ text = "Oct Range:" },
    vb:popup{
      id = "octave_range_dropdown",
      items = {"1","2","3","4"},
      height = Constants.cellSize,
      width = Constants.cellSize * 2,
      value = math.max(1, math.min(4, State.global_octave_range)),
      notifier = function(index)
        State.global_octave_range = index
        TrackManager.apply_global_note_constraints()
      end
    },

    -- Scale dropdown
    vb:text{ text = "Scale:" },
    vb:popup{
      id = "scale_mode_dropdown",
      items = MusicTheory.get_available_scales(),
      height = Constants.cellSize,
      value = 1,
      notifier = function(index)
        local items = vb.views.scale_mode_dropdown.items
        State.global_scale_mode = items[index]
        TrackManager.apply_global_note_constraints()
      end
    },

    -- Key dropdown
    vb:text{ text = "Key:" },
    vb:popup{
      id = "scale_key_dropdown",
      height = Constants.cellSize,
      width = Constants.cellSize * 2,
      items = Constants.KEY_NAMES,
      value = State.global_scale_key,
      notifier = function(index)
        State.global_scale_key = index
        TrackManager.apply_global_note_constraints()
      end
    },
  }

  -- Initialize session data
  State:reset_data()

  local loaded_from_pattern = PatternWriter.load_sequencer_from_pattern()

  if not loaded_from_pattern then
    print("Creating new sequencer session")
    State.sequencer_data[1] = {
      instrument = 1,
      note_value = 48,
      base_note_value = 48,
      step_states = {},
      step_notes = {},
      step_volumes = {},
      step_delays = {},
      track_volume = 100,
      is_chord_track = false,
      chord_type = "None"
    }
    for s = 1, State.num_steps do
      State.sequencer_data[1].step_states[s] = 0
    end
    State.track_visibility[1] = {note_visible = false, volume_visible = false, delay_visible = false}
    State.num_rows = 1
    TrackManager.setup_default_track_group()
  else
    print("Loaded sequencer from existing tracks (num_rows: " .. State.num_rows .. ")")
  end

  -- Create UI for all sequencer rows
  for r = 1, #State.sequencer_data do
    if State.sequencer_data[r] then
      if not State.track_visibility[r] then
        State.track_visibility[r] = {note_visible = false, volume_visible = false, delay_visible = false}
      end
      if not State.sequencer_data[r].step_delays then
        State.sequencer_data[r].step_delays = {}
      end
      local row_view = UIBuilder.create_styled_row_group(r, State.num_steps)
      State.step_grid_view:add_child(row_view)
      table.insert(State.grid_children, row_view)
    end
  end

  TrackManager.apply_global_note_constraints()
  PatternWriter.sync_pattern_to_sequencer()

  -- Assemble dialog layout
  local sequencer_section = vb:column{
    spacing = Constants.indicator_spacing,
    State.step_indicators_row,
    State.step_grid_view
  }

  local dialog_content = vb:column{
    margin = Constants.dialog_margin,
    spacing = Constants.section_spacing,
    controls_row,
    sequencer_section
  }

  -- Clean up previous notifiers to prevent stacking on re-open
  if State.idle_notifier then
    pcall(function()
      renoise.tool().app_idle_observable:remove_notifier(State.idle_notifier)
    end)
    State.idle_notifier = nil
  end
  if State.playing_notifier then
    pcall(function()
      renoise.song().transport.playing_observable:remove_notifier(State.playing_notifier)
    end)
    State.playing_notifier = nil
  end

  -- Set up idle notifier for step indicator updates
  State.idle_notifier = function()
    if renoise.song().transport.playing then
      Playback.update_step_indicators()
    end
  end
  renoise.tool().app_idle_observable:add_notifier(State.idle_notifier)

  -- Update indicators when playback starts or stops
  State.playing_notifier = function()
    Playback.update_step_indicators()
    Playback.update_play_button()
  end
  renoise.song().transport.playing_observable:add_notifier(State.playing_notifier)

  -- Show dialog
  State.dialog = renoise.app():show_custom_dialog("Requencer", dialog_content, function()
    -- Dialog closed callback
  end)

  Playback.update_play_button()

  -- Watch for instrument changes
  State.instruments_notifier = function()
    print("Instruments changed, refreshing dropdowns...")
    TrackManager.refresh_instrument_dropdowns()
  end
  renoise.song().instruments_observable:add_notifier(State.instruments_notifier)
end

-- Register callback on state so track_manager can reopen dialog
State.show_sequencer_dialog = show_sequencer_dialog

-- Register menu entry
renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Requencer",
  invoke = show_sequencer_dialog
}
