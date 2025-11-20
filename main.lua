local vb = renoise.ViewBuilder()

local control_margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
local control_spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
local control_height = renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT
local control_mini_height = renoise.ViewBuilder.DEFAULT_MINI_CONTROL_HEIGHT
local dialog_margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
local dialog_spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
local button_height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT
local section_spacing = 16  -- Spacing between major sections (controls, indicators, grid)

local num_steps_options = {"8", "16", "32", "64"}
local pattern = 1  -- Default pattern index
local patternLength = 16  -- Default pattern length
local cellSize = 24
local cellSizeLg = cellSize * 4





-- Global musical constraints
local global_octave_range = 3 -- 1-4 octaves
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
          if row.step_states and row.step_states[s] then
            -- Only update play steps (state 1), not stop steps (state 2)
            if row.step_states[s] == 1 then
            update_step_note_in_pattern(r, s, new_n)
            end
          end
        end
      end

      -- For active steps without specific per-step notes, apply constrained track note
      if row.step_states then
        for s = 1, num_steps do
          -- Only update play steps (state 1), not stop steps (state 2)
          if row.step_states[s] and row.step_states[s] == 1 and (not row.step_notes or not row.step_notes[s]) then
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
num_rows = 1
current_step = 1
is_playing = false

-- Grid for storing the current sequencer
step_grid_view = nil
sequencer_data = {}
step_indicators = {}
step_indicators_row = nil
dialog = nil  -- Main dialog window

-- Forward declarations (defined later)
local show_sequencer_dialog
local update_mute_button_color
update_step_note_in_pattern = nil  -- Will be defined later
update_note_in_pattern = nil  -- Will be defined later
update_step_volume_in_pattern = nil  -- Will be defined later
get_track_index_for_row = nil  -- Will be defined later
rebuild_track_mapping = nil  -- Will be defined later

-- Observable notifier references
local instruments_notifier = nil

-- Track mapping: Maps sequencer row index to actual Renoise track index
track_mapping = {}  -- track_mapping[row_index] = actual_track_index

-- Track visibility data
track_visibility = {}  -- Stores show/hide state for note, volume, and delay rows per track
track_note_rows = {}   -- References to note row views for each track
track_volume_rows = {} -- References to volume row views for each track
track_delay_rows = {}  -- References to delay row views for each track

-- Toggle functions for row visibility
local function toggle_note_row_visibility(row_index)
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
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
    track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
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

local function toggle_delay_row_visibility(row_index)
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end
  
  local is_visible = track_visibility[row_index].delay_visible
  track_visibility[row_index].delay_visible = not is_visible
  
  if track_delay_rows[row_index] then
    track_delay_rows[row_index].visible = not is_visible
  end
  
  -- Update button color
  local toggle_id = "delay_toggle_" .. tostring(row_index)
  if vb.views[toggle_id] then
    vb.views[toggle_id].color = not is_visible and {100, 255, 100} or {80, 80, 80}
  end
  
  print("Delay row " .. row_index .. " visibility: " .. tostring(not is_visible))
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
  
  -- Update track note columns based on chord state
  local song = renoise.song()
  local track_index = get_track_index_for_row(row_index)  -- Get actual track index
  
  if track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      if not is_chord then
        -- Chord mode enabled - expand columns based on current chord type
        local chord_type = sequencer_data[row_index].chord_type or "None"
        local chord_intervals = CHORD_TYPES[chord_type]
        if chord_intervals and #chord_intervals > 0 then
          local num_notes = #chord_intervals
          track.visible_note_columns = math.max(1, math.min(12, num_notes))
          print("Expanded track " .. track_index .. " to " .. num_notes .. " note columns for chord mode")
        else
          track.visible_note_columns = 1
        end
        
        -- Update all active steps to show chord notes
        for s = 1, num_steps do
          if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] then
            local step_state = sequencer_data[row_index].step_states[s]
            
            if step_state == 1 then
              -- Only update play steps, not stop steps
              local note_to_use = sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] or sequencer_data[row_index].note_value
              update_step_note_in_pattern(row_index, s, note_to_use)
            elseif step_state == 2 then
              -- Stop state: clear note first, then set volume to 0
              update_note_in_pattern(row_index, s, false)
              update_step_volume_in_pattern(row_index, s, 0)
            end
          end
        end
        print("Updated all active steps to chord notes")
      else
        -- Chord mode disabled - return to single column
        track.visible_note_columns = 1
        
        -- Update all active steps to single notes
        for s = 1, num_steps do
          if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] then
            local step_state = sequencer_data[row_index].step_states[s]
            
            if step_state == 1 then
              -- Only update play steps, not stop steps
              local note_to_use = sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] or sequencer_data[row_index].note_value
              update_step_note_in_pattern(row_index, s, note_to_use)
            elseif step_state == 2 then
              -- Stop state: clear note first, then set volume to 0
              update_note_in_pattern(row_index, s, false)
              update_step_volume_in_pattern(row_index, s, 0)
            end
          end
        end
        print("Collapsed track " .. track_index .. " to 1 note column")
      end
    end
  end
  
  print("Chord track " .. row_index .. " enabled: " .. tostring(not is_chord))
end

-- Color definitions for step indicators (lighter to differentiate from sequence steps)
local INACTIVE_COLOR = {130, 130, 130}  -- Light gray
local ACTIVE_COLOR = {255, 255, 100}  -- Light yellow for active step
local BLOCK_START_COLOR = {150, 150, 150}  -- Lighter gray for block start

-- Function to clear a sequencer row (remove notes from pattern and reset sequencer data)
local function remove_sequencer_row(row_index)
  if not sequencer_data[row_index] then
    print("ERROR: Row " .. row_index .. " doesn't exist")
    return
  end
  
  local song = renoise.song()
  local track_index = get_track_index_for_row(row_index)
  
  -- Clear all notes from the pattern for this row
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  if track_index and track_index <= #song.tracks then
    local pattern_track = pattern:track(track_index)
    
    -- Clear all lines in this track
    for line_index = 1, pattern.number_of_lines do
      local line = pattern_track:line(line_index)
      line:clear()  -- Clear notes, effects, everything
    end
    
    print("Cleared all pattern notes for row " .. row_index .. " (track " .. track_index .. ")")
  end
  
  -- Reset the sequencer data for this row
  sequencer_data[row_index].step_states = {}
  sequencer_data[row_index].step_notes = {}
  sequencer_data[row_index].step_volumes = {}
  for s = 1, num_steps do
    sequencer_data[row_index].step_states[s] = 0  -- Reset to Off
  end
  
  -- Clear all step buttons in the UI
  for s = 1, num_steps do
    local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
    if vb.views[button_id] then
      vb.views[button_id].text = " "
      vb.views[button_id].color = {80, 80, 80}  -- Gray for Off
    end
  end
  
  print("Cleared row " .. row_index .. " (pattern and steps reset)")
end

-- Function to remove row AND delete the associated track from Renoise
local function remove_sequencer_row_and_track(row_index)
  if not sequencer_data[row_index] then
    print("ERROR: Row " .. row_index .. " doesn't exist")
    return
  end
  
  local song = renoise.song()
  local track_index = get_track_index_for_row(row_index)
  
  -- Delete the actual track from Renoise first
  if track_index and track_index <= #song.tracks then
    local track = song.tracks[track_index]
    
    -- Safety check: only delete sequencer tracks
    if track.name:match("^Sequencer_") then
      song:delete_track_at(track_index)
      print("Deleted track " .. track_index .. " (" .. track.name .. ") from Renoise")
    else
      print("WARNING: Track " .. track_index .. " is not a sequencer track, not deleting")
      return
    end
  end
  
  -- Remove from sequencer data arrays
  table.remove(sequencer_data, row_index)
  table.remove(track_visibility, row_index)
  
  -- Rebuild track mapping (shift all indices down after deleted row)
  track_mapping = {}
  for r = 1, #sequencer_data do
    -- Find corresponding track for this row
    local found = false
    for t = 1, #song.tracks do
      if song.tracks[t].name:match("^Sequencer_") then
        -- Count sequencer tracks to find the right one
        local seq_count = 0
        for tt = 1, t do
          if song.tracks[tt].name:match("^Sequencer_") then
            seq_count = seq_count + 1
          end
        end
        if seq_count == r then
          track_mapping[r] = t
          found = true
          break
        end
      end
    end
    if found then
      print("Mapped row " .. r .. " to track " .. track_mapping[r])
    end
  end
  
  -- Update num_rows
  num_rows = #sequencer_data
  print("Updated num_rows to " .. num_rows)
  
  -- Close and reopen dialog to refresh UI
  if dialog and dialog.visible then
    dialog:close()
    show_sequencer_dialog()
  end
end

-- Helper function to find the last sequencer track index (before send/master tracks)
local function find_last_sequencer_track_index()
  local song = renoise.song()
  local last_sequencer_index = 0
  
  -- First, check if there are any existing "Sequencer_" tracks
  local has_seq_tracks = false
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.name:match("^Sequencer_") then
      has_seq_tracks = true
      last_sequencer_index = i
    elseif track.type == renoise.Track.TRACK_TYPE_SEQUENCER or 
           track.type == renoise.Track.TRACK_TYPE_GROUP then
      -- Track other sequencer/group tracks only if we haven't found Sequencer tracks yet
      if not has_seq_tracks then
        last_sequencer_index = i
      end
    end
  end
  
  -- If no sequencer tracks found, use the currently selected track index
  if last_sequencer_index == 0 then
    last_sequencer_index = song.selected_track_index
  end
  
  return last_sequencer_index
end

-- Helper function to get the actual track index for a sequencer row
get_track_index_for_row = function(row_index)
  return track_mapping[row_index] or row_index
end

-- Helper function to rebuild the track mapping
rebuild_track_mapping = function()
  local song = renoise.song()
  track_mapping = {}
  
  local seq_track_count = 0
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.name:match("^Sequencer_") then
      seq_track_count = seq_track_count + 1
      track_mapping[seq_track_count] = i
      print("Mapped row " .. seq_track_count .. " to track " .. i .. " (" .. track.name .. ")")
    end
  end
  
  -- Clean up orphaned tracks (more sequencer tracks than data rows)
  if seq_track_count > #sequencer_data then
    print("WARNING: Found " .. seq_track_count .. " sequencer tracks but only " .. #sequencer_data .. " data rows")
    -- Delete orphaned tracks (from the end backwards to avoid index shifting)
    for i = #song.tracks, 1, -1 do
      local track = song.tracks[i]
      if track.name:match("^Sequencer_") then
        -- Check if this track has a corresponding data row
        local has_data = false
        for row_idx = 1, #sequencer_data do
          if track_mapping[row_idx] == i then
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
    
    -- Rebuild mapping after cleanup
    track_mapping = {}
    seq_track_count = 0
    for i = 1, #song.tracks do
      local track = song.tracks[i]
      if track.name:match("^Sequencer_") then
        seq_track_count = seq_track_count + 1
        track_mapping[seq_track_count] = i
        print("Re-mapped row " .. seq_track_count .. " to track " .. i .. " (" .. track.name .. ")")
      end
    end
  end
end

-- Load sequencer data from existing tracks in the pattern
local function load_sequencer_from_pattern()
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)
  
  print("=== Attempting to load sequencer from existing tracks ===")
  
  -- Find all sequencer tracks
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
  
  -- For each sequencer track, analyze the pattern and reconstruct data
  for row_idx, track_info in ipairs(sequencer_tracks) do
    local track_index = track_info.index
    local track = track_info.track
    local pattern_track = pattern:track(track_index)
    
    -- Initialize row data
    sequencer_data[row_idx] = {
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
    
    -- Analyze pattern lines to determine step states
    local found_notes = false
    for step = 1, num_steps do
      local line_index = step
      if line_index <= pattern.number_of_lines then
        local line = pattern_track:line(line_index)
        local note_col = line:note_column(1)
        
        if note_col.note_value < 121 then  -- Has a note
          sequencer_data[row_idx].step_states[step] = 1  -- Play
          sequencer_data[row_idx].step_notes[step] = note_col.note_value
          
          -- Get instrument
          if note_col.instrument_value < 255 then
            sequencer_data[row_idx].instrument = note_col.instrument_value + 1
          end
          
          -- Get volume
          if note_col.volume_value < 255 then
            sequencer_data[row_idx].step_volumes[step] = note_col.volume_value
          end
          
          -- Get delay
          if note_col.delay_value > 0 then
            sequencer_data[row_idx].step_delays[step] = note_col.delay_value
          end
          
          found_notes = true
          
          -- Update base note if this is first note found
          if sequencer_data[row_idx].note_value == 48 then
            sequencer_data[row_idx].note_value = note_col.note_value
            sequencer_data[row_idx].base_note_value = note_col.note_value
          end
        elseif note_col.volume_value == 0 then  -- Stop note
          sequencer_data[row_idx].step_states[step] = 2  -- Stop
        else
          sequencer_data[row_idx].step_states[step] = 0  -- Off
        end
      else
        sequencer_data[row_idx].step_states[step] = 0  -- Off
      end
    end
    
    -- Check if it's a chord track (multiple note columns used)
    if track.visible_note_columns > 1 then
      sequencer_data[row_idx].is_chord_track = true
    end
    
    -- Map track
    track_mapping[row_idx] = track_index
    track_visibility[row_idx] = {note_visible = false, volume_visible = false, delay_visible = false}
    
    print("Loaded row " .. row_idx .. " from track " .. track_index .. " (instrument: " .. sequencer_data[row_idx].instrument .. ")")
  end
  
  -- Update global num_rows
  num_rows = #sequencer_tracks
  
  print("=== Loaded " .. num_rows .. " sequencer rows from pattern ===")
  return true
end

-- Create default sequencer tracks (NO GROUP - simple and reliable)
local function setup_default_track_group()
  local song = renoise.song()
  
  print("=== Starting setup_default_track_group ===")
  
  -- Find the position to insert new tracks (after last sequencer track, before send/master)
  local insert_pos = 1
  
  -- Find the last sequencer track
  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      insert_pos = i + 1
    end
  end
  
  print("Will insert new tracks starting at position " .. insert_pos)
  
  -- Create tracks for this session
  for i = 1, num_rows do
    -- Get instrument name
    local instrument_name = "Unknown"
    if sequencer_data[i] and sequencer_data[i].instrument then
      local inst = song.instruments[sequencer_data[i].instrument]
      if inst then instrument_name = inst.name end
    end
    
    -- Insert track
    song:insert_track_at(insert_pos)
    local track = song.tracks[insert_pos]
    track.name = "Sequencer_" .. instrument_name
    track.color = {0x60, 0xC0, 0xFF}  -- Blue color for visual grouping
    
    -- Map this row to the track position (simple and stable!)
    track_mapping[i] = insert_pos
    print("Row " .. i .. " -> Track " .. insert_pos .. " (" .. instrument_name .. ")")
    
    -- Next track goes after this one
    insert_pos = insert_pos + 1
  end
  
  print("=== Completed setup_default_track_group ===")
  
  -- Select first sequencer track
  if track_mapping[1] then
    song.selected_track_index = track_mapping[1]
  end
end

-- Helper function to update mute button color based on track state
update_mute_button_color = function(row_index)
  local track_index = get_track_index_for_row(row_index)
  if not track_index then
    return
  end
  
  local song = renoise.song()
  if track_index > #song.tracks then
    return
  end
  
  local track = song.tracks[track_index]
  local button_id = "mute_button_" .. tostring(row_index)
  
  if vb.views[button_id] then
    -- Check if track is muted or off
    local is_muted = (track.mute_state == renoise.Track.MUTE_STATE_MUTED or 
                      track.mute_state == renoise.Track.MUTE_STATE_OFF)
    
    -- Use same color scheme as chord enable button
    vb.views[button_id].color = is_muted and {255, 200, 100} or {80, 80, 80}
  end
end

-- Function to mute/unmute a track
local function toggle_track_mute(row_index)
  local track_index = get_track_index_for_row(row_index)
  if not track_index then
    return
  end
  
  local song = renoise.song()
  local track = song.tracks[track_index]
  
  if track then
    -- Check if track is muted
    local is_muted = (track.mute_state == renoise.Track.MUTE_STATE_MUTED or 
                      track.mute_state == renoise.Track.MUTE_STATE_OFF)
    
    if is_muted then
      track:unmute()
    else
      track:mute()
    end
    
    -- Update button color to reflect new state
    update_mute_button_color(row_index)
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
    if data.step_states and data.step_states[s] and data.step_states[s] > 0 then  -- If step is active
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
  
  -- Add labels aligned with controls (new order)
  row:add_child(vb:text{width = cellSizeLg, text = "Instrument", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "C", align = "center"})
  row:add_child(vb:text{width = cellSizeLg, text = "Chord", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "TN", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "TD", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "TV", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "N", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "V", align = "center"})
  row:add_child(vb:text{width = cellSize, text = "D", align = "center"})
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


-- Function to update a specific step with a specific volume value
update_step_volume_in_pattern = function(row_index, step, volume_value)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument - 1  -- Zero-based index for pattern
    local track_index = get_track_index_for_row(row_index)  -- Get actual track index

    -- Get the current pattern
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    local track = song.tracks[track_index]

    -- Calculate the line index based on the step and loop every num_steps lines
    for line_index = step, song.patterns[current_pattern_index].number_of_lines, num_steps do
      -- Access the note column in the specified track and line
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)
      
      -- If this is a chord track, set volume on all visible note columns
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

-- Function to update a specific step with a specific delay value
local function update_step_delay_in_pattern(row_index, step, delay_value)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local track_index = get_track_index_for_row(row_index)
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index
    local pattern = song:pattern(current_pattern_index)

    -- Update all occurrences of this step in the pattern
    for line_index = step, pattern.number_of_lines, num_steps do
      local pattern_track = pattern:track(track_index)
      local line = pattern_track:line(line_index)
      local note_column = line:note_column(1)
      
      -- Only update if there's a note on this line
      if note_column.note_value ~= 121 then
        note_column.delay_value = delay_value
        print("Set delay " .. delay_value .. " for step " .. step .. " at line " .. line_index)
      end
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Helper function to clear all notes for a specific step across the entire pattern
local function clear_step_from_pattern(row_index, step)
  local track_index = get_track_index_for_row(row_index)  -- Get actual track index
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  -- Clear all occurrences of this step in the pattern
  for line_index = step, pattern.number_of_lines, num_steps do
    local pattern_track = pattern:track(track_index)
    local line = pattern_track:line(line_index)
    
    -- Clear all note columns
    for i = 1, 12 do
      local note_column = line:note_column(i)
      if note_column then
        note_column.note_value = 121  -- Empty note
        note_column.instrument_value = 255
        note_column.volume_value = 255
        note_column.delay_value = 0
        note_column.panning_value = 255
      end
    end
  end
  print("Cleared all pattern notes for row " .. row_index .. " step " .. step)
end

-- Function to update a specific step with a specific note value or chord
update_step_note_in_pattern = function(row_index, step, note_value)
  print("update_step_note_in_pattern called: row=" .. row_index .. ", step=" .. step .. ", note=" .. (note_value or "nil"))
  
  local data = sequencer_data[row_index]
  if not data then
    print("ERROR: No sequencer data for row " .. row_index)
    return
  end
  
  if data.instrument then
    local instrument_index = data.instrument - 1  -- Zero-based index for pattern
    local track_index = get_track_index_for_row(row_index)  -- Get actual track index

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

    -- FIRST: Clear all existing notes for this step across the entire pattern
    clear_step_from_pattern(row_index, step)

    -- THEN: Add new notes at the correct intervals
    for line_index = step, song.patterns[current_pattern_index].number_of_lines, num_steps do
      -- Access the note column in the specified track and line
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)
      
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
            note_column.delay_value = 0 -- Ensure no note delay
            note_column.panning_value = 255 -- No panning change
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

-- Function to add or remove a note in the pattern for a specific row
update_note_in_pattern = function(row_index, step, add_note)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument - 1  -- Zero-based index for pattern
    local track_index = get_track_index_for_row(row_index)  -- Get actual track index
    local note_value = data.note_value or 48 -- Use dynamic note value or default to C3

    -- Get the current pattern
    local song = renoise.song()
    local current_pattern_index = song.selected_pattern_index

    -- Calculate the line index based on the step and loop every num_steps lines
    for line_index = step, song.patterns[current_pattern_index].number_of_lines, num_steps do
      -- Access the note column in the specified track and line
      local pattern_track = song:pattern(current_pattern_index):track(track_index)
      local line = pattern_track:line(line_index)

      if add_note then
        -- Add the note
        local note_column = line:note_column(1) -- Assuming first note column
        note_column.note_value = note_value
        note_column.instrument_value = instrument_index
        note_column.volume_value = 128 -- Max volume (0-128 scale)
        note_column.delay_value = 0 -- Ensure no note delay
        note_column.panning_value = 255 -- No panning change
        print("Added note " .. note_value .. " on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at line " .. line_index)
      else
        -- Remove all notes (clear up to 12 note columns to handle chords)
        for i = 1, 12 do
          local note_column = line:note_column(i)
          if note_column then
        note_column.note_value = 121 -- 121 represents an empty note
        note_column.instrument_value = 255 -- 255 represents no instrument
        note_column.volume_value = 255 -- 255 represents no volume change
            note_column.delay_value = 0 -- Clear any note delay
            note_column.panning_value = 255 -- Clear any panning
          end
        end
        print("Removed all notes in row " .. row_index .. " track " .. track_index .. " at line " .. line_index)
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
      for step_index = 1, num_steps do
        local step_state = data.step_states and data.step_states[step_index] or 0
        if step_state == 1 then
          -- Play: Add notes for active steps at intervals of num_steps (16, 32, etc.)
          local note_to_use = data.step_notes and data.step_notes[step_index] or data.note_value
          update_step_note_in_pattern(row_index, step_index, note_to_use)
        elseif step_state == 2 then
          -- Stop state: clear note first, then set volume to 0
          update_note_in_pattern(row_index, step_index, false)
          update_step_volume_in_pattern(row_index, step_index, 0)
        else
          -- Off state: clear notes
          update_note_in_pattern(row_index, step_index, false)
        end
      end
    end
  end
end


-- Function to update note delay for all notes in a specific track
local function update_note_delay_value(value, target_track_index)
  local song = renoise.song()
  local track_index = target_track_index or song.selected_track_index
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  -- Check if track exists and supports note columns
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
  
  -- Convert value from 0 to 255 range (note delay range)
  local delay_hex_value = math.floor(value)
  delay_hex_value = math.max(0, math.min(255, delay_hex_value)) -- Clamp to 0-255 range
  
  -- Enable delay column on the track
  track.delay_column_visible = true
  
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
    for step_index = 1, num_steps do
      -- Clear the data model
      if not sequencer_data[row_index].step_states then
        sequencer_data[row_index].step_states = {}
      end
      sequencer_data[row_index].step_states[step_index] = 0  -- Reset to Off
      
      -- Clear the UI button
      local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step_index)
      if vb.views[button_id] then
        vb.views[button_id].text = " "
        vb.views[button_id].color = {80, 80, 80}  -- Gray for Off
      end
    end
  end
  
  print("Cleared all notes from pattern and sequencer")
end

--- Sync pattern notes to sequencer (read notes from pattern and update sequencer)
local function sync_pattern_to_sequencer()
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  print("=== Syncing pattern to sequencer ===")
  
  -- For each sequencer row
  for row_index = 1, #sequencer_data do
    local track_index = get_track_index_for_row(row_index)
    
    if track_index and track_index <= #song.tracks then
      local pattern_track = pattern:track(track_index)
      
      -- Read notes from pattern lines 1-num_steps
      for step = 1, num_steps do
        local line = pattern_track:line(step)
        local note_column = line:note_column(1)
        
        if note_column and note_column.note_value < 121 then
          -- Found a note - set step to Play and store note value
          sequencer_data[row_index].step_states[step] = 1  -- Play
          sequencer_data[row_index].step_notes[step] = note_column.note_value
          
          -- Update UI button
          local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
          if vb.views[button_id] then
            vb.views[button_id].text = note_value_to_string(note_column.note_value)
            vb.views[button_id].color = {100, 255, 100}  -- Green for Play
          end
          
          -- Update note rotary
          local note_rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step)
          if vb.views[note_rotary_id] then
            local rotary_value = map_note_to_rotary(note_column.note_value)
            vb.views[note_rotary_id].value = rotary_value
          end
          
          print("Row " .. row_index .. " Step " .. step .. ": Found note " .. note_column.note_value .. " (" .. note_value_to_string(note_column.note_value) .. ")")
        else
          -- No note - set step to Off
          sequencer_data[row_index].step_states[step] = 0  -- Off
          sequencer_data[row_index].step_notes[step] = nil
          
          -- Update UI button
          local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(step)
          if vb.views[button_id] then
            vb.views[button_id].text = " "
            vb.views[button_id].color = {80, 80, 80}  -- Gray for Off
          end
        end
      end
    end
  end
  
  print("Pattern sync complete!")
end

-- Create a row for the sequencer
local function create_step_row(row_index, steps)
  -- Use actual steps parameter instead of creating 64 and hiding
  local actual_steps = math.min(steps, num_steps)
  local row = vb:horizontal_aligner{
    
      -- Instrument selector (first)
      vb:popup{
        id = "instrument_popup_" .. tostring(row_index),
        width = cellSizeLg,
        height = cellSize,
        items = get_instrument_names(),
        tooltip = "Select instrument for this row",
        notifier = function(index)
          sequencer_data[row_index].instrument = index
          print("Selected instrument " .. index .. " (0-based: " .. (index-1) .. ") for row " .. row_index)
          
          -- Update the track name to reflect the new instrument
          local song = renoise.song()
          local track_index = get_track_index_for_row(row_index)
          if track_index <= #song.tracks then
            local instrument_name = song.instruments[index].name
            song.tracks[track_index].name = "Sequencer_" .. instrument_name
            print("Updated track " .. track_index .. " name to: " .. song.tracks[track_index].name)
          end
          
          -- Update all currently checked steps in this row with the new instrument
          local current_pattern_index = song.selected_pattern_index
          local pattern = song:pattern(current_pattern_index)
          local pattern_track = pattern:track(track_index)
          
          -- Go through all steps in this row
          for s = 1, num_steps do
            if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] then
              local step_state = sequencer_data[row_index].step_states[s]
              
              if step_state == 1 then
                -- Only update play steps, not stop steps
                -- Update all occurrences of this step in the pattern
                for line_index = s, pattern.number_of_lines, num_steps do
                  local line = pattern_track:line(line_index)
                  local note_column = line:note_column(1)
                  
                  -- If there's a note on this line, update its instrument
                  if note_column.note_value ~= 121 then  -- 121 = empty note
                    note_column.instrument_value = index - 1  -- Zero-based for pattern
                    print("Updated step " .. s .. " at line " .. line_index .. " to instrument " .. index)
                  end
                end
              end
              -- Stop steps (state 2) don't have notes, so nothing to update
            end
          end
        end
      },
      
      -- Chord track toggle
      vb:button{
        id = "chord_toggle_" .. tostring(row_index),
        text = "♯",
        width = cellSize,
        height = cellSize,
        color = {80, 80, 80},  -- Gray when not chord track
        tooltip = "Enable/disable chord mode for this row",
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
        tooltip = "Select chord type (enable C button first)",
        notifier = function(index)
          local chord_items = vb.views["chord_popup_" .. tostring(row_index)].items
          local chord_type = chord_items[index]
          sequencer_data[row_index].chord_type = chord_type
          
          -- Update track note columns if chord mode is enabled
          if sequencer_data[row_index].is_chord_track then
            local song = renoise.song()
            local track_index = get_track_index_for_row(row_index)  -- Get actual track index
            
            if track_index <= #song.tracks then
              local track = song.tracks[track_index]
              if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
                local chord_intervals = CHORD_TYPES[chord_type]
                if chord_intervals and #chord_intervals > 0 then
                  local num_notes = #chord_intervals
                  track.visible_note_columns = math.max(1, math.min(12, num_notes))
                  print("Updated track " .. track_index .. " to " .. num_notes .. " note columns for " .. chord_type .. " chord")
                else
                  track.visible_note_columns = 1
                end
                
                -- Update all active steps with new chord type
                for s = 1, num_steps do
                  if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] then
                    local step_state = sequencer_data[row_index].step_states[s]
                    
                    if step_state == 1 then
                      -- Only update play steps, not stop steps
                      local note_to_use = sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] or sequencer_data[row_index].note_value
                      update_step_note_in_pattern(row_index, s, note_to_use)
                    elseif step_state == 2 then
                      -- Stop state: clear note first, then set volume to 0
                      update_note_in_pattern(row_index, s, false)
                      update_step_volume_in_pattern(row_index, s, 0)
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
        id = "note_rotary_" .. tostring(row_index),  -- Unique ID for note rotary
        min = 0,     -- 0% (C2)
        max = 100,   -- 100% (C4) 
        value = 50,  -- 50% (C3 default)
        width = cellSize,
        tooltip = "Track Note (base pitch for all steps)",
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
          
          -- Capture OLD track note value before updating
          local old_track_note = sequencer_data[row_index].note_value or base_note_value
          
          -- Calculate transposition offset (how much the track note changed)
          local transposition = new_note_value - old_track_note
          
          -- Update the note value for this row
          sequencer_data[row_index].note_value = new_note_value
          
          -- Update all step notes by applying the same transposition
          if sequencer_data[row_index].step_notes then
            for step_index, old_step_note in pairs(sequencer_data[row_index].step_notes) do
              -- Calculate offset from the OLD track note (this preserves the user's intended interval)
              local step_offset = old_step_note - old_track_note
              
              -- Apply the offset to the NEW track note
              local new_step_note = new_note_value + step_offset
              
              -- Constrain to scale
              new_step_note = snap_to_scale(new_step_note, select(1, compute_note_range(base_note_value)), select(2, compute_note_range(base_note_value)))
              
              -- Update step note data
              sequencer_data[row_index].step_notes[step_index] = new_step_note
              
              -- Update the step note rotary UI
              local step_rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step_index)
              if vb.views[step_rotary_id] then
                vb.views[step_rotary_id].value = note_to_percentage(new_step_note, base_note_value)
              end
              
              print("Step " .. step_index .. ": old_step=" .. old_step_note .. ", offset=" .. step_offset .. ", new_step=" .. new_step_note)
            end
          end
          
          -- Update all active steps in the pattern with their new constrained values
          for s = 1, num_steps do
            if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] then
              local step_state = sequencer_data[row_index].step_states[s]
              
              if step_state == 1 then
                -- Play state: update note
              local note_to_use
              if sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] then
                -- Use constrained step-specific note
                note_to_use = sequencer_data[row_index].step_notes[s]
              else
                -- Use new track note
                note_to_use = new_note_value
              end
              update_step_note_in_pattern(row_index, s, note_to_use)
              elseif step_state == 2 then
                -- Stop state: clear note first, then set volume to 0
                update_note_in_pattern(row_index, s, false)
                update_step_volume_in_pattern(row_index, s, 0)
              end
              -- State 0: do nothing (off)
            end
          end
          
          print("Updated track " .. row_index .. " note from " .. old_track_note .. " to " .. new_note_value .. " (transposition: " .. transposition .. " semitones)")
        end
      },
      
      -- Track Delay rotary
      vb:rotary{
        id = "track_delay_rotary_" .. tostring(row_index),  -- Unique ID for track delay rotary
        min = -100,  -- Minimum delay value
        max = 100,   -- Maximum delay value
        value = 0,   -- Initialize with 0
        width = cellSize,
        tooltip = "Track Delay (-100ms to +100ms)",
        notifier = function(value)
          -- Update the track delay for the specific row
          local track_index = get_track_index_for_row(row_index)  -- Get actual track index
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
        min = 0,     -- 0% (silent)
        max = 100,   -- 100% (full volume)
        value = 100, -- 100% default
        width = cellSize,
        tooltip = "Track Volume (master volume for all steps in this row)",
        notifier = function(value)
          -- Store track volume in sequencer data
          if not sequencer_data[row_index].track_volume then
            sequencer_data[row_index].track_volume = 100
          end
          sequencer_data[row_index].track_volume = value
          
          -- Apply to Renoise track
          local song = renoise.song()
          local track_index = get_track_index_for_row(row_index)
          if track_index <= #song.tracks then
            local track = song.tracks[track_index]
            if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
              -- Convert percentage (0-100) to linear volume (0-1)
              track.prefx_volume.value = value / 100
              print("Set track " .. track_index .. " volume to " .. (value / 100))
            end
          end
        end
      },
      
      -- Visibility toggle buttons
      vb:button{
        id = "note_toggle_" .. tostring(row_index),
        text = "N",  -- Note
        width = cellSize,
        height = cellSize,
        color = {80, 80, 80},  -- Gray when hidden (default)
        tooltip = "Toggle note row visibility",
        notifier = function()
          toggle_note_row_visibility(row_index)
        end
      },
      
      vb:button{
        id = "volume_toggle_" .. tostring(row_index),
        text = "V",  -- Volume
        width = cellSize,
        height = cellSize,
        color = {80, 80, 80},  -- Gray when hidden (default)
        tooltip = "Toggle volume row visibility",
        notifier = function()
          toggle_volume_row_visibility(row_index)
        end
      },
      
      vb:button{
        id = "delay_toggle_" .. tostring(row_index),
        text = "D",  -- Delay
        width = cellSize,
        height = cellSize,
        color = {80, 80, 80},  -- Gray when hidden (default)
        tooltip = "Toggle delay row visibility",
        notifier = function()
          toggle_delay_row_visibility(row_index)
        end
      },
  }
  
  -- Add MIDI mappings for track controls (remove old ones first to prevent duplicates)
  local track_delay_mapping = "Step Sequencer: Row " .. row_index .. " Track Delay"
  pcall(function() renoise.tool():remove_midi_mapping(track_delay_mapping) end)
  renoise.tool():add_midi_mapping{
    name = track_delay_mapping,
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
  
  local track_volume_mapping = "Step Sequencer: Row " .. row_index .. " Track Volume"
  pcall(function() renoise.tool():remove_midi_mapping(track_volume_mapping) end)
  renoise.tool():add_midi_mapping{
    name = track_volume_mapping,
    invoke = function(message)
      if (message:is_abs_value()) then
        -- Convert MIDI CC value (0-127) to percentage (0-100)
        local volume_percentage = (message.int_value / 127) * 100
        local control_id = "track_volume_rotary_" .. tostring(row_index)
        if vb.views[control_id] then
          vb.views[control_id].value = volume_percentage
        end
      end
    end
  }
  
  local track_note_mapping = "Step Sequencer: Row " .. row_index .. " Track Note"
  pcall(function() renoise.tool():remove_midi_mapping(track_note_mapping) end)
  renoise.tool():add_midi_mapping{
    name = track_note_mapping,
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
  
  
  -- Add 3-state buttons for each step (only create what we need)
  -- States: 0 = Off, 1 = Play, 2 = Stop
  for s = 1, actual_steps do
    local button_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
    
    -- Initialize step state if not exists
    if not sequencer_data[row_index].step_states then
      sequencer_data[row_index].step_states = {}
    end
    if not sequencer_data[row_index].step_states[s] then
      sequencer_data[row_index].step_states[s] = 0  -- Default to Off
    end
    
    -- Helper function to get button appearance based on state
    local function get_button_appearance(state)
      -- Static color definitions
      local button_off = {80, 80, 80}      -- Gray
      local button_play = {147, 245, 66}      -- Green
      local button_stop = {245, 66, 93}      -- Red
      
      if state == 0 then
        return " ", button_off  -- Off: gray, empty
      elseif state == 1 then
        return "▶", button_play  -- Play: green, play symbol
      elseif state == 2 then
        return "■", button_stop  -- Stop: red, stop symbol
      end
    end
    
    local initial_text, initial_color = get_button_appearance(sequencer_data[row_index].step_states[s])
    
    row:add_child(vb:button{
      id = button_id,
      text = initial_text,
      color = initial_color,
      width = cellSize,
      height = cellSize,
      notifier = function()
        -- Cycle through states: 0 -> 1 -> 2 -> 0
        local current_state = sequencer_data[row_index].step_states[s]
        local new_state = (current_state + 1) % 3
        sequencer_data[row_index].step_states[s] = new_state
        
        -- Update button appearance
        local new_text, new_color = get_button_appearance(new_state)
        if vb.views[button_id] then
          vb.views[button_id].text = new_text
          vb.views[button_id].color = new_color
        end
        
        print("Step state changed:")
        print("  Row: " .. row_index)
        print("  Step: " .. s)
        print("  Old state: " .. current_state .. " New state: " .. new_state)
        
        -- Handle state changes
        if new_state == 0 then
          -- Off: clear note from pattern
          update_note_in_pattern(row_index, s, false)
        elseif new_state == 1 then
          -- Play: add note to pattern
          local note_to_use = sequencer_data[row_index].step_notes and sequencer_data[row_index].step_notes[s] or sequencer_data[row_index].note_value
          update_step_note_in_pattern(row_index, s, note_to_use)
        elseif new_state == 2 then
          -- Stop: clear any existing note first, then set volume to 0
          update_note_in_pattern(row_index, s, false)
          update_step_volume_in_pattern(row_index, s, 0)
        end
      end
    })
  end
  
  -- Add mute track button
  local mute_button_id = "mute_button_" .. tostring(row_index)
  
  row:add_child(vb:button{
    id = mute_button_id,
    text = "M",
    width = cellSize,
    height = cellSize,
    tooltip = "Mute/unmute track",
    notifier = function()
      toggle_track_mute(row_index)
    end
  })
  
  -- Update button color based on current track state
  update_mute_button_color(row_index)
  
  -- Add Save and Remove buttons after the steps
  row:add_child(vb:button{
    text = "S",  -- Common Renoise phrase icon (double eighth notes)
    width = cellSize,
    height = cellSize,
    tooltip = "Save row as phrase",
    notifier = function()
      save_row_as_phrase(row_index)
    end
  })
  
  row:add_child(vb:button{
    text = "↩",  -- Backspace icon
    width = cellSize,
    height = cellSize,
    color = {245, 194, 66},  -- Orange color
    tooltip = "Clear pattern notes and reset row",
    notifier = function()
      remove_sequencer_row(row_index)
    end
  })
  
  row:add_child(vb:button{
    text = "x",  -- Trash can icon
    width = cellSize,
    height = cellSize,
    color = {245, 66, 93},  -- Red color
    tooltip = "Delete row AND remove track from Renoise",
    notifier = function()
      remove_sequencer_row_and_track(row_index)
    end
  })
  
  return row
end

-- Create a note row with rotary dials for each step
local function create_note_row(row_index, steps)
  -- Use actual steps parameter instead of creating 64 and hiding
  local actual_steps = math.min(steps, num_steps)
  local note_row = vb:horizontal_aligner{
    -- Add spacing to align with the step checkboxes (after all controls)
    vb:text{width = cellSizeLg, text = ""},  -- Instrument space
    vb:text{width = cellSize, text = ""},  -- Chord toggle space
    vb:text{width = cellSizeLg, text = ""},  -- Chord selection space
    vb:text{width = cellSize, text = ""},  -- Track note space  
    vb:text{width = cellSize, text = ""},  -- Track delay space
    vb:text{width = cellSize, text = ""},  -- Track volume space
    vb:text{width = cellSize, text = ""},  -- Note toggle space
    vb:text{width = cellSize, text = ""},  -- Volume toggle space
    vb:text{width = cellSize, text = ""},  -- Delay toggle space
  }
  
  -- Initialize visibility state
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end
  
  -- Add rotary dials for each step (only create what we need)
  for s = 1, actual_steps do
    local rotary_id = "step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    note_row:add_child(vb:rotary{
      id = rotary_id,
      min = 0,     -- 0% (C2)
      max = 100,   -- 100% (C4) 
      value = 50,  -- 50% (C3 default)
      width = cellSize,
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
        if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] and sequencer_data[row_index].step_states[s] > 0 then
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
  
  -- Wrap with vertical spacing
  return vb:column{
    spacing = 4,
    note_row
  }
end

-- Create a volume row with rotary dials for each step
local function create_volume_row(row_index, steps)
  -- Use actual steps parameter instead of creating 64 and hiding
  local actual_steps = math.min(steps, num_steps)
  local volume_row = vb:horizontal_aligner{
    -- Add spacing to align with the step checkboxes (after all controls)
    vb:text{width = cellSizeLg, text = ""},  -- Instrument space
    vb:text{width = cellSize, text = ""},  -- Chord toggle space
    vb:text{width = cellSizeLg, text = ""},  -- Chord selection space
    vb:text{width = cellSize, text = ""},  -- Track note space
    vb:text{width = cellSize, text = ""},  -- Track delay space
    vb:text{width = cellSize, text = ""},  -- Track volume space
    vb:text{width = cellSize, text = ""},  -- Note toggle space
    vb:text{width = cellSize, text = ""},  -- Volume toggle space
    vb:text{width = cellSize, text = ""},  -- Delay toggle space
  }
  
  -- Initialize visibility state
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end
  
  -- Add rotary dials for each step volume (only create what we need)
  for s = 1, actual_steps do
    local rotary_id = "step_volume_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    volume_row:add_child(vb:rotary{
      id = rotary_id,
      min = 0,     -- 0% (silent)
      max = 100,   -- 100% (full volume) 
      value = 100, -- 100% (full volume default)
      width = cellSize,
      notifier = function(value)
        -- Convert percentage to MIDI volume value (0-127 range)
        local volume_value = math.floor((value / 100) * 127)
        
        -- Store per-step volume values
        if not sequencer_data[row_index].step_volumes then
          sequencer_data[row_index].step_volumes = {}
        end
        sequencer_data[row_index].step_volumes[s] = volume_value
        
        -- Update pattern with specific volume for this step (only if step is active)
        if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] and sequencer_data[row_index].step_states[s] > 0 then
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
  
  -- Wrap with vertical spacing
  return vb:column{
    spacing = 4,
    volume_row
  }
end

-- Create a delay row for per-step delay controls
local function create_delay_row(row_index, steps)
  local actual_steps = math.min(steps, num_steps)
  local delay_row = vb:horizontal_aligner{
    -- Add spacing to align with the step checkboxes (after all controls)
    vb:text{width = cellSizeLg, text = ""},  -- Instrument space
    vb:text{width = cellSize, text = ""},  -- Chord toggle space
    vb:text{width = cellSizeLg, text = ""},  -- Chord selection space
    vb:text{width = cellSize, text = ""},  -- Track note space
    vb:text{width = cellSize, text = ""},  -- Track delay space
    vb:text{width = cellSize, text = ""},  -- Track volume space
    vb:text{width = cellSize, text = ""},  -- Note toggle space
    vb:text{width = cellSize, text = ""},  -- Volume toggle space
    vb:text{width = cellSize, text = ""},  -- Delay toggle space
  }
  
  -- Initialize visibility state
  if not track_visibility[row_index] then
    track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end
  
  -- Add rotary dials for each step delay (only create what we need)
  for s = 1, actual_steps do
    local rotary_id = "step_delay_rotary_" .. tostring(row_index) .. "_" .. tostring(s)
    delay_row:add_child(vb:rotary{
      id = rotary_id,
      min = 0,     -- 0 (no delay)
      max = 255,   -- 255 (maximum delay in hex) 
      value = 0,   -- 0 (no delay default)
      width = cellSize,
      notifier = function(value)
        -- Store per-step delay values
        if not sequencer_data[row_index].step_delays then
          sequencer_data[row_index].step_delays = {}
        end
        sequencer_data[row_index].step_delays[s] = math.floor(value)
        
        -- Update pattern with specific delay for this step (only if step is active)
        if sequencer_data[row_index].step_states and sequencer_data[row_index].step_states[s] and sequencer_data[row_index].step_states[s] > 0 then
          update_step_delay_in_pattern(row_index, s, math.floor(value))
        end
        
        print("Set step " .. s .. " delay to " .. math.floor(value) .. " for row " .. row_index)
      end
    })
    
    -- Add MIDI mapping for this delay rotary  
    local mapping_name = "Step Sequencer: Row " .. row_index .. " Step " .. s .. " Delay"
    pcall(function() renoise.tool():remove_midi_mapping(mapping_name) end)
    renoise.tool():add_midi_mapping{
      name = mapping_name,
      invoke = function(message)
        if (message:is_abs_value()) then
          -- Convert MIDI CC value (0-127) to delay value (0-255)
          local delay_value = (message.int_value / 127) * 255
          if vb.views[rotary_id] then
            vb.views[rotary_id].value = delay_value
          end
        end
      end
    }
  end
  
  -- Store reference to the delay row and set initial visibility
  track_delay_rows[row_index] = delay_row
  delay_row.visible = track_visibility[row_index].delay_visible
  
  -- Wrap with vertical spacing
  return vb:column{
    spacing = 4,
    delay_row
  }
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
        
        -- Clear all note columns (to handle chords)
        for i = 1, 12 do
          local note_column = line:note_column(i)
          if note_column and note_column.note_value ~= 121 then  -- 121 = empty note
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
    if data.step_states and data.step_states[current_step] and data.step_states[current_step] > 0 then
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
-- Create the main dialog window
function show_sequencer_dialog()
  -- Close existing dialog if open
  if dialog and dialog.visible then
    dialog:close()
  end
  
  -- Remove previous instrument observable if it exists
  if instruments_notifier then
    pcall(function()
      renoise.song().instruments_observable:remove_notifier(instruments_notifier)
    end)
    instruments_notifier = nil
  end
  
  -- Don't rebuild track mapping - it would delete orphaned tracks from previous sessions
  -- Each session has its own clean mapping created in setup_default_track_group()
  
  -- Remove existing MIDI mappings to avoid duplicates
  -- Note: We can't remove all at once with a pattern, so we try to remove known ones
  for r = 1, 20 do  -- Remove up to 20 potential rows
    pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Track Delay") end)
    pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Track Note") end)
    for s = 1, 64 do
      pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Step " .. s .. " Note") end)
      pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Step " .. s .. " Volume") end)
    end
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
          local old_steps = sequencer_data[r].step_states or {}
          local old_step_notes = sequencer_data[r].step_notes or {}
          local old_step_volumes = sequencer_data[r].step_volumes or {}
          
          sequencer_data[r].step_states = {}
          sequencer_data[r].step_notes = {}
          sequencer_data[r].step_volumes = {}
          
          -- Copy existing step data up to new_steps limit
          for s = 1, new_steps do
            sequencer_data[r].step_states[s] = old_steps[s] or 0
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
    -- Icon Buttons (left side)
    vb:button{
      text = "+",
      width = cellSize,
      height = cellSize,
      tooltip = "Add Row",
      notifier = function()
        local song = renoise.song()
        
        -- Find the position to insert (after last sequencer track)
        local insert_pos = 1
        for i = 1, #song.tracks do
          local track = song.tracks[i]
          if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
            insert_pos = i + 1
          end
        end
        
        print("Adding new row at track position: " .. insert_pos)
        
        -- Insert track
        song:insert_track_at(insert_pos)
        
        -- Get instrument name
        local instrument_name = "Unknown"
        if #song.instruments > 0 then
          instrument_name = song.instruments[1].name
        end
        
        -- Configure track
        local track = song.tracks[insert_pos]
        track.name = "Sequencer_" .. instrument_name
        track.color = {0x60, 0xC0, 0xFF}  -- Blue color
        
        -- Update row index and mapping
        local new_row_index = #sequencer_data + 1
        track_mapping[new_row_index] = insert_pos
        num_rows = num_rows + 1
        
        print("Row " .. new_row_index .. " -> Track " .. insert_pos .. " (" .. instrument_name .. ")")
        
        -- Initialize empty sequencer data
        sequencer_data[new_row_index] = {
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
        for s = 1, num_steps do
          sequencer_data[new_row_index].step_states[s] = 0  -- Default to Off
        end
        
        -- Initialize visibility data for new row
        track_visibility[new_row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
        
        -- Create UI rows
        step_grid_view:add_child(create_step_row(new_row_index, num_steps))
        step_grid_view:add_child(create_note_row(new_row_index, num_steps))
        step_grid_view:add_child(create_volume_row(new_row_index, num_steps))
        step_grid_view:add_child(create_delay_row(new_row_index, num_steps))
        apply_global_note_constraints()
        
        -- Select the new track
        song.selected_track_index = insert_pos
      end
    },
    vb:button{
      text = "▶",
      width = cellSize,
      height = cellSize,
      tooltip = "Play/Stop",
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
      text = "⌫",
      width = cellSize,
      height = cellSize,
      tooltip = "Clear",
      notifier = function()
        clear_pattern_and_sequencer()
      end
    },
    vb:button{
      text = "⟳",
      width = cellSize,
      height = cellSize,
      tooltip = "Refresh Instruments",
      notifier = function()
        refresh_instrument_dropdowns()
      end
    },
    vb:button{
      text = "⟲",
      width = cellSize,
      height = cellSize,
      tooltip = "Sync Pattern to Sequencer",
      notifier = function()
        sync_pattern_to_sequencer()
      end
    },
    -- Select Controls (right side)
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
  }

  -- Try to load sequencer from existing tracks, or create fresh session
  sequencer_data = {}
  track_visibility = {}
  track_mapping = {}
  
  -- Attempt to load from existing sequencer tracks in the pattern
  local loaded_from_pattern = load_sequencer_from_pattern()
  
  if not loaded_from_pattern then
    -- No existing tracks found - create new session with default first row
    print("Creating new sequencer session")
    sequencer_data[1] = {instrument = 1, note_value = 48, base_note_value = 48, step_states = {}, step_notes = {}, step_volumes = {}, step_delays = {}, track_volume = 100, is_chord_track = false, chord_type = "None"}
    for s = 1, num_steps do
      sequencer_data[1].step_states[s] = 0  -- Default to Off
    end
    track_visibility[1] = {note_visible = false, volume_visible = false, delay_visible = false}
    num_rows = 1
    
    -- Create new tracks for this session
    setup_default_track_group()
  else
    print("Loaded sequencer from existing tracks (num_rows: " .. num_rows .. ")")
  end
  
  -- Create UI for all existing sequencer rows
  for r = 1, #sequencer_data do
    if sequencer_data[r] then
      -- Initialize visibility data if not exists
      if not track_visibility[r] then
        track_visibility[r] = {note_visible = false, volume_visible = false, delay_visible = false}
      end
      
      -- Ensure step_delays exists
      if not sequencer_data[r].step_delays then
        sequencer_data[r].step_delays = {}
      end
      
      -- Create the rows
      step_grid_view:add_child(create_step_row(r, num_steps))
      step_grid_view:add_child(create_note_row(r, num_steps))
      step_grid_view:add_child(create_volume_row(r, num_steps))
      step_grid_view:add_child(create_delay_row(r, num_steps))
    end
  end
  
  apply_global_note_constraints()
  
  -- Sync any existing notes from pattern to sequencer
  sync_pattern_to_sequencer()

  -- Calculate dialog dimensions
  -- Base controls width: I(96) + C(24) + Chord(96) + TN(24) + TD(24) + TV(24) + N(24) + V(24) + D(24) = 360
  -- Step controls width: num_steps * 24
  -- After steps: S(24) + X(24) = 48
  -- Total width with margins
  local base_controls_width = cellSize * 7 + cellSizeLg * 2  -- 360 (added TV)
  local steps_width = num_steps * cellSize
  local after_steps_width = cellSize * 2  -- S and X buttons
  local total_content_width = base_controls_width + steps_width + after_steps_width
  local dialog_width = total_content_width + (dialog_margin * 2)
  
  -- Simple column layout - Renoise dialogs handle scrolling automatically
  dialog_content = vb:column{
    margin = dialog_margin,
    spacing = section_spacing,
    controls_row,
    step_indicators_row,
    step_grid_view
  }

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

  -- Show dialog with calculated width
  dialog = renoise.app():show_custom_dialog("Step Sequencer", dialog_content, function()
    -- Dialog closed callback (optional)
  end)
  
  -- Watch for instrument changes and auto-refresh dropdowns
  instruments_notifier = function()
    print("Instruments changed, refreshing dropdowns...")
    refresh_instrument_dropdowns()
  end
  renoise.song().instruments_observable:add_notifier(instruments_notifier)
end

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Step Sequencer",
  invoke = show_sequencer_dialog
}
