---------------------------------------------------------------
-- music_theory.lua
-- Pure functions for scale/chord computation and note conversion.
-- No side effects -- all state is passed in as parameters.
---------------------------------------------------------------

local Constants = require("constants")

local MusicTheory = {}

--- Build a sorted list of available scale names from Renoise instruments.
-- @return table  Array of scale name strings, starting with "None".
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

--- Build a sorted list of available chord type names.
-- @return table  Array of chord name strings, "None" first.
function MusicTheory.get_available_chords()
  local items = {}
  for name, _ in pairs(Constants.CHORD_TYPES) do
    table.insert(items, name)
  end
  table.sort(items)
  -- Move "None" to the front
  for i, item in ipairs(items) do
    if item == "None" then
      table.remove(items, i)
      table.insert(items, 1, "None")
      break
    end
  end
  return items
end

--- Generate chord note values from a root note and chord type name.
-- @param root_note   number  MIDI note value (0-119)
-- @param chord_type  string  Key into Constants.CHORD_TYPES
-- @return table  Array of MIDI note values
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

--- Compute the min/max MIDI note range centred on a base note.
-- @param base_note_value  number  Centre MIDI note
-- @param octave_range     number  1-4 octaves
-- @return number, number  min_note, max_note
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

--- Clamp a note value to the valid MIDI range 0-119.
-- @param n  number
-- @return number
function MusicTheory.clamp_note(n)
  return math.max(0, math.min(119, n))
end

--- Snap a note value to the nearest allowed pitch in the given scale.
-- @param note_value  number  Target MIDI note
-- @param min_note    number  Range lower bound
-- @param max_note    number  Range upper bound
-- @param scale_mode  string  Scale name (or "None" for no constraint)
-- @param scale_key   number  1-12 root key index
-- @return number  Constrained MIDI note value
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

--- Convert a rotary percentage (0-100) to a constrained MIDI note.
-- @param percent          number  0-100
-- @param base_note_value  number  Centre note
-- @param octave_range     number  1-4
-- @param scale_mode       string
-- @param scale_key        number  1-12
-- @return number  MIDI note value
function MusicTheory.percentage_to_note(percent, base_note_value, octave_range, scale_mode, scale_key)
  local min_note, max_note = MusicTheory.compute_note_range(base_note_value, octave_range)
  local note = math.floor(min_note + (percent / 100) * (max_note - min_note))
  return MusicTheory.snap_to_scale(note, min_note, max_note, scale_mode, scale_key)
end

--- Convert a MIDI note value to a rotary percentage (0-100).
-- @param note_value       number
-- @param base_note_value  number
-- @param octave_range     number  1-4
-- @return number
function MusicTheory.note_to_percentage(note_value, base_note_value, octave_range)
  local min_note, max_note = MusicTheory.compute_note_range(base_note_value, octave_range)
  local n = math.max(min_note, math.min(max_note, note_value))
  if max_note == min_note then return 0 end
  return ((n - min_note) / (max_note - min_note)) * 100
end

--- Convert a MIDI note value (0-119) to a compact display string ("C4", "D#3").
-- Returns a 3-character left-padded string for uniform button width.
-- @param note_value  number
-- @return string
function MusicTheory.note_value_to_string(note_value)
  if note_value >= 121 or note_value < 0 then
    return "   "
  end

  local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  local octave = math.floor(note_value / 12)
  local note_index = (note_value % 12) + 1

  local note_str = note_names[note_index] .. octave

  while #note_str < 3 do
    note_str = " " .. note_str
  end
  if #note_str > 3 then
    note_str = string.sub(note_str, 1, 3)
  end

  return note_str
end

--- Wrapper: map a MIDI note to rotary percentage.
-- @param note_value       number
-- @param base_note_value  number  (defaults to 48 / C3)
-- @param octave_range     number  1-4
-- @return number
function MusicTheory.map_note_to_rotary(note_value, base_note_value, octave_range)
  return MusicTheory.note_to_percentage(note_value, base_note_value or 48, octave_range or 3)
end

return MusicTheory
