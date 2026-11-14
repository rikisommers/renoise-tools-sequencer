-- Persist all sequencer settings inside the song via renoise.song().tool_data
-- (a per-tool data slot saved with the .xrns).
--
-- The pattern remains the source of truth for notes/repeats; tool_data holds
-- everything the pattern can't: step count, scale/key/octave range, chord
-- type, arp settings, values on empty steps, sub-row visibility, piano roll
-- scroll, repeat speed, etc.
--
-- Saving is throttled from an idle notifier and only writes when the
-- serialized snapshot actually changed.

local State = require("state")

local Persistence = {}

local FORMAT_VERSION = 1
local SAVE_INTERVAL  = 1     -- seconds between change checks

-- Scalar per-row fields restored from the snapshot
local ROW_SCALARS = {
  "instrument", "note_value", "base_note_value", "track_volume",
  "is_chord_track", "chord_type",
  "arp_enabled", "arp_mode",
  "piano_roll_visible", "piano_roll_low",
  "repeat_speed",
}

---------------------------------------------------------------------------
-- Serialization (plain tables of numbers/strings/booleans, sorted keys so
-- identical data always produces an identical string)
---------------------------------------------------------------------------

local function sort_keys(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return a < b
end

local function serialize(v)
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.6g", v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local keys = {}
    for k, _ in pairs(v) do
      local kt = type(k)
      if kt == "number" or kt == "string" then table.insert(keys, k) end
    end
    table.sort(keys, sort_keys)
    local parts = {}
    for _, k in ipairs(keys) do
      local sv = serialize(v[k])
      if sv then
        table.insert(parts, "[" .. serialize(k) .. "]=" .. sv)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return nil  -- functions, userdata, nil: skipped
end

local function deserialize(s)
  if type(s) ~= "string" or s == "" then return nil end
  local chunk = loadstring("return " .. s)
  if not chunk then return nil end
  setfenv(chunk, {})  -- no access to globals: data only
  local ok, result = pcall(chunk)
  if ok and type(result) == "table" then return result end
  return nil
end

local function copy_table(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy_table(v) end
  return c
end

---------------------------------------------------------------------------
-- Snapshot
---------------------------------------------------------------------------

local function build_snapshot()
  local song = renoise.song()
  local snapshot = {
    v            = FORMAT_VERSION,
    num_steps    = State.num_steps,
    octave_range = State.global_octave_range,
    scale_mode   = State.global_scale_mode,
    scale_key    = State.global_scale_key,
    rows         = {},
  }

  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row then
      local saved = {}
      for _, key in ipairs(ROW_SCALARS) do saved[key] = row[key] end
      saved.step_notes        = copy_table(row.step_notes)
      saved.step_volumes      = copy_table(row.step_volumes)
      saved.step_delays       = copy_table(row.step_delays)
      saved.arp_trigger_notes = copy_table(row.arp_trigger_notes)
      saved.visibility        = copy_table(State.track_visibility[r])

      local ti = State.track_mapping[r]
      if ti and song.tracks[ti] then saved.track_name = song.tracks[ti].name end

      snapshot.rows[r] = saved
    end
  end
  return snapshot
end

local last_saved = nil

-- Write the current session into the song (only if it changed)
function Persistence.save()
  if not State.session_valid or #State.sequencer_data == 0 then return end
  local s = serialize(build_snapshot())
  if not s or s == last_saved then return end
  local ok, err = pcall(function() renoise.song().tool_data = s end)
  if ok then
    last_saved = s
    print("Persistence: saved " .. #s .. " bytes (num_steps=" .. tostring(State.num_steps) .. ", rows=" .. #State.sequencer_data .. ")")
  else
    print("Persistence: failed to save tool_data: " .. tostring(err))
  end
end

-- Read the saved snapshot from the song, or nil
function Persistence.load()
  local ok, data = pcall(function() return renoise.song().tool_data end)
  if not ok then
    print("Persistence: could not read tool_data: " .. tostring(data))
    return nil
  end
  if data == nil then
    print("Persistence: no saved data in this song")
    return nil
  end
  local snapshot = deserialize(data)
  if snapshot and snapshot.v == FORMAT_VERSION then
    last_saved = data
    print("Persistence: loaded " .. #data .. " bytes (num_steps=" .. tostring(snapshot.num_steps) .. ")")
    return snapshot
  end
  print("Persistence: saved data could not be parsed (" .. #data .. " bytes)")
  return nil
end

---------------------------------------------------------------------------
-- Restore
---------------------------------------------------------------------------

-- Restore global settings. Call before building the UI / reading the pattern.
function Persistence.apply_globals(snapshot)
  if not snapshot then return end
  if tonumber(snapshot.num_steps) then State.num_steps = snapshot.num_steps end
  if tonumber(snapshot.octave_range) then State.global_octave_range = snapshot.octave_range end
  if type(snapshot.scale_mode) == "string" then State.global_scale_mode = snapshot.scale_mode end
  if tonumber(snapshot.scale_key) then State.global_scale_key = snapshot.scale_key end
end

-- Match saved rows to loaded rows: by order when counts match, otherwise
-- by track name (in order), so deleted/added tracks don't shift settings.
local function match_rows(snapshot)
  local saved_rows = snapshot.rows or {}
  local matches = {}
  if #saved_rows == #State.sequencer_data then
    for r = 1, #saved_rows do matches[r] = saved_rows[r] end
    return matches
  end

  local song = renoise.song()
  local used = {}
  for r = 1, #State.sequencer_data do
    local ti = State.track_mapping[r]
    local name = ti and song.tracks[ti] and song.tracks[ti].name
    for j = 1, #saved_rows do
      if not used[j] and saved_rows[j].track_name == name then
        used[j] = true
        matches[r] = saved_rows[j]
        break
      end
    end
  end
  return matches
end

-- Overlay saved row settings onto rows freshly loaded from the pattern.
-- Pattern wins for active steps; saved values fill everything else.
function Persistence.apply_rows(snapshot)
  if not snapshot then return end
  local matches = match_rows(snapshot)

  for r, saved in pairs(matches) do
    local row = State.sequencer_data[r]
    if row and type(saved) == "table" then
      for _, key in ipairs(ROW_SCALARS) do
        if saved[key] ~= nil then row[key] = saved[key] end
      end

      -- Step pitch: pattern for active steps, saved overrides for others
      row.step_notes = row.step_notes or {}
      for s, n in pairs(saved.step_notes or {}) do
        if row.step_states[s] ~= 1 and s <= State.num_steps then
          row.step_notes[s] = n
        end
      end

      -- Volumes/delays: pattern value if present, else saved
      row.step_volumes = row.step_volumes or {}
      for s, v in pairs(saved.step_volumes or {}) do
        if row.step_volumes[s] == nil and s <= State.num_steps then row.step_volumes[s] = v end
      end
      row.step_delays = row.step_delays or {}
      for s, d in pairs(saved.step_delays or {}) do
        if row.step_delays[s] == nil and s <= State.num_steps then row.step_delays[s] = d end
      end

      if type(saved.arp_trigger_notes) == "table" then
        row.arp_trigger_notes = copy_table(saved.arp_trigger_notes)
      end

      if type(saved.visibility) == "table" then
        local vis = State.create_default_visibility()
        for k, v in pairs(saved.visibility) do vis[k] = v end
        State.track_visibility[r] = vis
      end
    end
  end
  print("Persistence: restored settings for " .. #State.sequencer_data .. " rows")
end

---------------------------------------------------------------------------
-- Autosave
---------------------------------------------------------------------------

local last_check = 0

-- Register once at tool load: periodically saves while a session is active
function Persistence.start_autosave()
  renoise.tool().app_idle_observable:add_notifier(function()
    local now = os.time()
    if now - last_check < SAVE_INTERVAL then return end
    last_check = now
    Persistence.save()
  end)

  -- Forget the cached string when a different song is loaded
  renoise.tool().app_new_document_observable:add_notifier(function()
    last_saved = nil
  end)
end

return Persistence
