local vb = renoise.ViewBuilder()

local control_margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
local control_spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
local control_height = renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT
local control_mini_height = renoise.ViewBuilder.DEFAULT_MINI_CONTROL_HEIGHT
local dialog_margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
local dialog_spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
local button_height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT

local num_steps_options = {"8", "16", "32", "64"}
local pattern = 1  -- Default pattern index
local patternLength = 16  -- Default pattern length
local cellSize = 24
local cellSizeLg = cellSize * 4





-- Global musical constraints
local global_octave_range = 1 -- 1-4 octaves
local global_scale_mode = "None"
local global_scale_key = 1 -- 1=C, 2=C#, ... 12=B

-- Mapping of common scale names to semitone intervals in one octave
-- If a scale name is not found here, we will treat it as Chromatic
local SCALE_INTERVALS = {
  ["Chromatic"] = {0,1,2,3,4,5,6,7,8,9,10,11},
  ["Major"] = {0,2,4,5,7,9,11},
  ["Natural Minor"] = {0,2,3,5,7,8,10},
  ["Harmonic Minor"] = {0,2,3,5,7,8,11},
  ["Melodic Minor"] = {0,2,3,5,7,9,11},
  ["Dorian"] = {0,2,3,5,7,9,10},
  ["Phrygian"] = {0,1,3,5,7,8,10},
  ["Lydian"] = {0,2,4,6,7,9,11},
  ["Mixolydian"] = {0,2,4,5,7,9,10},
  ["Locrian"] = {0,1,3,5,6,8,10},
  ["Whole Tone"] = {0,2,4,6,8,10},
  ["Pentatonic Major"] = {0,2,4,7,9},
  ["Pentatonic Minor"] = {0,3,5,7,10},
  ["Blues"] = {0,3,5,6,7,10}
}

local KEY_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

-- Chord definitions for different chord types
local CHORD_TYPES = {
  ["None"] = {},  -- Single note, not a chord
  ["Major"] = {0, 4, 7},
  ["Minor"] = {0, 3, 7},
  ["Diminished"] = {0, 3, 6},
  ["Augmented"] = {0, 4, 8},
  ["Major 7"] = {0, 4, 7, 11},
  ["Minor 7"] = {0, 3, 7, 10},
  ["Dominant 7"] = {0, 4, 7, 10},
  ["Sus2"] = {0, 2, 7},
  ["Sus4"] = {0, 5, 7}
}

local function get_available_scales()
  local items = {"None"}
  local song = renoise.song()
  if #song.instruments > 0 then
    local inst = song.instruments[1]
    local modes = inst.trigger_options.available_scale_modes
    for _, m in ipairs(modes) do
      table.insert(items, m)
    end
  else
    -- Fallback minimal set
    for name, _ in pairs(SCALE_INTERVALS) do
      if name ~= "Chromatic" then table.insert(items, name) end
    end
    table.sort(items)
    table.insert(items, 1, "Chromatic")
    table.insert(items, 1, "None")
  end
  return items
end

local function get_available_chords()
  local items = {}
  for name, _ in pairs(CHORD_TYPES) do
    table.insert(items, name)
  end
  table.sort(items)
  -- Move "None" to the front
  local none_index = nil
  for i, item in ipairs(items) do
    if item == "None" then
      none_index = i
      break
    end
  end
  if none_index then
    table.remove(items, none_index)
    table.insert(items, 1, "None")
  end
  return items
end

local function generate_chord_notes(root_note, chord_type)
  local intervals = CHORD_TYPES[chord_type]
  if not intervals or #intervals == 0 then
    -- Single note
    return {root_note}
  end
  
  local chord_notes = {}
  for _, interval in ipairs(intervals) do
    local note = root_note + interval
    if note >= 0 and note <= 119 then  -- Valid MIDI range
      table.insert(chord_notes, note)
    end
  end
  return chord_notes
end

local function compute_note_range(base_note_value)
  local span = 12 * math.max(1, math.min(4, global_octave_range))
  local min_note = base_note_value - math.floor(span / 2)
  local max_note = base_note_value + math.ceil(span / 2)
  min_note = math.max(0, min_note)
  max_note = math.min(119, max_note)
  if max_note <= min_note then
    max_note = math.min(119, min_note + 12)
  end
  return min_note, max_note
end

local function clamp_note(n)
  return math.max(0, math.min(119, n))
end

local function snap_to_scale(note_value, min_note, max_note)
  -- No scale restriction
  if global_scale_mode == "None" then
    return clamp_note(math.max(min_note, math.min(max_note, note_value)))
  end

  -- Determine intervals for the current scale
  local intervals = SCALE_INTERVALS[global_scale_mode]
  if not intervals then
    -- Unknown scale -> behave chromatically
    return clamp_note(math.max(min_note, math.min(max_note, note_value)))
  end

  local root_pc = (global_scale_key - 1) % 12
  local allowed_pcs = {}
  for _, iv in ipairs(intervals) do
    allowed_pcs[(root_pc + iv) % 12] = true
  end

  local target = clamp_note(note_value)
  if target < min_note then target = min_note end
  if target > max_note then target = max_note end

  if allowed_pcs[target % 12] then
    return target
  end

  -- Search nearest allowed note in [min_note, max_note]
  local best_note = target
  local best_dist = 999
  for n = min_note, max_note do
    if allowed_pcs[n % 12] then
      local d = math.abs(n - target)
      if d < best_dist then
        best_dist = d
        best_note = n
        if d == 0 then break end
      end
    end
  end
  return clamp_note(best_note)
end

local function percentage_to_note(percent, base_note_value)
  local min_note, max_note = compute_note_range(base_note_value)
  local note = math.floor(min_note + (percent / 100) * (max_note - min_note))
  return snap_to_scale(note, min_note, max_note)
end

local function note_to_percentage(note_value, base_note_value)
  local min_note, max_note = compute_note_range(base_note_value)
  local n = math.max(min_note, math.min(max_note, note_value))
  if max_note == min_note then return 0 end
  return ((n - min_note) / (max_note - min_note)) * 100
end

local function apply_global_note_constraints()
  -- Update all rows' stored notes and UI according to current range+scale
  if not sequencer_data then return end
  for r = 1, #sequencer_data do
    local row = sequencer_data[r]
    if row then
      local base = row.base_note_value or 48
      -- Update track note_value within new constraints
      local constrained_track_note = snap_to_scale(clamp_note(row.note_value or base), select(1, compute_note_range(base)), select(2, compute_note_range(base)))
      row.note_value = constrained_track_note
      local track_rotary_id = "note_rotary_" .. tostring(r)
      if vb.views[track_rotary_id] then
        vb.views[track_rotary_id].value = note_to_percentage(constrained_track_note, base)
      end

      -- Update per-step notes
      if row.step_notes then
        for s, n in pairs(row.step_notes) do
          local new_n = snap_to_scale(clamp_note(n), select(1, compute_note_range(base)), select(2, compute_note_range(base)))
          row.step_notes[s] = new_n
          local step_rotary_id = "step_note_rotary_" .. tostring(r) .. "_" .. tostring(s)
          if vb.views[step_rotary_id] then
            vb.views[step_rotary_id].value = note_to_percentage(new_n, base)
          end
          if row.steps and row.steps[s] then
            update_step_note_in_pattern(r, s, new_n)
          end
        end
      end

      -- For active steps without specific per-step notes, apply constrained track note
      if row.steps then
        for s = 1, num_steps do
          if row.steps[s] and (not row.step_notes or not row.step_notes[s]) then
            update_step_note_in_pattern(r, s, constrained_track_note)
          end
        end
      end

      -- Also try to mirror instrument trigger scale settings, if any instrument selected
      if row.instrument and row.instrument >= 1 and row.instrument <= #renoise.song().instruments then
        local inst = renoise.song().instruments[row.instrument]
        if global_scale_mode ~= "None" then
          pcall(function()
            inst.trigger_options.scale_mode = global_scale_mode
            inst.trigger_options.scale_key = global_scale_key
          end)
        end
      end
    end
  end
end

-- Sequencer settings
num_steps = 16 --patternLength
num_rows = 4
current_step = 1
is_playing = false

-- Grid for storing the current sequencer
step_grid_view = nil
sequencer_data = {}
step_indicators = {}
step_indicators_row = nil

-- Track visibility data
track_visibility = {}  -- Stores show/hide state for note and volume rows per track
track_note_rows = {}   -- References to note row views for each track
track_volume_rows = {} -- References to volume row views for each track

-- Toggle functions for row visibility
local function toggle_note_row_visibility(row_index)
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = true, volume_visible = true}
  end
  
  local is_visible = track_visibility[row_index].note_visible
  track_visibility[row_index].note_visible = not is_visible
  
  if track_note_rows[row_index] then
    track_note_rows[row_index].visible = not is_visible
  end
  
  -- Update button color
  local toggle_id = "note_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_visible and {100, 255, 100} or {80, 80, 80}
  end
  
  print("Note row " .. row_index .. " visibility: " .. tostring(not is_visible))
end

local function toggle_volume_row_visibility(row_index)
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = true, volume_visible = true}
  end
  
  local is_visible = track_visibility[row_index].volume_visible
  track_visibility[row_index].volume_visible = not is_visible
  
  if track_volume_rows[row_index] then
    track_volume_rows[row_index].visible = not is_visible
  end
  
  -- Update button color
  local toggle_id = "volume_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_visible and {100, 255, 100} or {80, 80, 80}
  end
  
  print("Volume row " .. row_index .. " visibility: " .. tostring(not is_visible))
end

local function toggle_chord_track(row_index)
  if not sequencer_data[row_index] then return end
  
  local is_chord = sequencer_data[row_index].is_chord_track
  sequencer_data[row_index].is_chord_track = not is_chord
  
  -- Update button color
  local toggle_id = "chord_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_chord and {255, 200, 100} or {80, 80, 80}
  end
  
  -- Enable/disable chord selection dropdown
  local popup_id = "chord_popup_" .. tostring(row_index)
  if vb.views[popup_id] then
    vb.views[popup_id].active = not is_chord
  end
  
  print("Chord track " .. row_index .. " enabled: " .. tostring(not is_chord))
end

-- Color definitions
local INACTIVE_COLOR = {80, 80, 80}
local ACTIVE_COLOR = {255, 255, 0}  -- Yellow for active step
local BLOCK_START_COLOR = {99, 99, 99}  -- Light gray for block start

-- NEW FUNCTION: Create default track group and add sequencer tracks
local function setup_default_track_group()
  local song = renoise.song()
  
  -- Check if sequencer tracks already exist
  local has_sequencer_tracks = false
  for i = 1, #song.tracks do
    if song.tracks[i].name:match("^Seq %d+$") then
      has_sequencer_tracks = true
      break
    end
  end
  
  if has_sequencer_tracks then
    print("Sequencer tracks already exist, skipping setup")
    return
  end
  
  -- Create new group at position 1
  local new_group = song:insert_group_at(1)

  -- Set group name
  if new_group then
    new_group.name = "Sequencer"
  end
  
  -- Add sequencer tracks - they will automatically be added to the group when inserted after it
  for i = 1, num_rows do
    local track_index = i + 1  -- Track indices: 2, 3, 4, 5...
    song:insert_track_at(track_index)  -- Insert after group
    song.tracks[track_index].name = "Seq " .. i
    print("Created track " .. track_index .. ": " .. song.tracks[track_index].name)
  end
end


-- Function to save a row as a phrase
local function save_row_as_phrase(row_index)
  local data = sequencer_data[row_index]
  if not data or not data.instrument then
    print("No data to save for row " .. row_index)
    return
  end
  
  local song = renoise.song()
  local instrument = song.instruments[data.instrument]
  
  -- Create a new phrase for the instrument
  local phrase_index = #instrument.phrases + 1
  local new_phrase = instrument:insert_phrase_at(phrase_index)
  
  -- Set phrase properties
  new_phrase.number_of_lines = num_steps
  new_phrase.lpb = 1  -- Lines per beat - 1 means each line is a step
  
  -- Get delay values from the UI controls
  local track_delay = 0
  local note_delay = 0
  
  local track_delay_control = vb.views["track_delay_rotary_" .. tostring(row_index)]
  local note_delay_control = vb.views["note_delay_rotary_" .. tostring(row_index)]
  
  if track_delay_control then
    track_delay = track_delay_control.value
  end
  if note_delay_control then
    -- Convert from 0-255 range to 0x00-0xFF hex delay value
    note_delay = math.floor(note_delay_control.value)
  end
  
  -- Add notes to the phrase based on step data
  for s = 1, num_steps do
    if data.steps[s] then  -- If step is active
      local line = new_phrase:line(s)
      local note_column = line:note_column(1)
      
      -- Use step-specific note if available, otherwise use track note
      local note_to_use = data.note_value
      if data.step_notes and data.step_notes[s] then
        note_to_use = data.step_notes[s]
      end
      
      -- Get step-specific volume if available, otherwise use default
      local volume_to_use = 127  -- Default full volume
      if data.step_volumes and data.step_volumes[s] then
        volume_to_use = data.step_volumes[s]
      end
      
      -- Set the note with delays and volume
      note_column.note_value = note_to_use
      note_column.instrument_value = data.instrument - 1  -- Zero-based
      note_column.volume_value = volume_to_use  -- Use step-specific volume
      note_column.delay_value = note_delay  -- Apply note delay
      
      -- Add track delay as an effect command if non-zero
      if track_delay ~= 0 then
        local effect_column = line:effect_column(1)
        effect_column.number_string = "0D"  -- Delay effect
        effect_column.amount_value = math.abs(track_delay)
      end
    end
  end
  
  -- Name the phrase
  new_phrase.name = "Seq Row " .. row_index .. " (" .. instrument.name .. ")"
  
  print("Saved row " .. row_index .. " as phrase: " .. new_phrase.name)
  print("  - Track delay: " .. track_delay)
  print("  - Note delay: " .. note_delay)
  print("  - Volume data saved for active steps")
  return phrase_index
end

-- Initialize default group when tool starts (moved to dialog creation)

-- Create a row of step indicators
local function create_step_indicators(steps)


  
  local row = vb:horizontal_aligner{}
    local trackDelayLabel = vb:text{
      width = cellSize,
      text = "TD"
      
  }
  local noteLabel = vb:text{
    width = cellSize,
    text = "TN"
  }
  local noteDelayLabel = vb:text{
    width = cellSize,
    text = "ND"
  }
  
  local instrumentLabel = vb:text{
      width = cellSizeLg,
      text = "I"
  }
  
  local saveLabel = vb:text{
      width = cellSize,
      text = "?"
  }
  
  local noteToggleLabel = vb:text{
      width = cellSize,
      text = "N"
  }
  
  local volumeToggleLabel = vb:text{
      width = cellSize,
      text = "V"
  }
  
  local chordToggleLabel = vb:text{
      width = cellSize,
      text = "C"
  }
  
  local chordSelectLabel = vb:text{
      width = cellSizeLg,
      text = "Chord"
  }
  
  local previewLabel = vb:text{
      width = cellSize,
      text = "►"
  }
  
  

--        update_step_count(num_steps)
--        local new_indicators_row = create_step_indicators(num_steps)
--        dialog_content:remove_child(step_indicators_row)
--        dialog_content:add_child(new_indicators_row)  -- Insert at index 2 (after the controls row)
--        step_indicators_row = new_indicators_row
 
 
   row:add_child(trackDelayLabel)
   row:add_child(noteLabel)
   row:add_child(noteDelayLabel)
  row:add_child(instrumentLabel)
  row:add_child(saveLabel)
  row:add_child(previewLabel)
  row:add_child(noteToggleLabel)
  row:add_child(volumeToggleLabel)
  row:add_child(chordToggleLabel)
  row:add_child(chordSelectLabel)
 -- step_indicators = {}  -- Clear existing indicators
  for step = 1, steps do
    local indicator = vb:button{
      width = cellSize,
      height = cellSize,
      color = (step % 4 == 1) and BLOCK_START_COLOR or INACTIVE_COLOR,
      active = false
    }
    row:add_child(indicator)
    table.insert(step_indicators, indicator)
  end
  return row
end


-- Function to trigger a sample or chord for a specific row
local function trigger_sample(row_index)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument
    local instrument = renoise.song().instruments[instrument_index]
    
    -- Check if the instrument has samples
    if #instrument.samples > 0 then
      local sample = instrument.samples[1]  -- Trigger the first sample in the instrument
      local root_note = data.note_value or 48  -- Use dynamic note value or default to C3
      local velocity = 100   -- 0-127 range
      
      -- Generate notes (single note or chord)
      local notes_to_trigger = {}
      if data.is_chord_track and data.chord_type ~= "None" then
        notes_to_trigger = generate_chord_notes(root_note, data.chord_type)
      else
        notes_to_trigger = {root_note}
      end
      
      -- Trigger all notes
      for _, note_value in ipairs(notes_to_trigger) do
        sample:trigger_attack(note_value, velocity)
      end
      
      local chord_info = data.is_chord_track and " (" .. data.chord_type .. " chord)" or ""
      print("Triggered sample on instrument " .. instrument_index .. " ('" .. instrument.name .. "') with notes " .. table.concat(notes_to_trigger, ", ") .. chord_info)
    else
      print("No samples found in instrument " .. instrument_index)
    end
  else
    print("No instrument data for row " .. row_index)
  end
end


-- Function to trigger a sample for a specific row
local function trigger_sample_bak(row_index)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument
    local track_index = row_index
    local note_value = 48 -- C3 in MIDI note numbers
    
       local instrument = renoise.song().instruments[instrument_index]
    local note_value = 48 -- C3 in MIDI note numbers
    local velocity = 100 -- 0-127 range

    -- Trigger the note using MIDI trigger
    instrument:midi_trigger(note_value, velocity)
    
    
        -- Get the current pattern and line
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    local current_line_index = song.selected_line_index
    
        -- Access the note column in the specified track and line
    local track = song:track(track_index)
    local line = song:pattern(current_pattern_index):track(track_index):line(current_line_index)
    
    -- Write the note into the pattern
    local note_column = line:note_column(1) -- Assuming first note column
    note_column.note_value = note_value
    note_column.instrument_value = instrument_index - 1 -- Instrument index is zero-based in patterns
    note_column.volume_value = 128 -- Max volume (0-128 scale)
    
    print("Triggered note C3 on instrument " .. instrument_index .. " in track " .. track_index)
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Function to update a specific step with a specific volume value
local function update_step_volume_in_pattern(row_index, step, volume_value)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument - 1  -- Zero-based index for pattern
    local track_index = row_index

    -- Get the current pattern
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index

    -- Calculate the line index based on the step and loop every num_steps ticks
    for tick = step, song.patterns[current_pattern_index].number_of_lines, num_steps do
      local line_index = (tick - 1) % song.patterns[current_pattern_index].number_of_lines + 1

      -- Access the note column in the specified track and line
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)
      local note_column = line:note_column(1) -- Assuming first note column

      -- Update volume only if there's already a note
      if note_column.note_value ~= 121 then  -- 121 = empty note
        note_column.volume_value = volume_value
        print("Updated volume to " .. volume_value .. " for step " .. step .. " in track " .. track_index .. " at tick " .. tick)
      end
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Function to update a specific step with a specific note value or chord
local function update_step_note_in_pattern(row_index, step, note_value)
  print("update_step_note_in_pattern called: row=" .. row_index .. ", step=" .. step .. ", note=" .. (note_value or "nil"))
  
  local data = sequencer_data[row_index]
  if not data then
    print("ERROR: No sequencer data for row " .. row_index)
    return
  end
  
  if data.instrument then
    local instrument_index = data.instrument - 1  -- Zero-based index for pattern
    local track_index = row_index + 1  -- Skip the group track at index 1

    -- Get the current pattern
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    
    print("Writing to track " .. track_index .. ", pattern " .. current_pattern_index .. ", instrument " .. instrument_index)
    
    -- Check if track exists
    if track_index > #song.tracks then
      print("ERROR: Track " .. track_index .. " doesn't exist (only " .. #song.tracks .. " tracks available)")
      return
    end
    
    -- Check if track supports note columns
    local track = song.tracks[track_index]
    if track.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
      print("ERROR: Track " .. track_index .. " is not a sequencer track (type: " .. track.type .. ")")
      return
    end
    
    if track.max_note_columns == 0 then
      print("ERROR: Track " .. track_index .. " has no note columns available")
      return
    end

    -- Calculate the line index based on the step and loop every 16 ticks
    for tick = step, song.patterns[current_pattern_index].number_of_lines, num_steps do
      local line_index = (tick - 1) % song.patterns[current_pattern_index].number_of_lines + 1

      -- Access the note column in the specified track and line
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)
      
      -- Clear existing notes first
      for i = 1, 12 do  -- Clear up to 12 note columns
        local note_column = line:note_column(i)
        if note_column then
          note_column.note_value = 121  -- Empty note
          note_column.instrument_value = 255
          note_column.volume_value = 255
        end
      end
      
      -- Generate notes (single note or chord)
      local notes_to_add = {}
      if data.is_chord_track and data.chord_type ~= "None" then
        notes_to_add = generate_chord_notes(note_value, data.chord_type)
      else
        notes_to_add = {note_value}
      end
      
      -- Add notes to pattern
      for i, note in ipairs(notes_to_add) do
        if i <= 12 then  -- Renoise supports up to 12 note columns
          local note_column = line:note_column(i)
          if note_column then
            note_column.note_value = note
            note_column.instrument_value = instrument_index
            note_column.volume_value = 128 -- Max volume (0-128 scale)
          end
        end
      end
      
      local chord_info = data.is_chord_track and " (" .. data.chord_type .. " chord)" or ""
      print("Added notes " .. table.concat(notes_to_add, ", ") .. chord_info .. " on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at tick " .. tick)
    end
  else
    print("ERROR: No instrument set for row " .. row_index)
  end
end

-- Function to add or remove a note in the pattern for a specific row
local function update_note_in_pattern(row_index, step, add_note)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument - 1  -- Zero-based index for pattern
    local track_index = row_index
    local note_value = data.note_value or 48 -- Use dynamic note value or default to C3

    -- Get the current pattern
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index

    -- Calculate the line index based on the step and loop every 16 ticks
    for tick = step, song.patterns[current_pattern_index].number_of_lines, num_steps do
      local line_index = (tick - 1) % song.patterns[current_pattern_index].number_of_lines + 1

      -- Access the note column in the specified track and line
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)
      local note_column = line:note_column(1) -- Assuming first note column

      if add_note then
        -- Add the note
        note_column.note_value = note_value
        note_column.instrument_value = instrument_index
        note_column.volume_value = 128 -- Max volume (0-128 scale)
        print("Added note " .. note_value .. " on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at tick " .. tick)
      else
        -- Remove the note
        note_column.note_value = 121 -- 121 represents an empty note
        note_column.instrument_value = 255 -- 255 represents no instrument
        note_column.volume_value = 255 -- 255 represents no volume change
        print("Removed note in track " .. track_index .. " at tick " .. tick)
      end
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Function to loop through all sequencer rows and add/remove notes
local function write_sequencer_to_pattern()
  for row_index, data in ipairs(sequencer_data) do
    if data.instrument then
      -- Loop through each step in the row
      for step_index, is_active in ipairs(data.steps) do
        if is_active then
          -- Add notes for active steps at intervals of num_steps (16, 32, etc.)
          update_note_in_pattern(row_index, step_index, true)
        else
          -- Optionally, remove notes for inactive steps if needed
          update_note_in_pattern(row_index, step_index, false)
        end
      end
    end
  end
end


-- Create a shared variable to store the delay value
local delay_value = 0

-- Function to update the note's delay value
local function update_note_delay_value(value)
  local song = renoise.song()
  local track_index = song.selected_track_index
  local line_index = song.selected_line_index
  
  -- Apply the delay value to the current note in the selected track
  local note_column = song:pattern(song.selected_pattern_index)
                         :track(track_index)
                         :line(line_index)
                         :note_column(1)  -- Assuming 1st note column
  
  -- Set the delay value for the note
  note_column.delay_value = value
  print("Set note delay to " .. note_column.delay_value)
end


-- Function to update the track's delay value
local function update_delay_value(value)
  local song = renoise.song()
  local track_index = song.selected_track_index
  
  -- Set the track delay for the specified track
  song.tracks[track_index].output_delay = value
  print("Set track delay to " .. value, track_index)
end


local function update_note_delay_value(value, target_track_index)
  local song = renoise.song()
  local track_index = target_track_index or song.selected_track_index
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  -- Convert value from 0 to 100 range to 0x00 to 0xFF hex range
  -- 0 maps to 0x00 (no delay), 100 maps to 0xFF (maximum delay)
  local delay_hex_value = math.floor((value / 100) * 255)
  delay_hex_value = math.max(0, math.min(255, delay_hex_value)) -- Clamp to 0-255 range
  
  -- Enable delay column on the track
  local track = song:track(track_index)
  track.delay_column_visible = true
  
  -- Enable delay effect on the track if not already enabled
  --local delay_device = nil
  
  -- Check if delay device already exists
  -- for _, device in ipairs(track.devices) do
  --   if device.name == "Delay" then
  --     delay_device = device
  --     break
  --   end
  -- end
  
  -- -- If no delay device found, add one
  -- if not delay_device then
  --   delay_device = track:insert_device_at("Audio/Effects/Native/Delay", 2)
  --   print("Added delay device to track " .. track_index)
  -- end
  
  -- Apply delay value to all notes in the pattern for this track
  local pattern_track = pattern:track(track_index)
  for line_index = 1, pattern.number_of_lines do
    local line = pattern_track:line(line_index)
    local note_column = line:note_column(1)
    
    -- Only update delay for lines that have notes
    if note_column.note_value ~= 121 then  -- 121 = empty note
      note_column.delay_value = delay_hex_value
    end
  end
  
  print("Set note delay to " .. delay_hex_value .. " (hex: " .. string.format("%02X", delay_hex_value) .. ") for all notes in track " .. track_index)
end


-- Function to clear all notes from pattern and sequencer
local function clear_pattern_and_sequencer()
  -- Clear all notes in the pattern
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  -- Loop through all tracks and lines to clear notes
  for track_index = 1, #song.tracks do
    local pattern_track = pattern:track(track_index)
    for line_index = 1, pattern.number_of_lines do
      local line = pattern_track:line(line_index)
      line:clear()  -- Clear the entire line (notes, effects, etc.)
    end
  end
  
  -- Clear sequencer data and UI checkboxes
  for row_index, data in ipairs(sequencer_data) do
    for step_index = 1, #data.steps do
      -- Clear the data model
      sequencer_data[row_index].steps[step_index] = false
      
      -- Clear the UI checkbox
      local checkbox_id = "checkbox_" .. tostring(row_index) .. "_" .. tostring(step_index)
      if vb.views[checkbox_id] then
        vb.views[checkbox_id].value = false
      end
    end
  end
  
  print("Cleared all notes from pattern and sequencer")
end


-- Create a row for the sequencer
local function create_step_row(row_index, steps)
  -- Use actual steps parameter instead of creating 64 and hiding
  local actual_steps = math.min(steps, num_steps)
  local row = vb:horizontal_aligner{
    
      vb:rotary{
        id = "track_delay_rotary_" .. tostring(row_index),  -- Unique ID for track delay rotary
        min = -100,  -- Minimum delay value
        max = 100,   -- Maximum delay value
        value = 0,   -- Initialize with 0
        width = cellSize,  -- Set width of the rotary control
        notifier = function(value)
          -- Update the track delay
          update_delay_value(value)
        end
      },
      vb:rotary{
        id = "note_rotary_" .. tostring(row_index),  -- Unique ID for note rotary
        min = 0,     -- 0% (C2)
        max = 100,   -- 100% (C4) 
        value = 50,  -- 50% (C3 default)
        width = cellSize,  -- Set width of the rotary control
        notifier = function(value)
          -- Map percentage to constrained note using global range/scale
          local base_note_value = sequencer_data[row_index].base_note_value
          local new_note_value = percentage_to_note(value, base_note_value)
          
          -- Update the rotary to reflect the constrained note value
          local constrained_percentage = note_to_percentage(new_note_value, base_note_value)
          local track_rotary_id = "note_rotary_" .. tostring(row_index)
          if math.abs(constrained_percentage - value) > 0.1 and vb.views[track_rotary_id] then
            vb.views[track_rotary_id].value = constrained_percentage
          end
          
          -- Calculate transposition offset from base note
          local transposition = new_note_value - base_note_value
          
          -- Update the note value for this row
          sequencer_data[row_index].note_value = new_note_value
          
          -- Update all step notes by applying the same transposition
          if sequencer_data[row_index].step_notes then
            for step_index, original_step_note in pairs(sequencer_data[row_index].step_notes) do
              -- Calculate what this step note should be relative to the base
              local step_offset = original_step_note - base_note_value
              local new_step_note = base_note_value + transposition + step_offset
              
              -- Constrain to scale
              new_step_note = snap_to_scale(new_step_note, select(1, compute_note_range(base_note_value)), select(2, compute_note_range(base_note_value)))
              
              -- Update step note data
              sequencer_data[row_index].step_notes[step_index] = new_step_note
              
              -- Update the step note rotary UI
              local step_rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step_index)
              if vb.views[step_rotary_id] then
                vb.views[step_rotary_id].value = note_to_percentage(new_step_note, base_note_value)
              end
            end
          end
          
          -- Update all active steps in the pattern with their new constrained values
          for s = 1, num_steps do
            if sequencer_data[row_index].steps[s] then
              local note_to_use
              if sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] then
                -- Use constrained step-specific note
                note_to_use = sequencer_data[row_index].step_notes[s]
              else
                -- Use new track note
                note_to_use = new_note_value
              end
              update_step_note_in_pattern(row_index, s, note_to_use)
            end
          end
          
          print("Updated track " .. row_index .. " note to " .. new_note_value .. " (constrained to scale)")
        end
      },
      
      -- Chord track toggle
      vb:button{
        id = "chord_toggle_" .. tostring(row_index),
        text = "C",
        width = cellSize,
        height = cellSize,
        color = {80, 80, 80},  -- Gray when not chord track
        notifier = function()
          toggle_chord_track(row_index)
        end
      },
      
      -- Chord selection dropdown
      vb:popup{
        id = "chord_popup_" .. tostring(row_index),
        width = cellSizeLg,
        height = cellSize,
        items = get_available_chords(),
        value = 1, -- Default to "None"
        active = false, -- Initially disabled
        notifier = function(index)
          local chord_items = vb.views["chord_popup_" .. tostring(row_index)].items
          sequencer_data[row_index].chord_type = chord_items[index]
          print("Selected chord " .. chord_items[index] .. " for row " .. row_index)
        end
      },
      
      vb:rotary{
        id = "note_delay_rotary_" .. tostring(row_index),  -- Unique ID for note delay rotary
        min = 0,     -- Minimum note delay value
        max = 255,   -- Maximum note delay value (Renoise uses 0-255 for note delay)
        value = 0,   -- Initialize with 0
        width = cellSize,  -- Set width of the rotary control
        notifier = function(value)
          -- Update the note delay for the specific row
          update_note_delay_value(value, row_index)
        end
      },
      
      -- OLD CODE (commented out) - valuebox and minislider implementation
      --[[
      vb:valuebox{
        id = "delay_valuebox_" .. tostring(row_index),  -- Unique ID for the numeric input (valuebox)
        min = -100,  -- Minimum delay value
        max = 100,   -- Maximum delay value
        value = 0,   -- Initialize with 0
        width = 50,  -- Set width of the valuebox input
        notifier = function(value)
          -- Update the delay value and clamp between -100 and 100
          delay_value = math.min(100, math.max(-100, math.floor(value)))
          
          -- Update both the slider and the track delay
          vb.views["minislider_" .. tostring(row_index)].value = delay_value
          update_delay_value(delay_value)
        end
      },
      
      vb:minislider{
        id = "minislider_" .. tostring(row_index),  -- Unique ID for the minislider
        min = -100,  -- Minimum delay value
        max = 100,   -- Maximum delay value
        value = 0,   -- Start from the middle
        notifier = function(value)
          -- Update the valuebox when the slider changes
          vb.views["delay_valuebox_" .. tostring(row_index)].value = value
          update_delay_value(value)
        end
      },
      --]]
      
      vb:popup{
        id = "instrument_popup_" .. tostring(row_index),
        width = cellSizeLg,
        height = cellSize,
        items = get_instrument_names(),
        notifier = function(index)
          sequencer_data[row_index].instrument = index
          print("Selected instrument " .. index .. " (0-based: " .. (index-1) .. ") for row " .. row_index)
          
          -- Update all currently checked steps in this row with the new instrument
          local song = renoise.song()
          local current_pattern_index = song.selected_pattern_index
          local pattern = song:pattern(current_pattern_index)
          local pattern_track = pattern:track(row_index)
          
          -- Go through all steps in this row
          for s = 1, num_steps do
            if sequencer_data[row_index].steps[s] then  -- If step checkbox is checked
              -- Update all occurrences of this step in the pattern
              for tick = s, pattern.number_of_lines, num_steps do
                local line_index = (tick - 1) % pattern.number_of_lines + 1
                local line = pattern_track:line(line_index)
                local note_column = line:note_column(1)
                
                -- If there's a note on this line, update its instrument
                if note_column.note_value ~= 121 then  -- 121 = empty note
                  note_column.instrument_value = index - 1  -- Zero-based for pattern
                  print("Updated step " .. s .. " at line " .. line_index .. " to instrument " .. index)
                end
              end
            end
          end
        end
      },
      
      vb:button{
        text = "?",
        width = cellSize,
        height = cellSize,
        notifier = function()
          save_row_as_phrase(row_index)
        end
      },
      
      -- Preview button for triggering sample/chord
      vb:button{
        text = "►",
        width = cellSize,
        height = cellSize,
        notifier = function()
          trigger_sample(row_index)
        end
      },
      
      -- Visibility toggle buttons
      vb:button{
        id = "note_toggle_" .. tostring(row_index),
        text = "N",
        width = cellSize,
        height = cellSize,
        color = {100, 255, 100},  -- Green when visible
        notifier = function()
          toggle_note_row_visibility(row_index)
        end
      },
      
      vb:button{
        id = "volume_toggle_" .. tostring(row_index),
        text = "V",
        width = cellSize,
        height = cellSize,
        color = {100, 255, 100},  -- Green when visible
        notifier = function()
          toggle_volume_row_visibility(row_index)
        end
      },
  }
  
  -- Add MIDI mappings for track controls
  renoise.tool():add_midi_mapping{
    name = "Step Sequencer: Row " .. row_index .. " Track Delay",
    invoke = function(message)
      if (message:is_abs_value()) then
        -- Convert MIDI CC value (0-127) to delay range (-100 to 100)
        local delay_value = ((message.int_value / 127) * 200) - 100
        local control_id = "track_delay_rotary_" .. tostring(row_index)
        if vb.views[control_id] then
          vb.views[control_id].value = delay_value
        end
      end
    end
  }
  
  renoise.tool():add_midi_mapping{
    name = "Step Sequencer: Row " .. row_index .. " Track Note",
    invoke = function(message)
      if (message:is_abs_value()) then
        -- Convert MIDI CC value (0-127) to percentage (0-100)
        local percentage = (message.int_value / 127) * 100
        local control_id = "note_rotary_" .. tostring(row_index)
        if vb.views[control_id] then
          vb.views[control_id].value = percentage
        end
      end
    end
  }
  
  renoise.tool():add_midi_mapping{
    name = "Step Sequencer: Row " .. row_index .. " Note Delay",
    invoke = function(message)
      if (message:is_abs_value()) then
        -- Convert MIDI CC value (0-127) to delay range (0-255)
        local delay_value = (message.int_value / 127) * 255
        local control_id = "note_delay_rotary_" .. tostring(row_index)
        if vb.views[control_id] then
          vb.views[control_id].value = delay_value
        end
      end
    end
  }
  
  -- Add checkboxes for each step (only create what we need)
  for s = 1, actual_steps do
    row:add_child(vb:checkbox{
      id = "checkbox_" .. tostring(row_index) .. "_" .. tostring(s),
      value = false,
      width = cellSize,
      height = cellSize,
      notifier = function(new_value)
        local old_value = sequencer_data[row_index].steps[s]
        sequencer_data[row_index].steps[s] = new_value
        
        print("Checkbox changed:")
        print("  Row: " .. row_index)
        print("  Step: " .. s)
        print("  Old value: " .. tostring(old_value))
        print("  New value: " .. tostring(new_value))
        
        -- Use step-specific note if available, otherwise use track note
        if new_value then
          local note_to_use = sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] or sequencer_data[row_index].note_value
          print("  Note to use: " .. (note_to_use or "nil"))
          print("  Instrument: " .. (sequencer_data[row_index].instrument or "nil"))
          print("  Is chord track: " .. tostring(sequencer_data[row_index].is_chord_track))
          print("  Chord type: " .. (sequencer_data[row_index].chord_type or "nil"))
          update_step_note_in_pattern(row_index, s, note_to_use)
        else
          -- Remove note
          print("  Removing note from step")
          update_note_in_pattern(row_index, s, false)
        end
      end
    })
  end
  
  return row
end

-- Create a note row with rotary dials for each step
local function create_note_row(row_index, steps)
  -- Use actual steps parameter instead of creating 64 and hiding
  local actual_steps = math.min(steps, num_steps)
  local note_row = vb:horizontal_aligner{
    -- Add spacing to align with the step row controls
    vb:text{width = cellSize, text = ""},  -- Track delay space
    vb:text{width = cellSize, text = ""},  -- Note rotary space  
    vb:text{width = cellSize, text = ""},  -- Note delay space
    vb:text{width = cellSizeLg, height = cellSize, text = "Note"}, -- Label for note row
    vb:text{width = cellSize, text = ""},  -- Save button space
    vb:text{width = cellSize, text = ""},  -- Preview button space
    vb:text{width = cellSize, text = ""},  -- Note toggle space
    vb:text{width = cellSize, text = ""},  -- Volume toggle space
    vb:text{width = cellSize, text = ""},  -- Chord toggle space
    vb:text{width = cellSizeLg, text = ""},  -- Chord selection space
  }
  
  -- Initialize visibility state
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = true, volume_visible = true}
  end
  
  -- Add rotary dials for each step (only create what we need)
  for s = 1, actual_steps do
    local rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    note_row:add_child(vb:rotary{
      id = rotary_id,
      min = 0,     -- 0% (C2)
      max = 100,   -- 100% (C4) 
      value = 50,  -- 50% (C3 default)
      width = cellSize,  -- Same width as checkboxes
      notifier = function(value)
        -- Convert percentage to constrained note using global range/scale
        local base_note_value = sequencer_data[row_index].base_note_value or 48
        local note_value = percentage_to_note(value, base_note_value)
        
        -- Store per-step note values
        if not sequencer_data[row_index].step_notes then
          sequencer_data[row_index].step_notes = {}
        end
        sequencer_data[row_index].step_notes[s] = note_value
        
        -- Update the rotary to reflect the constrained note value
        local constrained_percentage = note_to_percentage(note_value, base_note_value)
        if math.abs(constrained_percentage - value) > 0.1 then
          vb.views[rotary_id].value = constrained_percentage
        end
        
        -- Update pattern with specific note for this step (only if step is active)
        if sequencer_data[row_index].steps[s] then
          update_step_note_in_pattern(row_index, s, note_value)
        end
        
        print("Set step " .. s .. " note to " .. note_value .. " for row " .. row_index)
      end
    })
    
    -- Add MIDI mapping for this rotary  
    local mapping_name = "Step Sequencer: Row " .. row_index .. " Step " .. s .. " Note"
    renoise.tool():add_midi_mapping{
      name = mapping_name,
      invoke = function(message)
        if (message:is_abs_value()) then
          -- Convert MIDI CC value (0-127) to rotary percentage (0-100)
          local percentage = (message.int_value / 127) * 100
          if vb.views[rotary_id] then
            vb.views[rotary_id].value = percentage
          end
        end
      end
    }
  end
  
  -- Store reference to the note row and set initial visibility
  track_note_rows[row_index] = note_row
  note_row.visible = track_visibility[row_index].note_visible
  
  return note_row
end

-- Create a volume row with rotary dials for each step
local function create_volume_row(row_index, steps)
  -- Use actual steps parameter instead of creating 64 and hiding
  local actual_steps = math.min(steps, num_steps)
  local volume_row = vb:horizontal_aligner{
    -- Add spacing to align with the step row controls
    vb:text{width = cellSize, text = ""},  -- Track delay space
    vb:text{width = cellSize, text = ""},  -- Note rotary space  
    vb:text{width = cellSize, text = ""},  -- Note delay space
    vb:text{width = cellSizeLg, height = cellSize, text = "Volume"}, -- Label for volume row
    vb:text{width = cellSize, text = ""},  -- Save button space
    vb:text{width = cellSize, text = ""},  -- Preview button space
    vb:text{width = cellSize, text = ""},  -- Note toggle space
    vb:text{width = cellSize, text = ""},  -- Volume toggle space
    vb:text{width = cellSize, text = ""},  -- Chord toggle space
    vb:text{width = cellSizeLg, text = ""},  -- Chord selection space
  }
  
  -- Initialize visibility state
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = true, volume_visible = true}
  end
  
  -- Add rotary dials for each step volume (only create what we need)
  for s = 1, actual_steps do
    local rotary_id = "step_volume_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    volume_row:add_child(vb:rotary{
      id = rotary_id,
      min = 0,     -- 0% (silent)
      max = 100,   -- 100% (full volume) 
      value = 100, -- 100% (full volume default)
      width = cellSize,  -- Same width as checkboxes
      notifier = function(value)
        -- Convert percentage to MIDI volume value (0-127 range)
        local volume_value = math.floor((value / 100) * 127)
        
        -- Store per-step volume values
        if not sequencer_data[row_index].step_volumes then
          sequencer_data[row_index].step_volumes = {}
        end
        sequencer_data[row_index].step_volumes[s] = volume_value
        
        -- Update pattern with specific volume for this step (only if step is active)
        if sequencer_data[row_index].steps[s] then
          update_step_volume_in_pattern(row_index, s, volume_value)
        end
        
        print("Set step " .. s .. " volume to " .. volume_value .. " for row " .. row_index)
      end
    })
    
    -- Add MIDI mapping for this volume rotary  
    local mapping_name = "Step Sequencer: Row " .. row_index .. " Step " .. s .. " Volume"
    renoise.tool():add_midi_mapping{
      name = mapping_name,
      invoke = function(message)
        if (message:is_abs_value()) then
          -- Convert MIDI CC value (0-127) to rotary percentage (0-100)
          local percentage = (message.int_value / 127) * 100
          if vb.views[rotary_id] then
            vb.views[rotary_id].value = percentage
          end
        end
      end
    }
  end
  
  -- Store reference to the volume row and set initial visibility
  track_volume_rows[row_index] = volume_row
  volume_row.visible = track_visibility[row_index].volume_visible
  
  return volume_row
end

-- Get names of all instruments
function get_instrument_names()
  local names = {}
  for i, instrument in ipairs(renoise.song().instruments) do
    table.insert(names, i .. ": " .. instrument.name)
  end
  return names
end

-- Refresh all instrument dropdowns
local function refresh_instrument_dropdowns()
  local updated_names = get_instrument_names()
  for r = 1, #sequencer_data do
    local popup_id = "instrument_popup_" .. tostring(r)
    if vb.views[popup_id] then
      local current_value = vb.views[popup_id].value
      vb.views[popup_id].items = updated_names
      -- Preserve selection if still valid
      if current_value <= #updated_names then
        vb.views[popup_id].value = current_value
      else
        vb.views[popup_id].value = 1
        -- Update sequencer data if instrument selection was reset
        if sequencer_data[r] then
          sequencer_data[r].instrument = 1
        end
      end
    end
  end
  print("Refreshed instrument dropdowns - found " .. #updated_names .. " instruments")
end



-- Update step indicators
local function update_step_indicators()
  print("Running step indicators. Count: " .. #step_indicators)
  local song = renoise.song()
  local current_line = song.transport.playback_pos.line
  
  -- Calculate the current sequencer step (1 to num_steps) with looping
  local current_sequencer_step = ((current_line - 1) % num_steps) + 1
  
  print("playing line t: ", current_line, " sequencer step: ", current_sequencer_step)
  
  for s, indicator in ipairs(step_indicators) do
    if s == current_sequencer_step then
      indicator.color = ACTIVE_COLOR
    elseif s % 4 == 1 then
      indicator.color = BLOCK_START_COLOR
    else
      indicator.color = INACTIVE_COLOR
    end
  end
end

-- Function to clear notes outside the new step range
local function clear_notes_outside_range(new_steps, current_steps)
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  -- Loop through all tracks and clear notes outside the new step range
  for track_index = 1, #song.tracks do
    local pattern_track = pattern:track(track_index)
    
    -- Clear notes that are outside the new step range
    for line_index = 1, pattern.number_of_lines do
      -- Calculate which step this line represents in the current step pattern
      local step_in_current_pattern = ((line_index - 1) % current_steps) + 1
      
      -- If this step is beyond the new step count, clear it
      if step_in_current_pattern > new_steps then
        local line = pattern_track:line(line_index)
        local note_column = line:note_column(1)
        
        -- Clear the note if it exists
        if note_column.note_value ~= 121 then  -- 121 = empty note
          note_column.note_value = 121
          note_column.instrument_value = 255
          note_column.volume_value = 255
        end
      end
    end
  end
  
  print("Cleared notes outside of " .. new_steps .. " step range")
end

-- Placeholder - update_step_count function will be moved inside show_sequencer_dialog



-- observer for indicator
local function setup_line_change_notifier()
  renoise.tool().app_new_document_observable:add_notifier(function()
    local song = renoise.song()
    song.transport.playback_pos_observable:add_notifier(function()
      if song.transport.playing then
        update_step_indicators()
      end
    end)
  end)
end


----------------------------------------------------------PLAYBACK


-- Trigger notes for active steps
local function trigger_notes()
  for row, data in ipairs(sequencer_data) do
    if data.steps[current_step] then
      local instrument = renoise.song().instruments[data.instrument]
      local track = renoise.song().tracks[row]
      local note = renoise.song().transport.edit_step
      instrument:trigger_note(note, 100, track.name)
    end
  end
   -- update_step_indicators()
end


-- Handle playback
local function handle_playback()
  if is_playing then
    trigger_notes()
    current_step = current_step % num_steps + 1
    renoise.tool().app:defer(handle_playback)
  end
end




----------------------------------------------------------MAIN
-- Dialog management
local dialog = nil

-- Create the main dialog window
local function show_sequencer_dialog()
  -- Close existing dialog if open
  if dialog and dialog.visible then
    dialog:close()
  end
  
  -- Create new ViewBuilder instance to avoid ID conflicts
  vb = renoise.ViewBuilder()
  
  -- Clear UI references but preserve data
  step_grid_view = nil
  step_indicators = {}
  step_indicators_row = nil
  track_note_rows = {}
  track_volume_rows = {}
  -- Note: We keep sequencer_data and track_visibility to preserve user data
  
  step_grid_view = vb:column{
    spacing = 0  -- Reduce spacing between rows
  }
  -- Create step indicators with maximum possible steps (64) so we can hide/show them
  step_indicators_row = create_step_indicators(64)  -- Create maximum, hide unused ones later
  
  -- Initially hide step indicators beyond current num_steps
  for s = 1, #step_indicators do
    if step_indicators[s] then
      step_indicators[s].visible = (s <= num_steps)
    end
  end

  setup_line_change_notifier()

  -- Initialize step indicators when the tool is loaded
  update_step_indicators()
  
  
  -- Find the index in num_steps_options that matches patternLength
  local function find_steps_index(pattern_length)
    for i, option in ipairs(num_steps_options) do
      if tonumber(option) == pattern_length then
        return i
      end
    end
    return 1  -- Default to first option if no match found
  end

  -- Declare dialog_content variable so it's accessible to update_step_count
  local dialog_content
  
  -- Update the number of steps in all rows (moved inside dialog function for proper scope)
  local function update_step_count(new_steps)
    if step_grid_view and dialog_content then
      -- Clear notes outside of the new step range in the pattern
      clear_notes_outside_range(new_steps, num_steps)
      
      -- Update global step count
      num_steps = new_steps
      
      -- Update step indicators - show/hide existing indicators
      for s = 1, #step_indicators do
        if step_indicators[s] then
          step_indicators[s].visible = (s <= new_steps)
        end
      end
      
      -- If we need more indicators than we have, we'll need to restart
      if new_steps > #step_indicators then
        print("Step count increased beyond current capacity. Please restart the tool.")
        return
      end
      
      -- Update sequencer data for existing rows to handle new step count
      for r = 1, num_rows do
        if sequencer_data[r] then
          -- Extend or truncate steps array
          local old_steps = sequencer_data[r].steps
          local old_step_notes = sequencer_data[r].step_notes or {}
          local old_step_volumes = sequencer_data[r].step_volumes or {}
          
          sequencer_data[r].steps = {}
          sequencer_data[r].step_notes = {}
          sequencer_data[r].step_volumes = {}
          
          -- Copy existing step data up to new_steps limit
          for s = 1, new_steps do
            sequencer_data[r].steps[s] = old_steps[s] or false
            if old_step_notes[s] then
              sequencer_data[r].step_notes[s] = old_step_notes[s]
            end
            if old_step_volumes[s] then
              sequencer_data[r].step_volumes[s] = old_step_volumes[s]
            end
          end
        end
      end
      
      -- Recreate the entire UI to avoid width calculation issues
      -- Clear existing rows
      step_grid_view:clear()
      
      -- Recreate all rows with new step count
      for r = 1, #sequencer_data do
        if sequencer_data[r] then
          step_grid_view:add_child(create_step_row(r, new_steps))
          step_grid_view:add_child(create_note_row(r, new_steps))
          step_grid_view:add_child(create_volume_row(r, new_steps))
        end
      end
      
      print("Updated sequencer to " .. new_steps .. " steps")
      apply_global_note_constraints()
    end
  end

  local controls_row = vb:row{
    vb:text{ text = "Steps:" },
    vb:popup{
      id = "steps_dropdown",
      items = num_steps_options,
      value = find_steps_index(patternLength), -- Set the index that matches pattern length
      notifier = function(index)
        num_steps = tonumber(vb.views.steps_dropdown.items[index])
        update_step_count(num_steps) -- this handles both sequencer rows and step indicators
      end
   
    },
    vb:text{ text = "Oct Range:" },
    vb:popup{
      id = "octave_range_dropdown",
      items = {"1","2","3","4"},
      value = math.max(1, math.min(4, global_octave_range)),
      notifier = function(index)
        global_octave_range = index
        apply_global_note_constraints()
      end
    },
    vb:text{ text = "Scale:" },
    vb:popup{
      id = "scale_mode_dropdown",
      items = get_available_scales(),
      value = 1,
      notifier = function(index)
        local items = vb.views.scale_mode_dropdown.items
        global_scale_mode = items[index]
        apply_global_note_constraints()
      end
    },
    vb:text{ text = "Key:" },
    vb:popup{
      id = "scale_key_dropdown",
      items = KEY_NAMES,
      value = global_scale_key,
      notifier = function(index)
        global_scale_key = index
        apply_global_note_constraints()
      end
    },
   vb:button{
      text = "Add Row",
      notifier = function()
        local song = renoise.song()
        
        -- Find the Sequencer group track
        local sequencer_group_index = nil
        for i, track in ipairs(song.tracks) do
          if track.type == renoise.Track.TRACK_TYPE_GROUP and track.name == "Sequencer" then
            sequencer_group_index = i
            break
          end
        end
        
        if sequencer_group_index then
          -- Create a new track after the existing sequencer tracks
          local new_track_index = sequencer_group_index + #sequencer_data + 1
          song:insert_track_at(new_track_index)
          
          -- Name the new track
          song.tracks[new_track_index].name = "Seq " .. (#sequencer_data + 1)
          
          print("Added new track " .. new_track_index .. " to Sequencer group at index " .. sequencer_group_index)
        else
          print("Sequencer group not found!")
        end
        
        -- Update sequencer UI
        num_rows = num_rows + 1
        local new_row_index = #sequencer_data + 1
        -- Initialize data before creating controls so notifiers can access it
        sequencer_data[new_row_index] = {instrument = 1, note_value = 48, base_note_value = 48, steps = {}, step_notes = {}, step_volumes = {}, is_chord_track = false, chord_type = "None"}
        for s = 1, num_steps do
          sequencer_data[new_row_index].steps[s] = false
        end
        
        -- Initialize visibility data for new row
        track_visibility[new_row_index] = {note_visible = true, volume_visible = true}
        step_grid_view:add_child(create_step_row(new_row_index, num_steps))  -- Create only current steps
        step_grid_view:add_child(create_note_row(new_row_index, num_steps))  -- Create only current steps
        step_grid_view:add_child(create_volume_row(new_row_index, num_steps))  -- Create only current steps
        apply_global_note_constraints()
      end
    },
    vb:button{
      text = "Play/Stop",
      notifier = function()
        local song = renoise.song()
        local current_line = song.transport.playback_pos.line
        song.transport.playing = not song.transport.playing
        if not song.transport.playing then
        -- Reset indicators when stopping
        for _, indicator in ipairs(step_indicators) do
          indicator.color = INACTIVE_COLOR
          
        end
       end
      end
    },
              vb:button{
       text = "Clear",
       notifier = function()
         clear_pattern_and_sequencer()
       end
     },
     vb:button{
       text = "Refresh Instruments",
       notifier = function()
         refresh_instrument_dropdowns()
       end
     },
  }

  -- Setup default track group on first run
  setup_default_track_group()
  
  -- Initialize default sequencer rows if empty
  if #sequencer_data == 0 then
    for r = 1, num_rows do
      sequencer_data[r] = {instrument = 1, note_value = 48, base_note_value = 48, steps = {}, step_notes = {}, step_volumes = {}, is_chord_track = false, chord_type = "None"}
      for s = 1, num_steps do
        sequencer_data[r].steps[s] = false
      end
      -- Initialize visibility data
      track_visibility[r] = {note_visible = true, volume_visible = true}
      
      -- Create the rows
      step_grid_view:add_child(create_step_row(r, num_steps))
      step_grid_view:add_child(create_note_row(r, num_steps))
      step_grid_view:add_child(create_volume_row(r, num_steps))
    end
    apply_global_note_constraints()
  end

  dialog_content = vb:column{
    controls_row,
    step_indicators_row,
    step_grid_view
  }
  
  -- Calculate dialog width to match content  
  -- Base controls width: TD(24) + TN(24) + ND(24) + I(96) + ?(24) + ►(24) + N(24) + V(24) + C(24) + Chord(96) = 384
  -- Step controls width: num_steps * 24
  -- Total width with margins
  local base_controls_width = cellSize * 8 + cellSizeLg * 2  -- 384
  local steps_width = num_steps * cellSize
  local total_content_width = base_controls_width + steps_width
  local dialog_width = total_content_width + (dialog_margin * 2)

  --update_step_count(num_steps)

  -- Set up idle notifier to update step indicators
  renoise.tool().app_idle_observable:add_notifier(function()
    if renoise.song().transport.playing then
      --print(" song playing now: ")
      update_step_indicators()
    end
  end)

  -- Update indicators when playback starts or stops
  renoise.song().transport.playing_observable:add_notifier(function()
    update_step_indicators()
  end)

  dialog = renoise.app():show_custom_dialog("Step Sequencer", dialog_content)
end

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Step Sequencer",
  invoke = show_sequencer_dialog
}













































