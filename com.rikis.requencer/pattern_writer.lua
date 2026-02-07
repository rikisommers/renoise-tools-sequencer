---------------------------------------------------------------
-- pattern_writer.lua
-- All Renoise pattern read/write/clear operations.
-- This is the data-access layer between sequencer state and
-- the Renoise pattern editor.
---------------------------------------------------------------

local Constants   = require("constants")
local MusicTheory = require("music_theory")
local State       = require("state")

local PatternWriter = {}

---------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------

--- Resolve the actual Renoise track index for a sequencer row.
local function track_index_for(row_index)
  return State.track_mapping[row_index] or row_index
end

---------------------------------------------------------------
-- Step-level pattern operations
---------------------------------------------------------------

--- Clear all note columns for a specific step across the entire pattern.
-- @param row_index  number
-- @param step       number
function PatternWriter.clear_step_from_pattern(row_index, step)
  local track_index = track_index_for(row_index)
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)

  for line_index = step, pattern.number_of_lines, State.num_steps do
    local line = pattern:track(track_index):line(line_index)
    for i = 1, 12 do
      local nc = line:note_column(i)
      if nc then
        nc.note_value       = 121
        nc.instrument_value = 255
        nc.volume_value     = 255
        nc.delay_value      = 0
        nc.panning_value    = 255
      end
    end
  end
  print("Cleared all pattern notes for row " .. row_index .. " step " .. step)
end

--- Write a note (or chord) into the pattern for a specific step.
-- @param row_index   number
-- @param step        number
-- @param note_value  number  MIDI note 0-119
function PatternWriter.update_step_note_in_pattern(row_index, step, note_value)
  print("update_step_note_in_pattern called: row=" .. row_index .. ", step=" .. step .. ", note=" .. (note_value or "nil"))

  local data = State.sequencer_data[row_index]
  if not data then
    print("ERROR: No sequencer data for row " .. row_index)
    return
  end

  if not data.instrument then
    print("ERROR: No instrument set for row " .. row_index)
    return
  end

  local instrument_index = data.instrument - 1
  local track_index = track_index_for(row_index)
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

  -- Clear existing notes for this step first
  PatternWriter.clear_step_from_pattern(row_index, step)

  -- Write new notes at the correct intervals
  for line_index = step, song.patterns[current_pattern_index].number_of_lines, State.num_steps do
    local line = song:pattern(current_pattern_index):track(track_index):line(line_index)

    -- Generate notes (single note or chord)
    local notes_to_add
    if data.is_chord_track and data.chord_type ~= "None" then
      notes_to_add = MusicTheory.generate_chord_notes(note_value, data.chord_type)
    else
      notes_to_add = {note_value}
    end

    for i, note in ipairs(notes_to_add) do
      if i <= 12 then
        local nc = line:note_column(i)
        if nc then
          nc.note_value       = note
          nc.instrument_value = instrument_index
          nc.volume_value     = 128
          nc.delay_value      = 0
          nc.panning_value    = 255
        end
      end
    end

    local chord_info = data.is_chord_track and " (" .. data.chord_type .. " chord)" or ""
    print("Added notes " .. table.concat(notes_to_add, ", ") .. chord_info ..
          " on instrument " .. (instrument_index + 1) ..
          " in track " .. track_index .. " at line " .. line_index)
  end
end

--- Add or remove a single note in the pattern for a specific step.
-- @param row_index  number
-- @param step       number
-- @param add_note   boolean  true = add, false = remove
function PatternWriter.update_note_in_pattern(row_index, step, add_note)
  local data = State.sequencer_data[row_index]
  if not (data and data.instrument) then
    print("No instrument data for row " .. row_index)
    return
  end

  local instrument_index = data.instrument - 1
  local track_index = track_index_for(row_index)
  local note_value = data.note_value or 48
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index

  for line_index = step, song.patterns[current_pattern_index].number_of_lines, State.num_steps do
    local line = song:pattern(current_pattern_index):track(track_index):line(line_index)

    if add_note then
      local nc = line:note_column(1)
      nc.note_value       = note_value
      nc.instrument_value = instrument_index
      nc.volume_value     = 128
      nc.delay_value      = 0
      nc.panning_value    = 255
      print("Added note " .. note_value .. " on instrument " .. (instrument_index + 1) ..
            " in track " .. track_index .. " at line " .. line_index)
    else
      for i = 1, 12 do
        local nc = line:note_column(i)
        if nc then
          nc.note_value       = 121
          nc.instrument_value = 255
          nc.volume_value     = 255
          nc.delay_value      = 0
          nc.panning_value    = 255
        end
      end
      print("Removed all notes in row " .. row_index .. " track " .. track_index .. " at line " .. line_index)
    end
  end
end

--- Set volume on a specific step in the pattern.
-- @param row_index     number
-- @param step          number
-- @param volume_value  number  0-128
function PatternWriter.update_step_volume_in_pattern(row_index, step, volume_value)
  local data = State.sequencer_data[row_index]
  if not (data and data.instrument) then
    print("No instrument data for row " .. row_index)
    return
  end

  local track_index = track_index_for(row_index)
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local track = song.tracks[track_index]

  for line_index = step, song.patterns[current_pattern_index].number_of_lines, State.num_steps do
    local line = song:pattern(current_pattern_index):track(track_index):line(line_index)
    local num_columns = data.is_chord_track and track.visible_note_columns or 1
    for col = 1, num_columns do
      local nc = line:note_column(col)
      if nc then
        nc.volume_value = volume_value
      end
    end
    print("Set volume to " .. volume_value .. " for step " .. step ..
          " in track " .. track_index .. " at line " .. line_index ..
          " (columns: " .. num_columns .. ")")
  end
end

--- Set delay on a specific step in the pattern.
-- @param row_index    number
-- @param step         number
-- @param delay_value  number  0-255
function PatternWriter.update_step_delay_in_pattern(row_index, step, delay_value)
  local data = State.sequencer_data[row_index]
  if not (data and data.instrument) then
    print("No instrument data for row " .. row_index)
    return
  end

  local track_index = track_index_for(row_index)
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)

  -- Enable delay column on the track
  if track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      track.delay_column_visible = true
    end
  end

  for line_index = step, pattern.number_of_lines, State.num_steps do
    local line = pattern:track(track_index):line(line_index)
    local nc = line:note_column(1)
    if nc.note_value ~= 121 then
      nc.delay_value = delay_value
      print("Set delay " .. delay_value .. " for step " .. step .. " at line " .. line_index)
    end
  end
end

---------------------------------------------------------------
-- Bulk pattern operations
---------------------------------------------------------------

--- Write the entire sequencer grid to the Renoise pattern.
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

--- Update note delay for all notes in a specific track.
-- @param value               number  0-255
-- @param target_track_index  number|nil  (defaults to selected track)
function PatternWriter.update_note_delay_value(value, target_track_index)
  local song = renoise.song()
  local track_index = target_track_index or song.selected_track_index
  local pattern = song:pattern(song.selected_pattern_index)

  if track_index > #song.tracks then
    print("ERROR: Track " .. track_index .. " doesn't exist")
    return
  end

  local track = song:track(track_index)
  if track.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    print("ERROR: Track " .. track_index .. " is not a sequencer track")
    return
  end
  if track.max_note_columns == 0 then
    print("ERROR: Track " .. track_index .. " has no note columns")
    return
  end

  local delay_hex = math.max(0, math.min(255, math.floor(value)))
  track.delay_column_visible = true

  local pt = pattern:track(track_index)
  for line_index = 1, pattern.number_of_lines do
    local nc = pt:line(line_index):note_column(1)
    if nc.note_value ~= 121 then
      nc.delay_value = delay_hex
    end
  end
  print("Set note delay to " .. delay_hex .. " for all notes in track " .. track_index)
end

--- Clear all notes from every track in the current pattern,
-- and reset all sequencer row step states + UI buttons.
function PatternWriter.clear_pattern_and_sequencer()
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)
  local vb = State.vb

  for track_index = 1, #song.tracks do
    local pt = pattern:track(track_index)
    for line_index = 1, pattern.number_of_lines do
      pt:line(line_index):clear()
    end
  end

  for row_index, _ in ipairs(State.sequencer_data) do
    for step_index = 1, State.num_steps do
      if not State.sequencer_data[row_index].step_states then
        State.sequencer_data[row_index].step_states = {}
      end
      State.sequencer_data[row_index].step_states[step_index] = 0

      local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step_index)
      if vb and vb.views[button_id] then
        vb.views[button_id].text = "   "
        vb.views[button_id].color = {80, 80, 80}
      end
    end
  end

  print("Cleared all notes from pattern and sequencer")
end

--- Clear notes that fall outside a new step range.
-- @param new_steps      number
-- @param current_steps  number
function PatternWriter.clear_notes_outside_range(new_steps, current_steps)
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)

  for track_index = 1, #song.tracks do
    local pt = pattern:track(track_index)
    for line_index = 1, pattern.number_of_lines do
      local step_in_pattern = ((line_index - 1) % current_steps) + 1
      if step_in_pattern > new_steps then
        local line = pt:line(line_index)
        for i = 1, 12 do
          local nc = line:note_column(i)
          if nc and nc.note_value ~= 121 then
            nc.note_value       = 121
            nc.instrument_value = 255
            nc.volume_value     = 255
            nc.delay_value      = 0
            nc.panning_value    = 255
          end
        end
      end
    end
  end
  print("Cleared notes outside of " .. new_steps .. " step range")
end

---------------------------------------------------------------
-- Pattern sync (read pattern -> update state + UI)
---------------------------------------------------------------

--- Sync pattern notes to sequencer (read notes from pattern and update sequencer).
function PatternWriter.sync_pattern_to_sequencer()
  if State.is_syncing_pattern then
    print("Pattern sync already in progress, skipping")
    return
  end

  State.is_syncing_pattern = true
  local vb = State.vb

  local ok, err = pcall(function()
    local song = renoise.song()
    local pattern = song:pattern(song.selected_pattern_index)

    print("=== Syncing pattern to sequencer ===")

    for row_index = 1, #State.sequencer_data do
      local track_index = track_index_for(row_index)
      local first_note_found = false

      if track_index and track_index <= #song.tracks then
        local pt = pattern:track(track_index)

        for step = 1, State.num_steps do
          local nc = pt:line(step):note_column(1)

          if nc and nc.note_value < 121 then
            State.sequencer_data[row_index].step_states[step] = 1
            State.sequencer_data[row_index].step_notes[step] = nc.note_value

            if not first_note_found then
              first_note_found = true
              State.sequencer_data[row_index].note_value = nc.note_value
              local rotary_id = "note_rotary_" .. tostring(row_index)
              if vb and vb.views[rotary_id] then
                local base = State.sequencer_data[row_index].base_note_value or 48
                vb.views[rotary_id].value = MusicTheory.map_note_to_rotary(nc.note_value, base, State.global_octave_range)
              end
            end

            -- Update UI button
            local btn_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
            if vb and vb.views[btn_id] then
              vb.views[btn_id].text = MusicTheory.note_value_to_string(nc.note_value)
              vb.views[btn_id].color = {147, 245, 66}
            end

            -- Update step note rotary
            local sr_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step)
            if vb and vb.views[sr_id] then
              local base = State.sequencer_data[row_index].base_note_value or 48
              vb.views[sr_id].value = MusicTheory.map_note_to_rotary(nc.note_value, base, State.global_octave_range)
            end

            -- Loop this note through the rest of the pattern
            for line_index = step + State.num_steps, pattern.number_of_lines, State.num_steps do
              local loop_nc = pt:line(line_index):note_column(1)
              if loop_nc then
                loop_nc.note_value       = nc.note_value
                loop_nc.instrument_value = nc.instrument_value
                loop_nc.volume_value     = nc.volume_value
                loop_nc.delay_value      = nc.delay_value
                loop_nc.panning_value    = nc.panning_value
              end
            end

            print("Row " .. row_index .. " Step " .. step .. ": Found note " ..
                  nc.note_value .. " (" .. MusicTheory.note_value_to_string(nc.note_value) .. ") - looped")
          else
            State.sequencer_data[row_index].step_states[step] = 0
            State.sequencer_data[row_index].step_notes[step] = nil

            local btn_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
            if vb and vb.views[btn_id] then
              vb.views[btn_id].text = "   "
              vb.views[btn_id].color = {80, 80, 80}
            end

            -- Clear from entire pattern
            for line_index = step, pattern.number_of_lines, State.num_steps do
              local loop_line = pt:line(line_index)
              for col = 1, 12 do
                local lnc = loop_line:note_column(col)
                if lnc then
                  lnc.note_value       = 121
                  lnc.instrument_value = 255
                  lnc.volume_value     = 255
                  lnc.delay_value      = 0
                  lnc.panning_value    = 255
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

---------------------------------------------------------------
-- Load sequencer data from existing Renoise tracks
---------------------------------------------------------------

--- Scan for existing Sequencer_ tracks and reconstruct state.
-- @return boolean  true if tracks were found and loaded
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
    local pt = pattern:track(track_index)

    track.output_delay = 0

    State.sequencer_data[row_idx] = State.create_default_row()

    local found_notes = false
    for step = 1, State.num_steps do
      if step <= pattern.number_of_lines then
        local nc = pt:line(step):note_column(1)

        if nc.note_value < 121 then
          State.sequencer_data[row_idx].step_states[step] = 1
          State.sequencer_data[row_idx].step_notes[step] = nc.note_value
          if nc.instrument_value < 255 then
            State.sequencer_data[row_idx].instrument = nc.instrument_value + 1
          end
          if nc.volume_value < 255 then
            State.sequencer_data[row_idx].step_volumes[step] = nc.volume_value
          end
          if nc.delay_value > 0 then
            State.sequencer_data[row_idx].step_delays[step] = nc.delay_value
          end
          found_notes = true
          if State.sequencer_data[row_idx].note_value == 48 then
            State.sequencer_data[row_idx].note_value = nc.note_value
            State.sequencer_data[row_idx].base_note_value = nc.note_value
          end
        elseif nc.volume_value == 0 then
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

    print("Loaded row " .. row_idx .. " from track " .. track_index ..
          " (instrument: " .. State.sequencer_data[row_idx].instrument .. ")")
  end

  State.num_rows = #sequencer_tracks
  print("=== Loaded " .. State.num_rows .. " sequencer rows from pattern ===")
  return true
end

return PatternWriter
