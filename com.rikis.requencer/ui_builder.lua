-- All ViewBuilder UI construction.
-- Each function receives vb and dependencies through State and explicit requires.

local State = require("state")
local Constants = require("constants")
local MusicTheory = require("music_theory")
local PatternWriter = require("pattern_writer")
local TrackManager = require("track_manager")
local MidiMappings = require("midi_mappings")
local StepState = require("step_state")

local PianoRoll = require("piano_roll")
local SubRows = require("sub_rows")

local UIBuilder = {}

-- Set a rotary value without re-entering its own notifier (Renoise feedback-loop guard).
local function set_rotary_value_safely(rotary_id, new_value)
  local vb = State.vb
  if not vb or not vb.views[rotary_id] then return end
  if math.abs(vb.views[rotary_id].value - new_value) <= 0.01 then return end

  State.updating_rotary[rotary_id] = true
  vb.views[rotary_id].value = new_value
  State.updating_rotary[rotary_id] = nil
end

-- Create the step indicator row (header showing current playback position)
function UIBuilder.create_step_indicators(steps)
  local vb = State.vb
  local row = vb:row{
    spacing = Constants.control_spacing,
    margin = Constants.ROW_PADDING,
  }
  local labels = vb:row{ spacing = Constants.control_spacing }

  labels:add_child(vb:text{width = Constants.cellSizeLg, text = "Instrument", align = "left"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "C",   align = "left"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "A",   align = "center"})
  labels:add_child(vb:text{width = Constants.cellSizeLg, text = "Chord", align = "left"})
  labels:add_child(vb:text{width = Constants.cellSizeLg, text = "ARP", align = "left"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "TN",  align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "TD",  align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "TV",  align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "N",   align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "V",   align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "D",   align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "P",   align = "center"})
  labels:add_child(vb:text{width = Constants.cellSize,   text = "R",   align = "center"})
  row:add_child(SubRows.fixed_left(labels))

  for step = 1, steps do
    local indicator = vb:button{
      width = Constants.cellSize,
      height = Constants.cellSize,
      text = "   ",
      color = State.is_beat_start(step) and Constants.BLOCK_START_COLOR or Constants.INACTIVE_COLOR,
      active = false
    }
    row:add_child(indicator)
    table.insert(State.step_indicators, indicator)
  end
  return row
end

-- Left area of a sub-row: mirrors the step row's control slots, with the
-- sub-row label in the instrument column.
local function create_labels_row(row_index, key, label)
  return SubRows.create_left_area({
    [Constants.SLOT_INSTRUMENT] = SubRows.slot_label(label .. " "),
  })
end

-- Index of value in list (1 if not found)
local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return 1
end

-- Create the main step row (controls + step buttons) for a sequencer row
function UIBuilder.create_step_row(row_index, steps)
  local vb = State.vb
  local data = State.sequencer_data[row_index]
  local instrument_names = TrackManager.get_instrument_names()
  local chord_items = MusicTheory.get_available_chords()
  local actual_steps = math.min(steps, State.num_steps)
  local controls = vb:row{
    spacing = Constants.control_spacing,

    -- Instrument selector
    vb:popup{
      id = "instrument_popup_" .. tostring(row_index),
      width = Constants.cellSizeLg,
      height = Constants.cellSize,
      items = instrument_names,
      value = math.max(1, math.min(#instrument_names, data.instrument or 1)),
      tooltip = "Select instrument for this row",
      notifier = function(index)
        State.sequencer_data[row_index].instrument = index
        print("Selected instrument " .. index .. " (0-based: " .. (index-1) .. ") for row " .. row_index)

        local song = renoise.song()
        local track_index = State:get_track_index_for_row(row_index)
        if track_index <= #song.tracks then
          local instrument_name = song.instruments[index].name
          song.tracks[track_index].name = "Sequencer_" .. instrument_name
          print("Updated track " .. track_index .. " name to: " .. song.tracks[track_index].name)
        end

        local current_pattern_index = song.selected_pattern_index
        local pattern = song:pattern(current_pattern_index)
        local pattern_track = pattern:track(track_index)

        for s = 1, State.num_steps do
          if State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s] then
            local step_state = State.sequencer_data[row_index].step_states[s]
            if step_state == 1 then
              for line_index = s, pattern.number_of_lines, State.num_steps do
                local line = pattern_track:line(line_index)
                local note_column = line:note_column(1)
                if note_column.note_value ~= 121 then
                  note_column.instrument_value = index - 1
                  print("Updated step " .. s .. " at line " .. line_index .. " to instrument " .. index)
                end
              end
            elseif step_state == 2 then
              PatternWriter.write_note_off_to_step(row_index, s)
            end
          end
        end
      end
    },

    -- Chord track toggle
    vb:button{
      id = "chord_toggle_" .. tostring(row_index),
      text = "♯",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = data.is_chord_track and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Enable/disable chord mode for this row",
      notifier = function()
        TrackManager.toggle_chord_track(row_index)
      end
    },

    -- Arp toggle
    vb:button{
      id = "arp_toggle_" .. tostring(row_index),
      text = "A",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = data.arp_enabled and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Enable/disable arpeggiator for this row",
      notifier = function()
        TrackManager.toggle_arp_enabled(row_index)
      end
    },

    -- Chord selection dropdown
    vb:popup{
      id = "chord_popup_" .. tostring(row_index),
      width = Constants.cellSizeLg,
      height = Constants.cellSize,
      items = chord_items,
      value = index_of(chord_items, data.chord_type),
      active = data.is_chord_track or false,
      tooltip = "Select chord type (enable C button first)",
      notifier = function(index)
        local chord_items = vb.views["chord_popup_" .. tostring(row_index)].items
        local chord_type = chord_items[index]
        State.sequencer_data[row_index].chord_type = chord_type

        if State.sequencer_data[row_index].is_chord_track then
          local song = renoise.song()
          local track_index = State:get_track_index_for_row(row_index)

          if track_index <= #song.tracks then
            local track = song.tracks[track_index]
            if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
              local chord_intervals = Constants.CHORD_TYPES[chord_type]
              if chord_intervals and #chord_intervals > 0 then
                local num_notes = #chord_intervals
                track.visible_note_columns = math.max(1, math.min(12, num_notes))
                print("Updated track " .. track_index .. " to " .. num_notes .. " note columns for " .. chord_type .. " chord")
              else
                track.visible_note_columns = 1
              end

              for s = 1, State.num_steps do
                if State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s] then
                  local step_state = State.sequencer_data[row_index].step_states[s]
                  if step_state == 1 then
                    local note_to_use = State.sequencer_data[row_index].step_notes and State.sequencer_data[row_index].step_notes[s] or State.sequencer_data[row_index].note_value
                    PatternWriter.update_step_note_in_pattern(row_index, s, note_to_use)
                  end
                end
              end
              print("Updated all active steps with " .. chord_type .. " chord")
            end
          end
        end

        print("Selected chord " .. chord_type .. " for row " .. row_index)
      end
    },

    -- Arp mode popup
    vb:popup{
      id = "arp_mode_popup_" .. tostring(row_index),
      width = Constants.cellSizeLg,
      height = Constants.cellSize,
      items = Constants.ARP_MODES,
      value = index_of(Constants.ARP_MODES, data.arp_mode),
      active = data.arp_enabled or false,
      tooltip = "Select arp mode (enable A button first)",
      notifier = function(index)
        TrackManager.set_arp_mode(row_index, Constants.ARP_MODES[index])
      end
    },

    -- Track Note rotary
    vb:rotary{
      id = "note_rotary_" .. tostring(row_index),
      min = 0,
      max = 100,
      value = 50,
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Track Note (base pitch for all steps)",
      notifier = function(value)
        local track_rotary_id = "note_rotary_" .. tostring(row_index)
        if State.updating_rotary[track_rotary_id] then return end

        local base_note_value = State.sequencer_data[row_index].base_note_value
        local new_note_value = MusicTheory.percentage_to_note(value, base_note_value, State.global_octave_range, State.global_scale_mode, State.global_scale_key)

        local constrained_percentage = MusicTheory.note_to_percentage(new_note_value, base_note_value, State.global_octave_range)
        if math.abs(constrained_percentage - value) > 0.1 then
          set_rotary_value_safely(track_rotary_id, constrained_percentage)
        end

        local old_track_note = State.sequencer_data[row_index].note_value or base_note_value
        local transposition = new_note_value - old_track_note

        State.sequencer_data[row_index].note_value = new_note_value

        if State.sequencer_data[row_index].step_notes then
          local min_note, max_note = MusicTheory.compute_note_range(base_note_value, State.global_octave_range)
          for step_index, old_step_note in pairs(State.sequencer_data[row_index].step_notes) do
            local step_offset = old_step_note - old_track_note
            local new_step_note = new_note_value + step_offset

            new_step_note = MusicTheory.snap_to_scale(new_step_note, min_note, max_note, State.global_scale_mode, State.global_scale_key)

            State.sequencer_data[row_index].step_notes[step_index] = new_step_note

            local step_rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step_index)
            if vb.views[step_rotary_id] then
              vb.views[step_rotary_id].value = MusicTheory.note_to_percentage(new_step_note, base_note_value, State.global_octave_range)
            end

            local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step_index)
            if vb.views[button_id] and State.sequencer_data[row_index].step_states[step_index] == 1 then
              vb.views[button_id].text = MusicTheory.note_value_to_string(new_step_note)
              vb.views[button_id].width = Constants.cellSize
            end

            print("Step " .. step_index .. ": old_step=" .. old_step_note .. ", offset=" .. step_offset .. ", new_step=" .. new_step_note)
          end
        end

        if not State.is_syncing_pattern then
          for s = 1, State.num_steps do
            if State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s] then
              local step_state = State.sequencer_data[row_index].step_states[s]

              if step_state == 1 then
                local note_to_use
                if State.sequencer_data[row_index].step_notes and State.sequencer_data[row_index].step_notes[s] then
                  note_to_use = State.sequencer_data[row_index].step_notes[s]
                else
                  note_to_use = new_note_value
                  local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
                  if vb.views[button_id] then
                    vb.views[button_id].text = MusicTheory.note_value_to_string(new_note_value)
                    vb.views[button_id].width = Constants.cellSize
                  end
                end
                PatternWriter.update_step_note_in_pattern(row_index, s, note_to_use)
              elseif step_state == 2 then
                PatternWriter.update_note_in_pattern(row_index, s, false)
                PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
              end
            end
          end
        end

        SubRows.refresh_indicators(row_index)
        print("Updated track " .. row_index .. " note from " .. old_track_note .. " to " .. new_note_value .. " (transposition: " .. transposition .. " semitones)")
      end
    },

    -- Track Delay rotary
    vb:rotary{
      id = "track_delay_rotary_" .. tostring(row_index),
      min = -100,
      max = 100,
      value = (function()
        local song = renoise.song()
        local ti = State:get_track_index_for_row(row_index)
        if ti and ti <= #song.tracks then
          return math.max(-100, math.min(100, song.tracks[ti].output_delay))
        end
        return 0
      end)(),
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Track Delay (-100ms to +100ms)",
      notifier = function(value)
        local track_index = State:get_track_index_for_row(row_index)
        local song = renoise.song()
        if track_index <= #song.tracks then
          song.tracks[track_index].output_delay = value
          print("Set track delay to " .. value .. " for track " .. track_index)
        else
          print("ERROR: Track " .. track_index .. " doesn't exist")
        end
      end
    },

    -- Track Volume rotary
    vb:rotary{
      id = "track_volume_rotary_" .. tostring(row_index),
      min = 0,
      max = 100,
      value = (function()
        local song = renoise.song()
        local ti = State:get_track_index_for_row(row_index)
        if ti and ti <= #song.tracks and song.tracks[ti].type == renoise.Track.TRACK_TYPE_SEQUENCER then
          return math.max(0, math.min(100, song.tracks[ti].prefx_volume.value * 100))
        end
        return 100
      end)(),
      width = Constants.cellSize,
      height = Constants.cellSize,
      tooltip = "Track Volume (master volume for all steps in this row)",
      notifier = function(value)
        if not State.sequencer_data[row_index].track_volume then
          State.sequencer_data[row_index].track_volume = 100
        end
        State.sequencer_data[row_index].track_volume = value

        local song = renoise.song()
        local track_index = State:get_track_index_for_row(row_index)
        if track_index <= #song.tracks then
          local track = song.tracks[track_index]
          if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
            track.prefx_volume.value = value / 100
            print("Set track " .. track_index .. " volume to " .. (value / 100))
          end
        end
      end
    },

    -- Visibility toggle buttons
    vb:button{
      id = "note_toggle_" .. tostring(row_index),
      text = "N",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Toggle note row visibility",
      notifier = function()
        TrackManager.toggle_note_row_visibility(row_index)
      end
    },

    vb:button{
      id = "volume_toggle_" .. tostring(row_index),
      text = "V",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Toggle volume row visibility",
      notifier = function()
        TrackManager.toggle_volume_row_visibility(row_index)
      end
    },

    vb:button{
      id = "delay_toggle_" .. tostring(row_index),
      text = "D",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Toggle delay row visibility",
      notifier = function()
        TrackManager.toggle_delay_row_visibility(row_index)
      end
    },

    vb:button{
      id = "piano_roll_toggle_" .. tostring(row_index),
      text = "P",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Toggle piano roll visibility",
      notifier = function()
        TrackManager.toggle_piano_roll_visibility(row_index)
      end
    },

    vb:button{
      id = "repeat_toggle_" .. tostring(row_index),
      text = "R",
      width = Constants.cellSize,
      height = Constants.cellSize,
      color = Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Toggle note repeat row (R0y retrigger effects)",
      notifier = function()
        TrackManager.toggle_repeat_visibility(row_index)
      end
    },
  }

  local row = vb:row{
    spacing = Constants.control_spacing,
    SubRows.fixed_left(controls),
  }

  -- Register MIDI mappings for track controls
  MidiMappings.register_track_mappings(row_index)

  -- Add 3-state step buttons
  for s = 1, actual_steps do
    local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)

    if not State.sequencer_data[row_index].step_states then
      State.sequencer_data[row_index].step_states = {}
    end
    if State.sequencer_data[row_index].step_states[s] == nil then
      State.sequencer_data[row_index].step_states[s] = 0
    end

    local step_state = State.sequencer_data[row_index].step_states[s]
    local initial_text, initial_color = StepState.get_button_appearance(step_state, s)
    if step_state == 1 then
      local row_data = State.sequencer_data[row_index]
      local note = row_data.step_notes and row_data.step_notes[s] or row_data.note_value or row_data.base_note_value or 48
      initial_text = MusicTheory.note_value_to_string(note)
    end

    row:add_child(vb:button{
      id = button_id,
      text = initial_text,
      color = initial_color,
      width = Constants.cellSize,
      height = Constants.cellSize,
      notifier = function()
        StepState.toggle_step_playing(row_index, s)
      end
    })
  end

  -- Mute button
  local mute_button_id = "mute_button_" .. tostring(row_index)
  row:add_child(vb:button{
    id = mute_button_id,
    text = "M",
    width = Constants.cellSize,
    height = Constants.cellSize,
    tooltip = "Mute/unmute track",
    notifier = function()
      TrackManager.toggle_track_mute(row_index)
    end
  })
  TrackManager.update_mute_button_color(row_index)

  -- Save as phrase button
  row:add_child(vb:button{
    text = "S",
    width = Constants.cellSize,
    height = Constants.cellSize,
    color = {30, 30, 30},
    tooltip = "Save row as phrase",
    notifier = function()
      TrackManager.save_row_as_phrase(row_index)
    end
  })

  -- Clear row button
  row:add_child(vb:button{
    text = "↩",
    width = Constants.cellSize,
    height = Constants.cellSize,
    color = {30, 30, 30},
    tooltip = "Clear pattern notes and reset row",
    notifier = function()
      TrackManager.remove_sequencer_row(row_index)
    end
  })

  -- Delete row and track button
  row:add_child(vb:button{
    text = "x",
    width = Constants.cellSize,
    height = Constants.cellSize,
    color = {245, 66, 93},
    tooltip = "Delete row AND remove track from Renoise",
    notifier = function()
      TrackManager.remove_sequencer_row_and_track(row_index)
    end
  })

  return row
end

-- Create a note row with rotary dials for each step
function UIBuilder.create_note_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local note_row = vb:row{
    spacing = Constants.control_spacing,
    create_labels_row(row_index, "note", "Note")
  }

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = State.create_default_visibility()
  end

  for s = 1, actual_steps do
    local rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    note_row:add_child(vb:row{
      margin = 0,
      spacing = 0,
      vb:rotary{
        id = rotary_id,
        min = 0,
        max = 100,
        value = (function()
          local d = State.sequencer_data[row_index]
          local n = (d.step_notes and d.step_notes[s]) or d.note_value or d.base_note_value or 48
          return MusicTheory.note_to_percentage(n, d.base_note_value or 48, State.global_octave_range)
        end)(),
        width = Constants.cellSize,
        height = Constants.cellSize,
        notifier = function(value)
          if State.updating_rotary[rotary_id] then return end

          local base_note_value = State.sequencer_data[row_index].base_note_value or 48
          local note_value = MusicTheory.percentage_to_note(value, base_note_value, State.global_octave_range, State.global_scale_mode, State.global_scale_key)

          if not State.sequencer_data[row_index].step_notes then
            State.sequencer_data[row_index].step_notes = {}
          end
          State.sequencer_data[row_index].step_notes[s] = note_value

          local constrained_percentage = MusicTheory.note_to_percentage(note_value, base_note_value, State.global_octave_range)
          if math.abs(constrained_percentage - value) > 0.1 then
            set_rotary_value_safely(rotary_id, constrained_percentage)
          end

          local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
          local step_state = 0
          if State.sequencer_data[row_index] and State.sequencer_data[row_index].step_states then
            step_state = State.sequencer_data[row_index].step_states[s] or 0
          end

          if step_state == 1 and vb.views[button_id] then
            vb.views[button_id].text = MusicTheory.note_value_to_string(note_value)
            vb.views[button_id].width = Constants.cellSize
            print("Updated button " .. button_id .. " text to " .. MusicTheory.note_value_to_string(note_value))
          end

          if not State.is_syncing_pattern and step_state == 1 then
            PatternWriter.update_step_note_in_pattern(row_index, s, note_value)
          end

          -- Keep linked piano roll view + indicators in sync
          PianoRoll.update_display(row_index)
          SubRows.refresh_indicators(row_index)

          print("Set step " .. s .. " note to " .. note_value .. " for row " .. row_index)
        end
      },
    })

    MidiMappings.register_step_note_mapping(row_index, s, rotary_id)
  end
  SubRows.add_right_area(note_row, row_index, "note")

  local wrapper = vb:column{
    spacing = 1,
    note_row
  }

  State.track_note_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].note_visible

  return wrapper
end

-- Create a volume row with rotary dials for each step
function UIBuilder.create_volume_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local volume_row = vb:row{
    spacing = Constants.control_spacing,
    create_labels_row(row_index, "volume", "Volume")
  }

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = State.create_default_visibility()
  end

  for s = 1, actual_steps do
    local rotary_id = "step_volume_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    volume_row:add_child(vb:row{
      margin = 0,
      spacing = 0,
      vb:rotary{
        id = rotary_id,
        min = 0,
        max = 100,
        value = (function()
          local v = State.sequencer_data[row_index].step_volumes and State.sequencer_data[row_index].step_volumes[s]
          if v then return math.max(0, math.min(100, (v / 127) * 100)) end
          return 100
        end)(),
        width = Constants.cellSize,
        height = Constants.cellSize,
        notifier = function(value)
          if State.updating_rotary[rotary_id] then return end
          local volume_value = math.floor((value / 100) * 127)

          if not State.sequencer_data[row_index].step_volumes then
            State.sequencer_data[row_index].step_volumes = {}
          end
          State.sequencer_data[row_index].step_volumes[s] = volume_value

          local step_state = State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s]
          if not State.is_syncing_pattern and step_state == 1 then
            PatternWriter.update_step_volume_in_pattern(row_index, s, volume_value)
          end

          SubRows.refresh_indicators(row_index)
          print("Set step " .. s .. " volume to " .. volume_value .. " for row " .. row_index)
        end
      },
    })

    MidiMappings.register_step_volume_mapping(row_index, s, rotary_id)
  end
  SubRows.add_right_area(volume_row, row_index, "volume")

  local wrapper = vb:column{
    spacing = 1,
    volume_row
  }

  State.track_volume_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].volume_visible

  return wrapper
end

-- Create a delay row with rotary dials for each step
function UIBuilder.create_delay_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local delay_row = vb:row{
    spacing = Constants.control_spacing,
    create_labels_row(row_index, "delay", "Delay")
  }

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = State.create_default_visibility()
  end

  for s = 1, actual_steps do
    local rotary_id = "step_delay_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    delay_row:add_child(vb:row{
      margin = 0,
      spacing = 0,
      vb:rotary{
        id = rotary_id,
        min = 0,
        max = 255,
        value = (State.sequencer_data[row_index].step_delays and State.sequencer_data[row_index].step_delays[s]) or 0,
        width = Constants.cellSize,
        height = Constants.cellSize,
        notifier = function(value)
          if State.updating_rotary[rotary_id] then return end
          if not State.sequencer_data[row_index].step_delays then
            State.sequencer_data[row_index].step_delays = {}
          end
          State.sequencer_data[row_index].step_delays[s] = math.floor(value)

          local step_state = State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s]
          if not State.is_syncing_pattern and step_state == 1 then
            PatternWriter.update_step_delay_in_pattern(row_index, s, math.floor(value))
          end

          SubRows.refresh_indicators(row_index)
          print("Set step " .. s .. " delay to " .. math.floor(value) .. " for row " .. row_index)
        end
      },
    })

    MidiMappings.register_step_delay_mapping(row_index, s, rotary_id)
  end
  SubRows.add_right_area(delay_row, row_index, "delay")

  local wrapper = vb:column{
    spacing = 1,
    delay_row
  }

  State.track_delay_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].delay_visible

  return wrapper
end

-- Create the note repeat row: speed selector + per-step repeat toggles
function UIBuilder.create_repeat_row(row_index, steps)
  local vb = State.vb
  local data = State.sequencer_data[row_index]
  if not data.step_repeats then data.step_repeats = {} end
  local actual_steps = math.min(steps, State.num_steps)

  local repeat_row = vb:row{
    spacing = Constants.control_spacing,
    SubRows.create_left_area({
      [Constants.SLOT_INSTRUMENT] = SubRows.slot_label("Repeat "),
      [Constants.SLOT_CHORD_POPUP] = vb:popup{
        id = "repeat_speed_" .. tostring(row_index),
        items = Constants.REPEAT_SPEED_OPTIONS,
        value = math.max(1, math.min(15, data.repeat_speed or Constants.REPEAT_DEFAULT_SPEED)),
        width = Constants.cellSizeLg,
        height = Constants.cellSize,
        tooltip = "Retrigger speed: R0y = retrigger every y ticks (lower = faster)",
        notifier = function(index)
          TrackManager.set_repeat_speed(row_index, index)
        end
      },
    })
  }

  for s = 1, actual_steps do
    local on = data.step_repeats[s]
    repeat_row:add_child(vb:button{
      id = "repeat_step_" .. tostring(row_index) .. "_" .. tostring(s),
      text = on and "R" or "--",
      color = on and Constants.REPEAT_STEP_COLOR or Constants.BUTTON_COLOR_INACTIVE,
      width = Constants.cellSize,
      height = Constants.cellSize,
      notifier = function()
        TrackManager.toggle_repeat_step(row_index, s)
      end
    })
  end
  SubRows.add_right_area(repeat_row, row_index, "rep")

  local wrapper = vb:column{ spacing = 1, repeat_row }
  State.track_repeat_rows[row_index] = wrapper
  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = State.create_default_visibility()
  end
  wrapper.visible = State.track_visibility[row_index].repeat_visible or false
  return wrapper
end

-- Wrap a complete sequencer row group with styled container
function UIBuilder.create_styled_row_group(row_index, steps)
  local vb = State.vb
  local step_row       = UIBuilder.create_step_row(row_index, steps)
  local note_row       = UIBuilder.create_note_row(row_index, steps)
  local volume_row     = UIBuilder.create_volume_row(row_index, steps)
  local delay_row      = UIBuilder.create_delay_row(row_index, steps)
  local repeat_row     = UIBuilder.create_repeat_row(row_index, steps)
  local piano_roll_row = PianoRoll.create_piano_roll_row(row_index, steps)

  local row_group = vb:column{
    step_row,
    note_row,
    volume_row,
    delay_row,
    repeat_row,
    piano_roll_row,
  }

  SubRows.refresh_indicators(row_index)

  return vb:row{
    margin = Constants.ROW_PADDING,
    style = "group",
    row_group
  }
end

return UIBuilder
