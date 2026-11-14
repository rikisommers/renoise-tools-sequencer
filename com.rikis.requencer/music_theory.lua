-- Pure functions for music theory operations.
-- All scale/octave/key parameters are passed explicitly (no global state reads).

local Constants = require("constants")

local MusicTheory = {}

-- Get list of available scale names from Renoise instrument or fallback
function MusicTheory.get_available_scales()
  local items = {"None"}
  local song = renoise.song()
  if #song.instruments > 0 then
    local inst = song.instruments[1]
    local modes = inst.trigger_options.available_scale_modes
    for _, m in ipairs(modes) do
      table.insert(items, m)
    end
  else
    for name, _ in pairs(Constants.SCALE_INTERVALS) do
      if name ~= "Chromatic" then table.insert(items, name) end
    end
    table.sort(items)
    table.insert(items, 1, "Chromatic")
    table.insert(items, 1, "None")
  end
  return items
end

-- Get sorted list of available chord type names
function MusicTheory.get_available_chords()
  local items = {}
  for name, _ in pairs(Constants.CHORD_TYPES) do
    table.insert(items, name)
  end
  table.sort(items)
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

-- Generate chord note values from a root note and chord type name
function MusicTheory.generate_chord_notes(root_note, chord_type)
  local intervals = Constants.CHORD_TYPES[chord_type]
  if not intervals or #intervals == 0 then
    return {root_note}
  end
  local chord_notes = {}
  for _, interval in ipairs(intervals) do
    local note = root_note + interval
    if note >= 0 and note <= 119 then
      table.insert(chord_notes, note)
    end
  end
  return chord_notes
end

-- Compute the min/max note range centered on base_note_value
function MusicTheory.compute_note_range(base_note_value, octave_range)
  local span = 12 * math.max(1, math.min(4, octave_range))
  local min_note = base_note_value - math.floor(span / 2)
  local max_note = base_note_value + math.ceil(span / 2)
  min_note = math.max(0, min_note)
  max_note = math.min(119, max_note)
  if max_note <= min_note then
    max_note = math.min(119, min_note + 12)
  end
  return min_note, max_note
end

-- Clamp a note value to the valid MIDI range (0-119)
function MusicTheory.clamp_note(n)
  return math.max(0, math.min(119, n))
end

-- Snap a note value to the nearest note in the given scale
function MusicTheory.snap_to_scale(note_value, min_note, max_note, scale_mode, scale_key)
  if scale_mode == "None" then
    return MusicTheory.clamp_note(math.max(min_note, math.min(max_note, note_value)))
  end

  local intervals = Constants.SCALE_INTERVALS[scale_mode]
  if not intervals then
    return MusicTheory.clamp_note(math.max(min_note, math.min(max_note, note_value)))
  end

  local root_pc = (scale_key - 1) % 12
  local allowed_pcs = {}
  for _, iv in ipairs(intervals) do
    allowed_pcs[(root_pc + iv) % 12] = true
  end

  local target = MusicTheory.clamp_note(note_value)
  if target < min_note then target = min_note end
  if target > max_note then target = max_note end

  if allowed_pcs[target % 12] then
    return target
  end

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
  return MusicTheory.clamp_note(best_note)
end

-- Convert a rotary percentage (0-100) to a constrained note value
function MusicTheory.percentage_to_note(percent, base_note_value, octave_range, scale_mode, scale_key)
  local min_note, max_note = MusicTheory.compute_note_range(base_note_value, octave_range)
  local note = math.floor(min_note + (percent / 100) * (max_note - min_note))
  return MusicTheory.snap_to_scale(note, min_note, max_note, scale_mode, scale_key)
end

-- Convert a note value to a rotary percentage (0-100)
function MusicTheory.note_to_percentage(note_value, base_note_value, octave_range)
  local min_note, max_note = MusicTheory.compute_note_range(base_note_value, octave_range)
  local n = math.max(min_note, math.min(max_note, note_value))
  if max_note == min_note then return 0 end
  return ((n - min_note) / (max_note - min_note)) * 100
end

-- Convert MIDI note value (0-119) to compact display string (e.g., "C4", "D#3")
function MusicTheory.note_value_to_string(note_value)
  if note_value >= 121 or note_value < 0 then
    return "--"
  end
  local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  local octave = math.floor(note_value / 12)
  local note_index = (note_value % 12) + 1
  local note_name = note_names[note_index]
  return note_name .. octave
end

-- Map note value to rotary percentage (convenience wrapper)
function MusicTheory.map_note_to_rotary(note_value, base_note_value, octave_range)
  return MusicTheory.note_to_percentage(note_value, base_note_value or 48, octave_range)
end

-- Returns sorted (low→high) list of MIDI note values in the octave of base_note that belong to scale
function MusicTheory.get_scale_notes_in_octave(scale_mode, scale_key, base_note)
  local octave_start = math.floor(base_note / 12) * 12

  if scale_mode == "None" then
    local notes = {}
    for i = 0, 11 do table.insert(notes, octave_start + i) end
    return notes
  end

  local intervals = Constants.SCALE_INTERVALS[scale_mode]
  if not intervals then
    local notes = {}
    for i = 0, 11 do table.insert(notes, octave_start + i) end
    return notes
  end

  local root_pc = (scale_key - 1) % 12
  local allowed_pcs = {}
  for _, iv in ipairs(intervals) do
    allowed_pcs[(root_pc + iv) % 12] = true
  end

  local notes = {}
  for i = 0, 11 do
    local note = octave_start + i
    if allowed_pcs[note % 12] and note >= 0 and note <= 119 then
      table.insert(notes, note)
    end
  end
  return notes  -- already sorted low→high
end

-- Returns {[step]=note_value} for all steps filled by arp, based on trigger notes and mode.
-- Segments: from each trigger step to the step before the next trigger (or end).
function MusicTheory.generate_arp_sequence(trigger_notes_map, mode, num_steps, scale_mode, scale_key)
  local result = {}

  local trigger_steps = {}
  for step, _ in pairs(trigger_notes_map) do
    table.insert(trigger_steps, step)
  end
  table.sort(trigger_steps)

  if #trigger_steps == 0 then return result end

  for seg_idx, trigger_step in ipairs(trigger_steps) do
    local trigger_note = trigger_notes_map[trigger_step]
    local next_trigger  = trigger_steps[seg_idx + 1] or (num_steps + 1)
    local seg_length    = next_trigger - trigger_step

    local scale_notes = MusicTheory.get_scale_notes_in_octave(scale_mode, scale_key, trigger_note)
    local n = #scale_notes

    -- Find closest scale note index to trigger_note
    local start_idx = 1
    if n > 0 then
      local best_dist = 999
      for i, note in ipairs(scale_notes) do
        local d = math.abs(note - trigger_note)
        if d < best_dist then best_dist = d; start_idx = i end
      end
    end

    local seq = {}
    if n == 0 then
      for i = 1, seg_length do seq[i] = trigger_note end
    elseif mode == "up" then
      for i = 1, seg_length do
        local idx = ((start_idx - 1 + (i - 1)) % n) + 1
        seq[i] = scale_notes[idx]
      end
    elseif mode == "down" then
      for i = 1, seg_length do
        local offset = ((start_idx - 1 - (i - 1)) % n + n) % n
        seq[i] = scale_notes[offset + 1]
      end
    elseif mode == "updown" then
      if n == 1 then
        for i = 1, seg_length do seq[i] = scale_notes[1] end
      else
        local pattern = {}
        for j = 1, n do table.insert(pattern, j) end
        for j = n - 1, 2, -1 do table.insert(pattern, j) end
        local pat_len = #pattern
        for i = 1, seg_length do
          local pidx = ((start_idx - 1 + (i - 1)) % pat_len) + 1
          seq[i] = scale_notes[pattern[pidx]]
        end
      end
    elseif mode == "downup" then
      if n == 1 then
        for i = 1, seg_length do seq[i] = scale_notes[1] end
      else
        local pattern = {}
        for j = n, 1, -1 do table.insert(pattern, j) end
        for j = 2, n - 1 do table.insert(pattern, j) end
        local pat_len = #pattern
        for i = 1, seg_length do
          local pidx = ((start_idx - 1 + (i - 1)) % pat_len) + 1
          seq[i] = scale_notes[pattern[pidx]]
        end
      end
    elseif mode == "random" then
      seq[1] = trigger_note
      for i = 2, seg_length do
        seq[i] = scale_notes[math.random(1, n)]
      end
    else
      for i = 1, seg_length do seq[i] = trigger_note end
    end

    for i = 1, seg_length do
      local step = trigger_step + i - 1
      if step <= num_steps then result[step] = seq[i] end
    end
  end

  return result
end

return MusicTheory
