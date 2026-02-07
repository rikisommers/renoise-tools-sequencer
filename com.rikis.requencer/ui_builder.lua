-- All ViewBuilder UI construction.
-- Each function receives vb and dependencies through State and explicit requires.

local State = require("state")
local Constants = require("constants")
local MusicTheory = require("music_theory")
local PatternWriter = require("pattern_writer")
local TrackManager = require("track_manager")
local MidiMappings = require("midi_mappings")

local UIBuilder = {}

-- Create the step indicator row (header showing current playback position)
function UIBuilder.create_step_indicators(steps)
  local vb = State.vb
  local row = vb:row{
    spacing = Constants.control_spacing,
    margin = Constants.ROW_PADDING,
  }

  row:add_child(vb:text{width = Constants.cellSizeLg, text = "Instrument", align = "left"})
  row:add_child(vb:text{width = Constants.cellSize, text = "C", align = "left"})
  row:add_child(vb:text{width = Constants.cellSizeLg, text = "Chord", align = "left"})
  row:add_child(vb:text{width = Constants.cellSize, text = "TN", align = "center"})
  row:add_child(vb:text{width = Constants.cellSize, text = "TD", align = "center"})
  row:add_child(vb:text{width = Constants.cellSize, text = "TV", align = "center"})
  row:add_child(vb:text{width = Constants.cellSize, text = "N", align = "center"})
  row:add_child(vb:text{width = Constants.cellSize, text = "V", align = "center"})
  row:add_child(vb:text{width = Constants.cellSize, text = "D", align = "center"})

  for step = 1, steps do
    local indicator = vb:button{
      width = Constants.cellSize,
      height = Constants.cellSize,
      text = "   ",
      color = (step % 4 == 1) and Constants.BLOCK_START_COLOR or Constants.INACTIVE_COLOR,
      active = false
    }
    row:add_child(indicator)
    table.insert(State.step_indicators, indicator)
  end
  return row
end

-- Create labels spacer row (aligns rotary rows with step buttons)
local function create_labels_row()
  local vb = State.vb
  return vb:row{
    spacing = 0,
    vb:text{
      width = Constants.cellSizeLg + Constants.cellSize + Constants.cellSizeLg + (Constants.cellSize * 6) + 6,
      height = Constants.cellSize,
      text = ""
    }
  }
end

-- Helper: get button text and color for a step state
local function get_button_appearance(state)
  local button_off = {40, 40, 40}
  local button_play = {147, 245, 66}
  local button_stop = {245, 66, 93}

  if state == 0 then
    return "--", button_off
  elseif state == 1 then
    return "▶", button_play
  elseif state == 2 then
    return "■", button_stop
  end
end

-- Create the main step row (controls + step buttons) for a sequencer row
function UIBuilder.create_step_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local row = vb:row{
    spacing = Constants.control_spacing,

    -- Instrument selector
    vb:popup{
      id = "instrument_popup_" .. tostring(row_index),
      width = Constants.cellSizeLg,
      height = Constants.cellSize,
      items = TrackManager.get_instrument_names(),
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
      color = Constants.BUTTON_COLOR_INACTIVE,
      tooltip = "Enable/disable chord mode for this row",
      notifier = function()
        TrackManager.toggle_chord_track(row_index)
      end
    },

    -- Chord selection dropdown
    vb:popup{
      id = "chord_popup_" .. tostring(row_index),
      width = Constants.cellSizeLg,
      height = Constants.cellSize,
      items = MusicTheory.get_available_chords(),
      value = 1,
      active = false,
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
                  elseif step_state == 2 then
                    PatternWriter.update_note_in_pattern(row_index, s, false)
                    PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
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
        local base_note_value = State.sequencer_data[row_index].base_note_value
        local new_note_value = MusicTheory.percentage_to_note(value, base_note_value, State.global_octave_range, State.global_scale_mode, State.global_scale_key)

        local constrained_percentage = MusicTheory.note_to_percentage(new_note_value, base_note_value, State.global_octave_range)
        local track_rotary_id = "note_rotary_" .. tostring(row_index)
        if math.abs(constrained_percentage - value) > 0.1 and vb.views[track_rotary_id] then
          vb.views[track_rotary_id].value = constrained_percentage
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

        print("Updated track " .. row_index .. " note from " .. old_track_note .. " to " .. new_note_value .. " (transposition: " .. transposition .. " semitones)")
      end
    },

    -- Track Delay rotary
    vb:rotary{
      id = "track_delay_rotary_" .. tostring(row_index),
      min = -100,
      max = 100,
      value = 0,
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
      value = 100,
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
  }

  -- Register MIDI mappings for track controls
  MidiMappings.register_track_mappings(row_index)

  -- Add 3-state step buttons
  for s = 1, actual_steps do
    local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)

    if not State.sequencer_data[row_index].step_states then
      State.sequencer_data[row_index].step_states = {}
    end
    if not State.sequencer_data[row_index].step_states[s] then
      State.sequencer_data[row_index].step_states[s] = 0
    end

    local initial_text, initial_color = get_button_appearance(State.sequencer_data[row_index].step_states[s])

    row:add_child(vb:button{
      id = button_id,
      text = initial_text,
      color = initial_color,
      width = Constants.cellSize,
      height = Constants.cellSize,
      notifier = function()
        local current_state = State.sequencer_data[row_index].step_states[s]
        local new_state = (current_state + 1) % 3
        State.sequencer_data[row_index].step_states[s] = new_state

        local new_text, new_color = get_button_appearance(new_state)
        if vb.views[button_id] then
          vb.views[button_id].text = new_text
          vb.views[button_id].color = new_color
          vb.views[button_id].width = Constants.cellSize
        end

        print("Step state changed:")
        print("  Row: " .. row_index)
        print("  Step: " .. s)
        print("  Old state: " .. current_state .. " New state: " .. new_state)

        if new_state == 0 then
          PatternWriter.update_note_in_pattern(row_index, s, false)
        elseif new_state == 1 then
          local note_to_use = State.sequencer_data[row_index].step_notes and State.sequencer_data[row_index].step_notes[s] or State.sequencer_data[row_index].note_value
          PatternWriter.update_step_note_in_pattern(row_index, s, note_to_use)
          if vb.views[button_id] then
            vb.views[button_id].text = MusicTheory.note_value_to_string(note_to_use)
            vb.views[button_id].width = Constants.cellSize
          end
        elseif new_state == 2 then
          PatternWriter.update_note_in_pattern(row_index, s, false)
          PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
        end
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
    create_labels_row()
  }

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
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
        value = 50,
        width = Constants.cellSize,
        height = Constants.cellSize,
        notifier = function(value)
          local base_note_value = State.sequencer_data[row_index].base_note_value or 48
          local note_value = MusicTheory.percentage_to_note(value, base_note_value, State.global_octave_range, State.global_scale_mode, State.global_scale_key)

          if not State.sequencer_data[row_index].step_notes then
            State.sequencer_data[row_index].step_notes = {}
          end
          State.sequencer_data[row_index].step_notes[s] = note_value

          local constrained_percentage = MusicTheory.note_to_percentage(note_value, base_note_value, State.global_octave_range)
          if math.abs(constrained_percentage - value) > 0.1 then
            vb.views[rotary_id].value = constrained_percentage
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

          if not State.is_syncing_pattern and step_state > 0 then
            PatternWriter.update_step_note_in_pattern(row_index, s, note_value)
          end

          print("Set step " .. s .. " note to " .. note_value .. " for row " .. row_index)
        end
      },
    })

    MidiMappings.register_step_note_mapping(row_index, s, rotary_id)
  end

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
    create_labels_row()
  }

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
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
        value = 100,
        width = Constants.cellSize,
        height = Constants.cellSize,
        notifier = function(value)
          local volume_value = math.floor((value / 100) * 127)

          if not State.sequencer_data[row_index].step_volumes then
            State.sequencer_data[row_index].step_volumes = {}
          end
          State.sequencer_data[row_index].step_volumes[s] = volume_value

          local step_state = State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s]
          if not State.is_syncing_pattern and step_state and step_state > 0 then
            PatternWriter.update_step_volume_in_pattern(row_index, s, volume_value)
          end

          print("Set step " .. s .. " volume to " .. volume_value .. " for row " .. row_index)
        end
      },
    })

    MidiMappings.register_step_volume_mapping(row_index, s, rotary_id)
  end

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
    create_labels_row()
  }

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
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
        value = 0,
        width = Constants.cellSize,
        height = Constants.cellSize,
        notifier = function(value)
          if not State.sequencer_data[row_index].step_delays then
            State.sequencer_data[row_index].step_delays = {}
          end
          State.sequencer_data[row_index].step_delays[s] = math.floor(value)

          local step_state = State.sequencer_data[row_index].step_states and State.sequencer_data[row_index].step_states[s]
          if not State.is_syncing_pattern and step_state and step_state > 0 then
            PatternWriter.update_step_delay_in_pattern(row_index, s, math.floor(value))
          end

          print("Set step " .. s .. " delay to " .. math.floor(value) .. " for row " .. row_index)
        end
      },
    })

    MidiMappings.register_step_delay_mapping(row_index, s, rotary_id)
  end

  local wrapper = vb:column{
    spacing = 1,
    delay_row
  }

  State.track_delay_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].delay_visible

  return wrapper
end

-- Wrap a complete sequencer row group with styled container
function UIBuilder.create_styled_row_group(row_index, steps)
  local vb = State.vb
  local step_row = UIBuilder.create_step_row(row_index, steps)
  local note_row = UIBuilder.create_note_row(row_index, steps)
  local volume_row = UIBuilder.create_volume_row(row_index, steps)
  local delay_row = UIBuilder.create_delay_row(row_index, steps)

  local row_group = vb:column{
    step_row,
    note_row,
    volume_row,
    delay_row
  }

  return vb:row{
    margin = Constants.ROW_PADDING,
    style = "group",
    row_group
  }
end

return UIBuilder
