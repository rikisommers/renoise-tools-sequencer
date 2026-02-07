-- Track lifecycle management: create, delete, mute, visibility, phrase export,
-- chord mode, instrument handling, and global note constraint application.

local State = require("state")
local Constants = require("constants")
local MusicTheory = require("music_theory")
local PatternWriter = require("pattern_writer")

local TrackManager = {}

-- Toggle note row visibility for a given sequencer row
function TrackManager.toggle_note_row_visibility(row_index)
  local vb = State.vb
  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end

  local is_visible = State.track_visibility[row_index].note_visible
  State.track_visibility[row_index].note_visible = not is_visible

  if State.track_note_rows[row_index] then
    State.track_note_rows[row_index].visible = not is_visible
  end

  local toggle_id = "note_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_visible and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end

  print("Note row " .. row_index .. " visibility: " .. tostring(not is_visible))
end

-- Toggle volume row visibility for a given sequencer row
function TrackManager.toggle_volume_row_visibility(row_index)
  local vb = State.vb
  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end

  local is_visible = State.track_visibility[row_index].volume_visible
  State.track_visibility[row_index].volume_visible = not is_visible

  if State.track_volume_rows[row_index] then
    State.track_volume_rows[row_index].visible = not is_visible
  end

  local toggle_id = "volume_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_visible and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end

  print("Volume row " .. row_index .. " visibility: " .. tostring(not is_visible))
end

-- Toggle delay row visibility for a given sequencer row
function TrackManager.toggle_delay_row_visibility(row_index)
  local vb = State.vb
  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end

  local is_visible = State.track_visibility[row_index].delay_visible
  State.track_visibility[row_index].delay_visible = not is_visible

  if State.track_delay_rows[row_index] then
    State.track_delay_rows[row_index].visible = not is_visible
  end

  local track_index = State:get_track_index_for_row(row_index)
  local song = renoise.song()
  if track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      track.delay_column_visible = not is_visible
    end
  end

  local toggle_id = "delay_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_visible and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end

  print("Delay row " .. row_index .. " visibility: " .. tostring(not is_visible))
end

-- Toggle chord mode for a sequencer row
function TrackManager.toggle_chord_track(row_index)
  local vb = State.vb
  if not State.sequencer_data[row_index] then return end

  local is_chord = State.sequencer_data[row_index].is_chord_track
  State.sequencer_data[row_index].is_chord_track = not is_chord

  local toggle_id = "chord_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_chord and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end

  local popup_id = "chord_popup_" .. tostring(row_index)
  if vb.views[popup_id] then
    vb.views[popup_id].active = not is_chord
  end

  local song = renoise.song()
  local track_index = State:get_track_index_for_row(row_index)

  if track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      if not is_chord then
        local chord_type = State.sequencer_data[row_index].chord_type or "None"
        local chord_intervals = Constants.CHORD_TYPES[chord_type]
        if chord_intervals and #chord_intervals > 0 then
          local num_notes = #chord_intervals
          track.visible_note_columns = math.max(1, math.min(12, num_notes))
          print("Expanded track " .. track_index .. " to " .. num_notes .. " note columns for chord mode")
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
        print("Updated all active steps to chord notes")
      else
        track.visible_note_columns = 1

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
        print("Collapsed track " .. track_index .. " to 1 note column")
      end
    end
  end

  print("Chord track " .. row_index .. " enabled: " .. tostring(not is_chord))
end

-- Clear a sequencer row (remove notes from pattern and reset sequencer data)
function TrackManager.remove_sequencer_row(row_index)
  local vb = State.vb
  if not State.sequencer_data[row_index] then
    print("ERROR: Row " .. row_index .. " doesn't exist")
    return
  end

  local song = renoise.song()
  local track_index = State:get_track_index_for_row(row_index)

  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)

  if track_index and track_index <= #song.tracks then
    local pattern_track = pattern:track(track_index)
    for line_index = 1, pattern.number_of_lines do
      local line = pattern_track:line(line_index)
      line:clear()
    end
    print("Cleared all pattern notes for row " .. row_index .. " (track " .. track_index .. ")")
  end

  State.sequencer_data[row_index].step_states = {}
  State.sequencer_data[row_index].step_notes = {}
  State.sequencer_data[row_index].step_volumes = {}
  for s = 1, State.num_steps do
    State.sequencer_data[row_index].step_states[s] = 0
  end

  for s = 1, State.num_steps do
    local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
    if vb.views[button_id] then
      vb.views[button_id].text = "--"
      vb.views[button_id].color = {80, 80, 80}
      vb.views[button_id].width = Constants.cellSize
    end
  end

  print("Cleared row " .. row_index .. " (pattern and steps reset)")
end

-- Remove row AND delete the associated track from Renoise
function TrackManager.remove_sequencer_row_and_track(row_index)
  if not State.sequencer_data[row_index] then
    print("ERROR: Row " .. row_index .. " doesn't exist")
    return
  end

  local song = renoise.song()
  local track_index = State:get_track_index_for_row(row_index)

  if track_index and track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.name:match("^Sequencer_") then
      song:delete_track_at(track_index)
      print("Deleted track " .. track_index .. " (" .. track.name .. ") from Renoise")
    else
      print("WARNING: Track " .. track_index .. " is not a sequencer track, not deleting")
      return
    end
  end

  table.remove(State.sequencer_data, row_index)
  table.remove(State.track_visibility, row_index)

  State.track_mapping = {}
  for r = 1, #State.sequencer_data do
    local found = false
    for t = 1, #song.tracks do
      if song.tracks[t].name:match("^Sequencer_") then
        local seq_count = 0
        for tt = 1, t do
          if song.tracks[tt].name:match("^Sequencer_") then
            seq_count = seq_count + 1
          end
        end
        if seq_count == r then
          State.track_mapping[r] = t
          found = true
          break
        end
      end
    end
    if found then
      print("Mapped row " .. r .. " to track " .. State.track_mapping[r])
    end
  end

  State.num_rows = #State.sequencer_data
  print("Updated num_rows to " .. State.num_rows)

  if State.dialog and State.dialog.visible then
    State.dialog:close()
    if State.show_sequencer_dialog then
      State.show_sequencer_dialog()
    end
  end
end

-- Find the last sequencer track index (before send/master tracks)
function TrackManager.find_last_sequencer_track_index()
  local song = renoise.song()
  local last_sequencer_index = 0

  local has_seq_tracks = false
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.name:match("^Sequencer_") then
      has_seq_tracks = true
      last_sequencer_index = i
    elseif track.type == renoise.Track.TRACK_TYPE_SEQUENCER or
           track.type == renoise.Track.TRACK_TYPE_GROUP then
      if not has_seq_tracks then
        last_sequencer_index = i
      end
    end
  end

  if last_sequencer_index == 0 then
    last_sequencer_index = song.selected_track_index
  end

  return last_sequencer_index
end

-- Rebuild the track mapping (maps sequencer row indices to Renoise track indices)
function TrackManager.rebuild_track_mapping()
  local song = renoise.song()
  State.track_mapping = {}

  local seq_track_count = 0
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.name:match("^Sequencer_") then
      seq_track_count = seq_track_count + 1
      State.track_mapping[seq_track_count] = i
      print("Mapped row " .. seq_track_count .. " to track " .. i .. " (" .. track.name .. ")")
    end
  end

  if seq_track_count > #State.sequencer_data then
    print("WARNING: Found " .. seq_track_count .. " sequencer tracks but only " .. #State.sequencer_data .. " data rows")
    for i = #song.tracks, 1, -1 do
      local track = song.tracks[i]
      if track.name:match("^Sequencer_") then
        local has_data = false
        for row_idx = 1, #State.sequencer_data do
          if State.track_mapping[row_idx] == i then
            has_data = true
            break
          end
        end

        if not has_data and track.type ~= renoise.Track.TRACK_TYPE_MASTER and track.type ~= renoise.Track.TRACK_TYPE_SEND then
          print("Deleting orphaned track " .. i .. ": " .. track.name)
          song:delete_track_at(i)
        end
      end
    end

    State.track_mapping = {}
    seq_track_count = 0
    for i = 1, #song.tracks do
      local track = song.tracks[i]
      if track.name:match("^Sequencer_") then
        seq_track_count = seq_track_count + 1
        State.track_mapping[seq_track_count] = i
        print("Re-mapped row " .. seq_track_count .. " to track " .. i .. " (" .. track.name .. ")")
      end
    end
  end
end

-- Create default sequencer tracks
function TrackManager.setup_default_track_group()
  local song = renoise.song()

  print("=== Starting setup_default_track_group ===")

  local insert_pos = 1
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      insert_pos = i + 1
    end
  end

  print("Will insert new tracks starting at position " .. insert_pos)

  for i = 1, State.num_rows do
    local instrument_name = "Unknown"
    if State.sequencer_data[i] and State.sequencer_data[i].instrument then
      local inst = song.instruments[State.sequencer_data[i].instrument]
      if inst then instrument_name = inst.name end
    end

    song:insert_track_at(insert_pos)
    local track = song.tracks[insert_pos]
    track.name = "Sequencer_" .. instrument_name
    track.color = {0x60, 0xC0, 0xFF}
    track.output_delay = 0

    State.track_mapping[i] = insert_pos
    print("Row " .. i .. " -> Track " .. insert_pos .. " (" .. instrument_name .. ")")

    insert_pos = insert_pos + 1
  end

  print("=== Completed setup_default_track_group ===")

  if State.track_mapping[1] then
    song.selected_track_index = State.track_mapping[1]
  end
end

-- Update mute button color based on track mute state
function TrackManager.update_mute_button_color(row_index)
  local vb = State.vb
  local track_index = State:get_track_index_for_row(row_index)
  if not track_index then return end

  local song = renoise.song()
  if track_index > #song.tracks then return end

  local track = song.tracks[track_index]
  local button_id = "mute_button_" .. tostring(row_index)

  if vb.views[button_id] then
    local is_muted = (track.mute_state == renoise.Track.MUTE_STATE_MUTED or
                      track.mute_state == renoise.Track.MUTE_STATE_OFF)
    vb.views[button_id].color = is_muted and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end
end

-- Toggle mute/unmute for the track associated with a sequencer row
function TrackManager.toggle_track_mute(row_index)
  local track_index = State:get_track_index_for_row(row_index)
  if not track_index then return end

  local song = renoise.song()
  local track = song.tracks[track_index]

  if track then
    local is_muted = (track.mute_state == renoise.Track.MUTE_STATE_MUTED or
                      track.mute_state == renoise.Track.MUTE_STATE_OFF)
    if is_muted then
      track:unmute()
    else
      track:mute()
    end
    TrackManager.update_mute_button_color(row_index)
  end
end

-- Save a sequencer row as a Renoise phrase
function TrackManager.save_row_as_phrase(row_index)
  local vb = State.vb
  local data = State.sequencer_data[row_index]
  if not data or not data.instrument then
    print("No data to save for row " .. row_index)
    return
  end

  local song = renoise.song()
  local instrument = song.instruments[data.instrument]

  local phrase_index = #instrument.phrases + 1
  local new_phrase = instrument:insert_phrase_at(phrase_index)

  new_phrase.number_of_lines = State.num_steps
  new_phrase.lpb = song.transport.lpb

  local track_delay = 0
  local note_delay = 0

  local track_delay_control = vb.views["track_delay_rotary_" .. tostring(row_index)]
  local note_delay_control = vb.views["note_delay_rotary_" .. tostring(row_index)]

  if track_delay_control then
    track_delay = track_delay_control.value
  end
  if note_delay_control then
    note_delay = math.floor(note_delay_control.value)
  end

  for s = 1, State.num_steps do
    if data.step_states and data.step_states[s] and data.step_states[s] > 0 then
      local line = new_phrase:line(s)
      local note_column = line:note_column(1)

      local note_to_use = data.note_value
      if data.step_notes and data.step_notes[s] then
        note_to_use = data.step_notes[s]
      end

      local volume_to_use = 127
      if data.step_volumes and data.step_volumes[s] then
        volume_to_use = data.step_volumes[s]
      end

      note_column.note_value = note_to_use
      note_column.instrument_value = data.instrument - 1
      note_column.volume_value = volume_to_use
      note_column.delay_value = note_delay

      if track_delay ~= 0 then
        local effect_column = line:effect_column(1)
        effect_column.number_string = "0D"
        effect_column.amount_value = math.abs(track_delay)
      end
    end
  end

  new_phrase.name = "Seq Row " .. row_index .. " (" .. instrument.name .. ")"

  print("Saved row " .. row_index .. " as phrase: " .. new_phrase.name)
  print("  - Track delay: " .. track_delay)
  print("  - Note delay: " .. note_delay)
  print("  - Volume data saved for active steps")
  return phrase_index
end

-- Get names of all instruments (formatted for dropdown display)
function TrackManager.get_instrument_names()
  local names = {}
  for i, instrument in ipairs(renoise.song().instruments) do
    table.insert(names, i .. ": " .. instrument.name)
  end
  return names
end

-- Refresh all instrument dropdown menus in the sequencer UI
function TrackManager.refresh_instrument_dropdowns()
  local vb = State.vb
  local updated_names = TrackManager.get_instrument_names()
  for r = 1, #State.sequencer_data do
    local popup_id = "instrument_popup_" .. tostring(r)
    if vb.views[popup_id] then
      local current_value = vb.views[popup_id].value
      vb.views[popup_id].items = updated_names
      if current_value <= #updated_names then
        vb.views[popup_id].value = current_value
      else
        vb.views[popup_id].value = 1
        if State.sequencer_data[r] then
          State.sequencer_data[r].instrument = 1
        end
      end
    end
  end
  print("Refreshed instrument dropdowns - found " .. #updated_names .. " instruments")
end

-- Apply global note constraints (octave range, scale, key) to all rows and steps
function TrackManager.apply_global_note_constraints()
  if not State.sequencer_data then return end
  local vb = State.vb

  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row then
      local base = row.base_note_value or 48
      local min_note, max_note = MusicTheory.compute_note_range(base, State.global_octave_range)
      local constrained_track_note = MusicTheory.snap_to_scale(
        MusicTheory.clamp_note(row.note_value or base),
        min_note, max_note,
        State.global_scale_mode, State.global_scale_key
      )
      row.note_value = constrained_track_note
      local track_rotary_id = "note_rotary_" .. tostring(r)
      if vb.views[track_rotary_id] then
        vb.views[track_rotary_id].value = MusicTheory.note_to_percentage(constrained_track_note, base, State.global_octave_range)
      end

      if row.step_notes then
        for s, n in pairs(row.step_notes) do
          local new_n = MusicTheory.snap_to_scale(
            MusicTheory.clamp_note(n),
            min_note, max_note,
            State.global_scale_mode, State.global_scale_key
          )
          row.step_notes[s] = new_n
          local step_rotary_id = "step_note_rotary_" .. tostring(r) .. "_" .. tostring(s)
          if vb.views[step_rotary_id] then
            vb.views[step_rotary_id].value = MusicTheory.note_to_percentage(new_n, base, State.global_octave_range)
          end
          if row.step_states and row.step_states[s] then
            if row.step_states[s] == 1 then
              PatternWriter.update_step_note_in_pattern(r, s, new_n)
            end
          end
        end
      end

      if row.step_states then
        for s = 1, State.num_steps do
          if row.step_states[s] and row.step_states[s] == 1 and (not row.step_notes or not row.step_notes[s]) then
            PatternWriter.update_step_note_in_pattern(r, s, constrained_track_note)
          end
        end
      end

      if row.instrument and row.instrument >= 1 and row.instrument <= #renoise.song().instruments then
        local inst = renoise.song().instruments[row.instrument]
        if State.global_scale_mode ~= "None" then
          pcall(function()
            inst.trigger_options.scale_mode = State.global_scale_mode
            inst.trigger_options.scale_key = State.global_scale_key
          end)
        end
      end
    end
  end
end

return TrackManager
