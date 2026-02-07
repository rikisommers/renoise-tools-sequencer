-- All Renoise pattern read/write operations.
-- This is the data access layer between sequencer state and Renoise patterns.

local State = require("state")
local MusicTheory = require("music_theory")
local Constants = require("constants")

local PatternWriter = {}

-- Update a specific step with a specific volume value
function PatternWriter.update_step_volume_in_pattern(row_index, step, volume_value)
  local data = State.sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument - 1
    local track_index = State:get_track_index_for_row(row_index)
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    local track = song.tracks[track_index]

    for line_index = step, song.patterns[current_pattern_index].number_of_lines, State.num_steps do
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)
      local num_columns = data.is_chord_track and track.visible_note_columns or 1
      for col = 1, num_columns do
        local note_column = line:note_column(col)
        if note_column then
          note_column.volume_value = volume_value
        end
      end
      print("Set volume to " .. volume_value .. " for step " .. step .. " in track " .. track_index .. " at line " .. line_index .. " (columns: " .. num_columns .. ")")
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Update a specific step with a specific delay value
function PatternWriter.update_step_delay_in_pattern(row_index, step, delay_value)
  local data = State.sequencer_data[row_index]
  if data and data.instrument then
    local track_index = State:get_track_index_for_row(row_index)
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    local pattern = song:pattern(current_pattern_index)

    if track_index <= #song.tracks then
      local track = song.tracks[track_index]
      if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
        track.delay_column_visible = true
      end
    end

    for line_index = step, pattern.number_of_lines, State.num_steps do
      local pattern_track = pattern:track(track_index)
      local line = pattern_track:line(line_index)
      local note_column = line:note_column(1)
      if note_column.note_value ~= 121 then
        note_column.delay_value = delay_value
        print("Set delay " .. delay_value .. " for step " .. step .. " at line " .. line_index)
      end
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Clear all notes for a specific step across the entire pattern
function PatternWriter.clear_step_from_pattern(row_index, step)
  local track_index = State:get_track_index_for_row(row_index)
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)

  for line_index = step, pattern.number_of_lines, State.num_steps do
    local pattern_track = pattern:track(track_index)
    local line = pattern_track:line(line_index)
    for i = 1, 12 do
      local note_column = line:note_column(i)
      if note_column then
        note_column.note_value = 121
        note_column.instrument_value = 255
        note_column.volume_value = 255
        note_column.delay_value = 0
        note_column.panning_value = 255
      end
    end
  end
  print("Cleared all pattern notes for row " .. row_index .. " step " .. step)
end

-- Update a specific step with a specific note value or chord
function PatternWriter.update_step_note_in_pattern(row_index, step, note_value)
  print("update_step_note_in_pattern called: row=" .. row_index .. ", step=" .. step .. ", note=" .. (note_value or "nil"))

  local data = State.sequencer_data[row_index]
  if not data then
    print("ERROR: No sequencer data for row " .. row_index)
    return
  end

  if data.instrument then
    local instrument_index = data.instrument - 1
    local track_index = State:get_track_index_for_row(row_index)
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index

    print("Writing to track " .. track_index .. ", pattern " .. current_pattern_index .. ", instrument " .. instrument_index)

    if track_index > #song.tracks then
      print("ERROR: Track " .. track_index .. " doesn't exist (only " .. #song.tracks .. " tracks available)")
      return
    end

    local track = song.tracks[track_index]
    if track.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
      print("ERROR: Track " .. track_index .. " is not a sequencer track (type: " .. track.type .. ")")
      return
    end

    if track.max_note_columns == 0 then
      print("ERROR: Track " .. track_index .. " has no note columns available")
      return
    end

    PatternWriter.clear_step_from_pattern(row_index, step)

    for line_index = step, song.patterns[current_pattern_index].number_of_lines, State.num_steps do
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)

      local notes_to_add = {}
      if data.is_chord_track and data.chord_type ~= "None" then
        notes_to_add = MusicTheory.generate_chord_notes(note_value, data.chord_type)
      else
        notes_to_add = {note_value}
      end

      for i, note in ipairs(notes_to_add) do
        if i <= 12 then
          local note_column = line:note_column(i)
          if note_column then
            note_column.note_value = note
            note_column.instrument_value = instrument_index
            note_column.volume_value = 128
            note_column.delay_value = 0
            note_column.panning_value = 255
          end
        end
      end

      local chord_info = data.is_chord_track and " (" .. data.chord_type .. " chord)" or ""
      print("Added notes " .. table.concat(notes_to_add, ", ") .. chord_info .. " on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at line " .. line_index)
    end
  else
    print("ERROR: No instrument set for row " .. row_index)
  end
end

-- Add or remove a note in the pattern for a specific row/step
function PatternWriter.update_note_in_pattern(row_index, step, add_note)
  local data = State.sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument - 1
    local track_index = State:get_track_index_for_row(row_index)
    local note_value = data.note_value or 48

    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index

    for line_index = step, song.patterns[current_pattern_index].number_of_lines, State.num_steps do
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)

      if add_note then
        local note_column = line:note_column(1)
        note_column.note_value = note_value
        note_column.instrument_value = instrument_index
        note_column.volume_value = 128
        note_column.delay_value = 0
        note_column.panning_value = 255
        print("Added note " .. note_value .. " on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at line " .. line_index)
      else
        for i = 1, 12 do
          local note_column = line:note_column(i)
          if note_column then
            note_column.note_value = 121
            note_column.instrument_value = 255
            note_column.volume_value = 255
            note_column.delay_value = 0
            note_column.panning_value = 255
          end
        end
        print("Removed all notes in row " .. row_index .. " track " .. track_index .. " at line " .. line_index)
      end
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Write all sequencer rows to the pattern
function PatternWriter.write_sequencer_to_pattern()
  for row_index, data in ipairs(State.sequencer_data) do
    if data.instrument then
      for step_index = 1, State.num_steps do
        local step_state = data.step_states and data.step_states[step_index] or 0
        if step_state == 1 then
          local note_to_use = data.step_notes and data.step_notes[step_index] or data.note_value
          PatternWriter.update_step_note_in_pattern(row_index, step_index, note_to_use)
        elseif step_state == 2 then
          PatternWriter.update_note_in_pattern(row_index, step_index, false)
          PatternWriter.update_step_volume_in_pattern(row_index, step_index, 0)
        else
          PatternWriter.update_note_in_pattern(row_index, step_index, false)
        end
      end
    end
  end
end

-- Update note delay for all notes in a specific track
function PatternWriter.update_note_delay_value(value, target_track_index)
  local song = renoise.song()
  local track_index = target_track_index or song.selected_track_index
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)

  if track_index > #song.tracks then
    print("ERROR: Track " .. track_index .. " doesn't exist")
    return
  end

  local track = song:track(track_index)
  if track.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    print("ERROR: Track " .. track_index .. " is not a sequencer track (type: " .. track.type .. ")")
    return
  end

  if track.max_note_columns == 0 then
    print("ERROR: Track " .. track_index .. " has no note columns available")
    return
  end

  local delay_hex_value = math.floor(value)
  delay_hex_value = math.max(0, math.min(255, delay_hex_value))

  track.delay_column_visible = true

  local pattern_track = pattern:track(track_index)
  for line_index = 1, pattern.number_of_lines do
    local line = pattern_track:line(line_index)
    local note_column = line:note_column(1)
    if note_column.note_value ~= 121 then
      note_column.delay_value = delay_hex_value
    end
  end

  print("Set note delay to " .. delay_hex_value .. " (hex: " .. string.format("%02X", delay_hex_value) .. ") for all notes in track " .. track_index)
end

-- Clear all notes from pattern and reset sequencer step states/UI
function PatternWriter.clear_pattern_and_sequencer()
  local vb = State.vb
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)

  for track_index = 1, #song.tracks do
    local pattern_track = pattern:track(track_index)
    for line_index = 1, pattern.number_of_lines do
      local line = pattern_track:line(line_index)
      line:clear()
    end
  end

  for row_index, data in ipairs(State.sequencer_data) do
    for step_index = 1, State.num_steps do
      if not State.sequencer_data[row_index].step_states then
        State.sequencer_data[row_index].step_states = {}
      end
      State.sequencer_data[row_index].step_states[step_index] = 0

      local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step_index)
      if vb.views[button_id] then
        vb.views[button_id].text = "--"
        vb.views[button_id].color = {80, 80, 80}
        vb.views[button_id].width = Constants.cellSize
      end
    end
  end

  print("Cleared all notes from pattern and sequencer")
end

-- Sync pattern notes to sequencer (read from pattern, update sequencer state and UI)
function PatternWriter.sync_pattern_to_sequencer()
  if State.is_syncing_pattern then
    print("Pattern sync already in progress, skipping new request")
    return
  end

  State.is_syncing_pattern = true
  local vb = State.vb

  local ok, err = pcall(function()
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    local pattern = song:pattern(current_pattern_index)

    print("=== Syncing pattern to sequencer ===")

    for row_index = 1, #State.sequencer_data do
      local track_index = State:get_track_index_for_row(row_index)
      local first_note_found = false

      if track_index and track_index <= #song.tracks then
        local pattern_track = pattern:track(track_index)

        for step = 1, State.num_steps do
          local line = pattern_track:line(step)
          local note_column = line:note_column(1)

          if note_column and note_column.note_value < 121 then
            State.sequencer_data[row_index].step_states[step] = 1
            State.sequencer_data[row_index].step_notes[step] = note_column.note_value

            if not first_note_found then
              first_note_found = true
              State.sequencer_data[row_index].note_value = note_column.note_value
              local track_note_rotary_id = "note_rotary_" .. tostring(row_index)
              if vb.views[track_note_rotary_id] then
                local base_note_value = State.sequencer_data[row_index].base_note_value or 48
                local track_rotary_value = MusicTheory.map_note_to_rotary(note_column.note_value, base_note_value, State.global_octave_range)
                vb.views[track_note_rotary_id].value = track_rotary_value
              end
            end

            local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
            if vb.views[button_id] then
              vb.views[button_id].text = MusicTheory.note_value_to_string(note_column.note_value)
              vb.views[button_id].color = {147, 245, 66}
              vb.views[button_id].width = Constants.cellSize
            end

            local note_rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step)
            if vb.views[note_rotary_id] then
              local base_note_value = State.sequencer_data[row_index].base_note_value or 48
              local rotary_value = MusicTheory.map_note_to_rotary(note_column.note_value, base_note_value, State.global_octave_range)
              vb.views[note_rotary_id].value = rotary_value
            end

            for line_index = step + State.num_steps, pattern.number_of_lines, State.num_steps do
              local loop_line = pattern_track:line(line_index)
              local loop_note_column = loop_line:note_column(1)
              if loop_note_column then
                loop_note_column.note_value = note_column.note_value
                loop_note_column.instrument_value = note_column.instrument_value
                loop_note_column.volume_value = note_column.volume_value
                loop_note_column.delay_value = note_column.delay_value
                loop_note_column.panning_value = note_column.panning_value
              end
            end

            print("Row " .. row_index .. " Step " .. step .. ": Found note " .. note_column.note_value .. " (" .. MusicTheory.note_value_to_string(note_column.note_value) .. ") - looped through pattern")
          else
            State.sequencer_data[row_index].step_states[step] = 0
            State.sequencer_data[row_index].step_notes[step] = nil

            local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
            if vb.views[button_id] then
              vb.views[button_id].text = "--"
              vb.views[button_id].color = {80, 80, 80}
              vb.views[button_id].width = Constants.cellSize
            end

            for line_index = step, pattern.number_of_lines, State.num_steps do
              local loop_line = pattern_track:line(line_index)
              for col = 1, 12 do
                local loop_note_column = loop_line:note_column(col)
                if loop_note_column then
                  loop_note_column.note_value = 121
                  loop_note_column.instrument_value = 255
                  loop_note_column.volume_value = 255
                  loop_note_column.delay_value = 0
                  loop_note_column.panning_value = 255
                end
              end
            end
          end
        end
      end
    end

    print("Pattern sync complete!")
  end)

  State.is_syncing_pattern = false

  if not ok then
    error(err)
  end
end

-- Load sequencer data from existing tracks in the pattern
function PatternWriter.load_sequencer_from_pattern()
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)

  print("=== Attempting to load sequencer from existing tracks ===")

  local sequencer_tracks = {}
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.name:match("^Sequencer_") and track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      table.insert(sequencer_tracks, {index = i, track = track})
      print("Found sequencer track " .. i .. ": " .. track.name)
    end
  end

  if #sequencer_tracks == 0 then
    print("No existing sequencer tracks found")
    return false
  end

  for row_idx, track_info in ipairs(sequencer_tracks) do
    local track_index = track_info.index
    local track = track_info.track
    local pattern_track = pattern:track(track_index)

    track.output_delay = 0

    State.sequencer_data[row_idx] = {
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

    local found_notes = false
    for step = 1, State.num_steps do
      local line_index = step
      if line_index <= pattern.number_of_lines then
        local line = pattern_track:line(line_index)
        local note_col = line:note_column(1)

        if note_col.note_value < 121 then
          State.sequencer_data[row_idx].step_states[step] = 1
          State.sequencer_data[row_idx].step_notes[step] = note_col.note_value

          if note_col.instrument_value < 255 then
            State.sequencer_data[row_idx].instrument = note_col.instrument_value + 1
          end

          if note_col.volume_value < 255 then
            State.sequencer_data[row_idx].step_volumes[step] = note_col.volume_value
          end

          if note_col.delay_value > 0 then
            State.sequencer_data[row_idx].step_delays[step] = note_col.delay_value
          end

          found_notes = true

          if State.sequencer_data[row_idx].note_value == 48 then
            State.sequencer_data[row_idx].note_value = note_col.note_value
            State.sequencer_data[row_idx].base_note_value = note_col.note_value
          end
        elseif note_col.volume_value == 0 then
          State.sequencer_data[row_idx].step_states[step] = 2
        else
          State.sequencer_data[row_idx].step_states[step] = 0
        end
      else
        State.sequencer_data[row_idx].step_states[step] = 0
      end
    end

    if track.visible_note_columns > 1 then
      State.sequencer_data[row_idx].is_chord_track = true
    end

    State.track_mapping[row_idx] = track_index
    State.track_visibility[row_idx] = {note_visible = false, volume_visible = false, delay_visible = false}

    print("Loaded row " .. row_idx .. " from track " .. track_index .. " (instrument: " .. State.sequencer_data[row_idx].instrument .. ")")
  end

  State.num_rows = #sequencer_tracks

  print("=== Loaded " .. State.num_rows .. " sequencer rows from pattern ===")
  return true
end

-- Clear notes outside the new step range when step count changes
function PatternWriter.clear_notes_outside_range(new_steps, current_steps)
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)

  for track_index = 1, #song.tracks do
    local pattern_track = pattern:track(track_index)

    for line_index = 1, pattern.number_of_lines do
      local step_in_current_pattern = ((line_index - 1) % current_steps) + 1

      if step_in_current_pattern > new_steps then
        local line = pattern_track:line(line_index)

        for i = 1, 12 do
          local note_column = line:note_column(i)
          if note_column and note_column.note_value ~= 121 then
            note_column.note_value = 121
            note_column.instrument_value = 255
            note_column.volume_value = 255
            note_column.delay_value = 0
            note_column.panning_value = 255
          end
        end
      end
    end
  end

  print("Cleared notes outside of " .. new_steps .. " step range")
end

return PatternWriter
