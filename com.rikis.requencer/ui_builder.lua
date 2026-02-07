---------------------------------------------------------------
-- ui_builder.lua
-- All ViewBuilder UI construction.
-- Returns view objects; delegates behaviour to other modules.
---------------------------------------------------------------

local Constants     = require("constants")
local MusicTheory   = require("music_theory")
local State         = require("state")
local PatternWriter = require("pattern_writer")
local TrackManager  = require("track_manager")
local MidiMappings  = require("midi_mappings")

local UIBuilder = {}

-- Shorthand constants used throughout this module
local C  = Constants
local cs = C.CELL_SIZE
local cl = C.CELL_SIZE_LG

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------

--- Get button text + colour for a step state (0=Off, 1=Play, 2=Stop).
local function get_button_appearance(state)
  if state == 0 then
    return "   ", C.BUTTON_COLOR_OFF
  elseif state == 1 then
    return " ▶ ", C.BUTTON_COLOR_PLAY
  elseif state == 2 then
    return " ■ ", C.BUTTON_COLOR_STOP
  end
end

---------------------------------------------------------------
-- Labels row (spacer to align sub-rows with main step row)
---------------------------------------------------------------

local function create_labels_row()
  local vb = State.vb
  return vb:row{
    spacing = C.CONTROL_SPACING,
    vb:text{width = cl, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
    vb:text{width = cl, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
    vb:text{width = cs, height = cs, text = ""},
  }
end

---------------------------------------------------------------
-- Step indicators (top header row)
---------------------------------------------------------------

--- Create the header row of step indicator buttons.
-- @param steps  number  Maximum number of indicators to create
-- @return view  The row view
function UIBuilder.create_step_indicators(steps)
  local vb = State.vb

  local row = vb:row{
    spacing = C.CONTROL_SPACING,
    margin  = C.ROW_PADDING,
  }

  -- Column header labels
  row:add_child(vb:text{width = cl, text = "Instrument", align = "left"})
  row:add_child(vb:text{width = cs, text = "C",  align = "left"})
  row:add_child(vb:text{width = cl, text = "Chord",     align = "left"})
  row:add_child(vb:text{width = cs, text = "TN", align = "center"})
  row:add_child(vb:text{width = cs, text = "TD", align = "center"})
  row:add_child(vb:text{width = cs, text = "TV", align = "center"})
  row:add_child(vb:text{width = cs, text = "N",  align = "center"})
  row:add_child(vb:text{width = cs, text = "V",  align = "center"})
  row:add_child(vb:text{width = cs, text = "D",  align = "center"})

  for step = 1, steps do
    local indicator = vb:button{
      width  = cs,
      height = cs,
      text   = "   ",
      color  = (step % 4 == 1) and C.BLOCK_START_COLOR or C.INACTIVE_COLOR,
      active = false,
      font   = "mono",
    }
    row:add_child(indicator)
    table.insert(State.step_indicators, indicator)
  end

  return row
end

---------------------------------------------------------------
-- Step row (main row: instrument, chord, rotaries, step buttons, actions)
---------------------------------------------------------------

function UIBuilder.create_step_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local data = State.sequencer_data[row_index]

  local row = vb:row{
    spacing = C.CONTROL_SPACING,

    -- Instrument selector
    vb:popup{
      id      = "instrument_popup_" .. tostring(row_index),
      width   = cl,
      height  = cs,
      items   = TrackManager.get_instrument_names(),
      tooltip = "Select instrument for this row",
      notifier = function(index)
        data.instrument = index
        print("Selected instrument " .. index .. " for row " .. row_index)

        local song = renoise.song()
        local track_index = TrackManager.get_track_index_for_row(row_index)
        if track_index <= #song.tracks then
          song.tracks[track_index].name = "Sequencer_" .. song.instruments[index].name
        end

        -- Update pattern instrument for active play steps
        local pattern = song:pattern(song.selected_pattern_index)
        local pt = pattern:track(track_index)
        for s = 1, State.num_steps do
          if data.step_states and data.step_states[s] == 1 then
            for li = s, pattern.number_of_lines, State.num_steps do
              local nc = pt:line(li):note_column(1)
              if nc.note_value ~= 121 then
                nc.instrument_value = index - 1
              end
            end
          end
        end
      end
    },

    -- Chord toggle
    vb:button{
      id      = "chord_toggle_" .. tostring(row_index),
      text    = "♯",
      width   = cs,
      height  = cs,
      color   = C.BUTTON_COLOR_INACTIVE,
      tooltip = "Enable/disable chord mode for this row",
      notifier = function() TrackManager.toggle_chord_track(row_index) end
    },

    -- Chord type popup
    vb:popup{
      id      = "chord_popup_" .. tostring(row_index),
      width   = cl,
      height  = cs,
      items   = MusicTheory.get_available_chords(),
      value   = 1,
      active  = false,
      tooltip = "Select chord type (enable C button first)",
      notifier = function(index)
        local chord_items = vb.views["chord_popup_" .. tostring(row_index)].items
        local chord_type = chord_items[index]
        data.chord_type = chord_type

        if data.is_chord_track then
          local song = renoise.song()
          local track_index = TrackManager.get_track_index_for_row(row_index)
          if track_index <= #song.tracks then
            local track = song.tracks[track_index]
            if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
              local intervals = C.CHORD_TYPES[chord_type]
              if intervals and #intervals > 0 then
                track.visible_note_columns = math.max(1, math.min(12, #intervals))
              else
                track.visible_note_columns = 1
              end
              for s = 1, State.num_steps do
                if data.step_states and data.step_states[s] then
                  if data.step_states[s] == 1 then
                    local note = data.step_notes and data.step_notes[s] or data.note_value
                    PatternWriter.update_step_note_in_pattern(row_index, s, note)
                  elseif data.step_states[s] == 2 then
                    PatternWriter.update_note_in_pattern(row_index, s, false)
                    PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
                  end
                end
              end
            end
          end
        end
        print("Selected chord " .. chord_type .. " for row " .. row_index)
      end
    },

    -- Track Note rotary
    vb:rotary{
      id      = "note_rotary_" .. tostring(row_index),
      min     = 0,
      max     = 100,
      value   = 50,
      width   = cs,
      height  = cs,
      tooltip = "Track Note (base pitch for all steps)",
      notifier = function(value)
        local base = data.base_note_value
        local new_note = MusicTheory.percentage_to_note(value, base, State.global_octave_range, State.global_scale_mode, State.global_scale_key)

        local constrained_pct = MusicTheory.note_to_percentage(new_note, base, State.global_octave_range)
        if math.abs(constrained_pct - value) > 0.1 then
          local ctl = vb.views["note_rotary_" .. tostring(row_index)]
          if ctl then ctl.value = constrained_pct end
        end

        local old_note = data.note_value or base
        local transposition = new_note - old_note
        data.note_value = new_note

        -- Transpose per-step notes
        if data.step_notes then
          local min_n, max_n = MusicTheory.compute_note_range(base, State.global_octave_range)
          for si, old_sn in pairs(data.step_notes) do
            local offset = old_sn - old_note
            local new_sn = MusicTheory.snap_to_scale(new_note + offset, min_n, max_n, State.global_scale_mode, State.global_scale_key)
            data.step_notes[si] = new_sn

            local sr_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(si)
            if vb.views[sr_id] then
              vb.views[sr_id].value = MusicTheory.note_to_percentage(new_sn, base, State.global_octave_range)
            end
            local btn_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(si)
            if vb.views[btn_id] and data.step_states[si] == 1 then
              vb.views[btn_id].text = MusicTheory.note_value_to_string(new_sn)
            end
          end
        end

        -- Update pattern
        if not State.is_syncing_pattern then
          for s = 1, State.num_steps do
            if data.step_states and data.step_states[s] then
              if data.step_states[s] == 1 then
                local note_to_use = data.step_notes and data.step_notes[s] or new_note
                if not (data.step_notes and data.step_notes[s]) then
                  local btn_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
                  if vb.views[btn_id] then
                    vb.views[btn_id].text = MusicTheory.note_value_to_string(new_note)
                  end
                end
                PatternWriter.update_step_note_in_pattern(row_index, s, note_to_use)
              elseif data.step_states[s] == 2 then
                PatternWriter.update_note_in_pattern(row_index, s, false)
                PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
              end
            end
          end
        end

        print("Updated track " .. row_index .. " note from " .. old_note .. " to " .. new_note .. " (transposition: " .. transposition .. ")")
      end
    },

    -- Track Delay rotary
    vb:rotary{
      id      = "track_delay_rotary_" .. tostring(row_index),
      min     = -100,
      max     = 100,
      value   = 0,
      width   = cs,
      height  = cs,
      tooltip = "Track Delay (-100ms to +100ms)",
      notifier = function(value)
        local track_index = TrackManager.get_track_index_for_row(row_index)
        local song = renoise.song()
        if track_index <= #song.tracks then
          song.tracks[track_index].output_delay = value
          print("Set track delay to " .. value .. " for track " .. track_index)
        end
      end
    },

    -- Track Volume rotary
    vb:rotary{
      id      = "track_volume_rotary_" .. tostring(row_index),
      min     = 0,
      max     = 100,
      value   = 100,
      width   = cs,
      height  = cs,
      tooltip = "Track Volume (master volume for all steps in this row)",
      notifier = function(value)
        data.track_volume = value
        local song = renoise.song()
        local track_index = TrackManager.get_track_index_for_row(row_index)
        if track_index <= #song.tracks then
          local track = song.tracks[track_index]
          if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
            track.prefx_volume.value = value / 100
          end
        end
      end
    },

    -- Visibility toggle buttons
    vb:button{
      id       = "note_toggle_" .. tostring(row_index),
      text     = "N",
      width    = cs,
      height   = cs,
      color    = C.BUTTON_COLOR_INACTIVE,
      tooltip  = "Toggle note row visibility",
      notifier = function() TrackManager.toggle_note_row_visibility(row_index) end
    },
    vb:button{
      id       = "volume_toggle_" .. tostring(row_index),
      text     = "V",
      width    = cs,
      height   = cs,
      color    = C.BUTTON_COLOR_INACTIVE,
      tooltip  = "Toggle volume row visibility",
      notifier = function() TrackManager.toggle_volume_row_visibility(row_index) end
    },
    vb:button{
      id       = "delay_toggle_" .. tostring(row_index),
      text     = "D",
      width    = cs,
      height   = cs,
      color    = C.BUTTON_COLOR_INACTIVE,
      tooltip  = "Toggle delay row visibility",
      notifier = function() TrackManager.toggle_delay_row_visibility(row_index) end
    },
  }

  -- Register MIDI mappings for track controls
  MidiMappings.register_track_mappings(row_index)

  -- 3-state step buttons
  for s = 1, actual_steps do
    local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)

    if not data.step_states then data.step_states = {} end
    if not data.step_states[s] then data.step_states[s] = 0 end

    local init_text, init_color = get_button_appearance(data.step_states[s])

    row:add_child(vb:button{
      id       = button_id,
      text     = init_text,
      color    = init_color,
      width    = cs,
      height   = cs,
      font     = "mono",
      notifier = function()
        local cur = data.step_states[s]
        local nxt = (cur + 1) % 3
        data.step_states[s] = nxt

        local txt, col = get_button_appearance(nxt)
        if vb.views[button_id] then
          vb.views[button_id].text  = txt
          vb.views[button_id].color = col
        end

        if nxt == 0 then
          PatternWriter.update_note_in_pattern(row_index, s, false)
        elseif nxt == 1 then
          local note = data.step_notes and data.step_notes[s] or data.note_value
          PatternWriter.update_step_note_in_pattern(row_index, s, note)
        elseif nxt == 2 then
          PatternWriter.update_note_in_pattern(row_index, s, false)
          PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
        end
      end
    })
  end

  -- Action buttons after steps
  row:add_child(vb:button{
    id       = "mute_button_" .. tostring(row_index),
    text     = "M",
    width    = cs,
    height   = cs,
    tooltip  = "Mute/unmute track",
    notifier = function() TrackManager.toggle_track_mute(row_index) end
  })
  TrackManager.update_mute_button_color(row_index)

  row:add_child(vb:button{
    text     = "S",
    width    = cs,
    height   = cs,
    color    = C.BUTTON_COLOR_DARK,
    tooltip  = "Save row as phrase",
    notifier = function() TrackManager.save_row_as_phrase(row_index) end
  })

  row:add_child(vb:button{
    text     = "↩",
    font     = "bold",
    width    = cs,
    height   = cs,
    color    = C.BUTTON_COLOR_DARK,
    tooltip  = "Clear pattern notes and reset row",
    notifier = function() TrackManager.remove_sequencer_row(row_index) end
  })

  row:add_child(vb:button{
    text     = "x",
    width    = cs,
    height   = cs,
    color    = C.BUTTON_COLOR_STOP,
    tooltip  = "Delete row AND remove track from Renoise",
    notifier = function() TrackManager.remove_sequencer_row_and_track(row_index) end
  })

  return row
end

---------------------------------------------------------------
-- Note row (per-step note rotaries)
---------------------------------------------------------------

function UIBuilder.create_note_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local data = State.sequencer_data[row_index]

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end

  local note_row = vb:row{
    spacing = C.CONTROL_SPACING + 6,
    create_labels_row()
  }

  for s = 1, actual_steps do
    local rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    note_row:add_child(vb:rotary{
      id    = rotary_id,
      min   = 0,
      max   = 100,
      value = 50,
      width = cs,
      height = cs,
      notifier = function(value)
        local base = data.base_note_value or 48
        local note_val = MusicTheory.percentage_to_note(value, base, State.global_octave_range, State.global_scale_mode, State.global_scale_key)

        if not data.step_notes then data.step_notes = {} end
        data.step_notes[s] = note_val

        local cpct = MusicTheory.note_to_percentage(note_val, base, State.global_octave_range)
        if math.abs(cpct - value) > 0.1 then
          vb.views[rotary_id].value = cpct
        end

        local ss = data.step_states and data.step_states[s]
        if not State.is_syncing_pattern and ss and ss > 0 then
          PatternWriter.update_step_note_in_pattern(row_index, s, note_val)
          if ss == 1 then
            local btn_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
            if vb.views[btn_id] then
              vb.views[btn_id].text = MusicTheory.note_value_to_string(note_val)
            end
          end
        end
        print("Set step " .. s .. " note to " .. note_val .. " for row " .. row_index)
      end
    })
    MidiMappings.register_step_note_mapping(row_index, s)
  end

  local wrapper = vb:column{ spacing = 1, note_row }
  State.track_note_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].note_visible
  return wrapper
end

---------------------------------------------------------------
-- Volume row (per-step volume rotaries)
---------------------------------------------------------------

function UIBuilder.create_volume_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local data = State.sequencer_data[row_index]

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end

  local vol_row = vb:row{
    spacing = C.CONTROL_SPACING + 6,
    create_labels_row()
  }

  for s = 1, actual_steps do
    local rotary_id = "step_volume_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    vol_row:add_child(vb:rotary{
      id     = rotary_id,
      min    = 0,
      max    = 100,
      value  = 100,
      width  = cs,
      height = cs,
      notifier = function(value)
        local vol = math.floor((value / 100) * 127)
        if not data.step_volumes then data.step_volumes = {} end
        data.step_volumes[s] = vol

        local ss = data.step_states and data.step_states[s]
        if not State.is_syncing_pattern and ss and ss > 0 then
          PatternWriter.update_step_volume_in_pattern(row_index, s, vol)
        end
        print("Set step " .. s .. " volume to " .. vol .. " for row " .. row_index)
      end
    })
    MidiMappings.register_step_volume_mapping(row_index, s)
  end

  local wrapper = vb:column{ spacing = 1, vol_row }
  State.track_volume_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].volume_visible
  return wrapper
end

---------------------------------------------------------------
-- Delay row (per-step delay rotaries)
---------------------------------------------------------------

function UIBuilder.create_delay_row(row_index, steps)
  local vb = State.vb
  local actual_steps = math.min(steps, State.num_steps)
  local data = State.sequencer_data[row_index]

  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end

  local delay_row = vb:row{
    spacing = C.CONTROL_SPACING + 6,
    create_labels_row()
  }

  for s = 1, actual_steps do
    local rotary_id = "step_delay_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    delay_row:add_child(vb:rotary{
      id     = rotary_id,
      min    = 0,
      max    = 255,
      value  = 0,
      width  = cs,
      height = cs,
      notifier = function(value)
        if not data.step_delays then data.step_delays = {} end
        data.step_delays[s] = math.floor(value)

        local ss = data.step_states and data.step_states[s]
        if not State.is_syncing_pattern and ss and ss > 0 then
          PatternWriter.update_step_delay_in_pattern(row_index, s, math.floor(value))
        end
        print("Set step " .. s .. " delay to " .. math.floor(value) .. " for row " .. row_index)
      end
    })
    MidiMappings.register_step_delay_mapping(row_index, s)
  end

  local wrapper = vb:column{ spacing = 1, delay_row }
  State.track_delay_rows[row_index] = wrapper
  wrapper.visible = State.track_visibility[row_index].delay_visible
  return wrapper
end

---------------------------------------------------------------
-- Styled row group (combines step + note + volume + delay rows)
---------------------------------------------------------------

function UIBuilder.create_styled_row_group(row_index, steps)
  local vb = State.vb
  local row_group = vb:column{
    UIBuilder.create_step_row(row_index, steps),
    UIBuilder.create_note_row(row_index, steps),
    UIBuilder.create_volume_row(row_index, steps),
    UIBuilder.create_delay_row(row_index, steps),
  }
  return vb:row{
    margin     = C.ROW_PADDING,
    background = "group",
    row_group
  }
end

return UIBuilder
