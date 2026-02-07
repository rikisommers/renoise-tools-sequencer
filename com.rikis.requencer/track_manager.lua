---------------------------------------------------------------
-- track_manager.lua
-- Renoise track lifecycle: create, delete, map, mute, chord,
-- visibility toggles, phrase saving, instrument list.
---------------------------------------------------------------

local Constants     = require("constants")
local MusicTheory   = require("music_theory")
local State         = require("state")
local PatternWriter = require("pattern_writer")

local TrackManager = {}

---------------------------------------------------------------
-- Track mapping helpers
---------------------------------------------------------------

--- Get the actual Renoise track index for a sequencer row.
-- @param row_index  number
-- @return number
function TrackManager.get_track_index_for_row(row_index)
  return State.track_mapping[row_index] or row_index
end

--- Rebuild the track_mapping table by scanning for Sequencer_ tracks.
-- Also cleans up orphaned tracks that have no matching data row.
function TrackManager.rebuild_track_mapping()
  local song = renoise.song()
  State.track_mapping = {}

  local seq_track_count = 0
  for i = 1, #song.tracks do
    if song.tracks[i].name:match("^Sequencer_") then
      seq_track_count = seq_track_count + 1
      State.track_mapping[seq_track_count] = i
      print("Mapped row " .. seq_track_count .. " to track " .. i .. " (" .. song.tracks[i].name .. ")")
    end
  end

  -- Clean up orphaned tracks
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

    -- Rebuild after cleanup
    State.track_mapping = {}
    seq_track_count = 0
    for i = 1, #song.tracks do
      if song.tracks[i].name:match("^Sequencer_") then
        seq_track_count = seq_track_count + 1
        State.track_mapping[seq_track_count] = i
        print("Re-mapped row " .. seq_track_count .. " to track " .. i .. " (" .. song.tracks[i].name .. ")")
      end
    end
  end
end

--- Find the last sequencer-type track index (before send/master tracks).
-- @return number
function TrackManager.find_last_sequencer_track_index()
  local song = renoise.song()
  local last_index = 0
  local has_seq_tracks = false

  for i = 1, #song.tracks do
    local track = song.tracks[i]
    if track.name:match("^Sequencer_") then
      has_seq_tracks = true
      last_index = i
    elseif (track.type == renoise.Track.TRACK_TYPE_SEQUENCER or
            track.type == renoise.Track.TRACK_TYPE_GROUP) then
      if not has_seq_tracks then
        last_index = i
      end
    end
  end

  if last_index == 0 then
    last_index = song.selected_track_index
  end
  return last_index
end

---------------------------------------------------------------
-- Track creation
---------------------------------------------------------------

--- Create default Renoise tracks for all current sequencer rows.
function TrackManager.setup_default_track_group()
  local song = renoise.song()
  print("=== Starting setup_default_track_group ===")

  local insert_pos = 1
  for i = 1, #song.tracks do
    if song.tracks[i].type == renoise.Track.TRACK_TYPE_SEQUENCER then
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
    track.color = Constants.TRACK_COLOR
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

---------------------------------------------------------------
-- Row removal
---------------------------------------------------------------

--- Clear a sequencer row (pattern notes + reset state + UI buttons).
-- Does NOT delete the Renoise track.
-- @param row_index  number
function TrackManager.remove_sequencer_row(row_index)
  if not State.sequencer_data[row_index] then
    print("ERROR: Row " .. row_index .. " doesn't exist")
    return
  end

  local song = renoise.song()
  local track_index = TrackManager.get_track_index_for_row(row_index)
  local pattern = song:pattern(song.selected_pattern_index)

  if track_index and track_index <= #song.tracks then
    local pt = pattern:track(track_index)
    for line_index = 1, pattern.number_of_lines do
      pt:line(line_index):clear()
    end
    print("Cleared all pattern notes for row " .. row_index .. " (track " .. track_index .. ")")
  end

  State.sequencer_data[row_index].step_states  = {}
  State.sequencer_data[row_index].step_notes   = {}
  State.sequencer_data[row_index].step_volumes = {}
  for s = 1, State.num_steps do
    State.sequencer_data[row_index].step_states[s] = 0
  end

  local vb = State.vb
  for s = 1, State.num_steps do
    local btn_id = "step_button_" .. tostring(row_index) .. "_" .. tostring(s)
    if vb and vb.views[btn_id] then
      vb.views[btn_id].text  = "   "
      vb.views[btn_id].color = {80, 80, 80}
    end
  end

  print("Cleared row " .. row_index .. " (pattern and steps reset)")
end

--- Remove a row AND delete the associated Renoise track.
-- Rebuilds mapping and reopens the dialog.
-- @param row_index  number
function TrackManager.remove_sequencer_row_and_track(row_index)
  if not State.sequencer_data[row_index] then
    print("ERROR: Row " .. row_index .. " doesn't exist")
    return
  end

  local song = renoise.song()
  local track_index = TrackManager.get_track_index_for_row(row_index)

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

  State:remove_row(row_index)

  -- Rebuild track mapping
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

  print("Updated num_rows to " .. State.num_rows)

  -- Close and reopen dialog to refresh UI
  if State.dialog and State.dialog.visible then
    State.dialog:close()
    if State.show_sequencer_dialog then
      State.show_sequencer_dialog()
    end
  end
end

---------------------------------------------------------------
-- Mute / unmute
---------------------------------------------------------------

--- Update the mute button colour to reflect the current track mute state.
-- @param row_index  number
function TrackManager.update_mute_button_color(row_index)
  local track_index = TrackManager.get_track_index_for_row(row_index)
  if not track_index then return end

  local song = renoise.song()
  if track_index > #song.tracks then return end

  local vb = State.vb
  local track = song.tracks[track_index]
  local btn_id = "mute_button_" .. tostring(row_index)

  if vb and vb.views[btn_id] then
    local is_muted = (track.mute_state == renoise.Track.MUTE_STATE_MUTED or
                      track.mute_state == renoise.Track.MUTE_STATE_OFF)
    vb.views[btn_id].color = is_muted and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end
end

--- Toggle mute on the Renoise track for a row.
-- @param row_index  number
function TrackManager.toggle_track_mute(row_index)
  local track_index = TrackManager.get_track_index_for_row(row_index)
  if not track_index then return end

  local song = renoise.song()
  local track = song.tracks[track_index]
  if not track then return end

  local is_muted = (track.mute_state == renoise.Track.MUTE_STATE_MUTED or
                    track.mute_state == renoise.Track.MUTE_STATE_OFF)
  if is_muted then
    track:unmute()
  else
    track:mute()
  end
  TrackManager.update_mute_button_color(row_index)
end

---------------------------------------------------------------
-- Visibility toggles
---------------------------------------------------------------

local function ensure_visibility(row_index)
  if not State.track_visibility[row_index] then
    State.track_visibility[row_index] = {note_visible = false, volume_visible = false, delay_visible = false}
  end
end

function TrackManager.toggle_note_row_visibility(row_index)
  ensure_visibility(row_index)
  local vis = State.track_visibility[row_index]
  vis.note_visible = not vis.note_visible

  if State.track_note_rows[row_index] then
    State.track_note_rows[row_index].visible = vis.note_visible
  end

  local vb = State.vb
  local toggle_id = "note_toggle_" .. tostring(row_index)
  if vb and vb.views[toggle_id] then
    vb.views[toggle_id].color = vis.note_visible and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end
  print("Note row " .. row_index .. " visibility: " .. tostring(vis.note_visible))
end

function TrackManager.toggle_volume_row_visibility(row_index)
  ensure_visibility(row_index)
  local vis = State.track_visibility[row_index]
  vis.volume_visible = not vis.volume_visible

  if State.track_volume_rows[row_index] then
    State.track_volume_rows[row_index].visible = vis.volume_visible
  end

  local vb = State.vb
  local toggle_id = "volume_toggle_" .. tostring(row_index)
  if vb and vb.views[toggle_id] then
    vb.views[toggle_id].color = vis.volume_visible and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end
  print("Volume row " .. row_index .. " visibility: " .. tostring(vis.volume_visible))
end

function TrackManager.toggle_delay_row_visibility(row_index)
  ensure_visibility(row_index)
  local vis = State.track_visibility[row_index]
  vis.delay_visible = not vis.delay_visible

  if State.track_delay_rows[row_index] then
    State.track_delay_rows[row_index].visible = vis.delay_visible
  end

  local track_index = TrackManager.get_track_index_for_row(row_index)
  local song = renoise.song()
  if track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      track.delay_column_visible = vis.delay_visible
    end
  end

  local vb = State.vb
  local toggle_id = "delay_toggle_" .. tostring(row_index)
  if vb and vb.views[toggle_id] then
    vb.views[toggle_id].color = vis.delay_visible and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end
  print("Delay row " .. row_index .. " visibility: " .. tostring(vis.delay_visible))
end

---------------------------------------------------------------
-- Chord track toggle
---------------------------------------------------------------

--- Toggle chord mode on a sequencer row, adjusting note columns and patterns.
-- @param row_index  number
function TrackManager.toggle_chord_track(row_index)
  if not State.sequencer_data[row_index] then return end

  local data = State.sequencer_data[row_index]
  local is_chord = data.is_chord_track
  data.is_chord_track = not is_chord

  local vb = State.vb

  -- Update chord toggle button
  local toggle_id = "chord_toggle_" .. tostring(row_index)
  if vb and vb.views[toggle_id] then
    vb.views[toggle_id].color = (not is_chord) and Constants.BUTTON_COLOR_ACTIVE or Constants.BUTTON_COLOR_INACTIVE
  end

  -- Enable/disable chord popup
  local popup_id = "chord_popup_" .. tostring(row_index)
  if vb and vb.views[popup_id] then
    vb.views[popup_id].active = not is_chord
  end

  -- Update track note columns
  local song = renoise.song()
  local track_index = TrackManager.get_track_index_for_row(row_index)

  if track_index <= #song.tracks then
    local track = song.tracks[track_index]
    if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      if not is_chord then
        -- Chord mode enabled
        local chord_type = data.chord_type or "None"
        local chord_intervals = Constants.CHORD_TYPES[chord_type]
        if chord_intervals and #chord_intervals > 0 then
          track.visible_note_columns = math.max(1, math.min(12, #chord_intervals))
        else
          track.visible_note_columns = 1
        end
      else
        -- Chord mode disabled
        track.visible_note_columns = 1
      end

      -- Update all active steps
      for s = 1, State.num_steps do
        if data.step_states and data.step_states[s] then
          if data.step_states[s] == 1 then
            local note_to_use = data.step_notes and data.step_notes[s] or data.note_value
            PatternWriter.update_step_note_in_pattern(row_index, s, note_to_use)
          elseif data.step_states[s] == 2 then
            PatternWriter.update_note_in_pattern(row_index, s, false)
            PatternWriter.update_step_volume_in_pattern(row_index, s, 0)
          end
        end
      end
    end
  end

  print("Chord track " .. row_index .. " enabled: " .. tostring(not is_chord))
end

---------------------------------------------------------------
-- Save row as phrase
---------------------------------------------------------------

--- Save a sequencer row as a Renoise instrument phrase.
-- @param row_index  number
-- @return number|nil  phrase index
function TrackManager.save_row_as_phrase(row_index)
  local data = State.sequencer_data[row_index]
  if not data or not data.instrument then
    print("No data to save for row " .. row_index)
    return
  end

  local vb = State.vb
  local song = renoise.song()
  local instrument = song.instruments[data.instrument]

  local phrase_index = #instrument.phrases + 1
  local new_phrase = instrument:insert_phrase_at(phrase_index)
  new_phrase.number_of_lines = State.num_steps
  new_phrase.lpb = 1

  -- Read delay values from UI controls
  local track_delay = 0
  local note_delay  = 0
  if vb then
    local td_ctl = vb.views["track_delay_rotary_" .. tostring(row_index)]
    local nd_ctl = vb.views["note_delay_rotary_" .. tostring(row_index)]
    if td_ctl then track_delay = td_ctl.value end
    if nd_ctl then note_delay = math.floor(nd_ctl.value) end
  end

  for s = 1, State.num_steps do
    if data.step_states and data.step_states[s] and data.step_states[s] > 0 then
      local line = new_phrase:line(s)
      local nc = line:note_column(1)

      local note_to_use = data.note_value
      if data.step_notes and data.step_notes[s] then
        note_to_use = data.step_notes[s]
      end

      local volume_to_use = 127
      if data.step_volumes and data.step_volumes[s] then
        volume_to_use = data.step_volumes[s]
      end

      nc.note_value       = note_to_use
      nc.instrument_value = data.instrument - 1
      nc.volume_value     = volume_to_use
      nc.delay_value      = note_delay

      if track_delay ~= 0 then
        local ec = line:effect_column(1)
        ec.number_string = "0D"
        ec.amount_value  = math.abs(track_delay)
      end
    end
  end

  new_phrase.name = "Seq Row " .. row_index .. " (" .. instrument.name .. ")"
  print("Saved row " .. row_index .. " as phrase: " .. new_phrase.name)
  return phrase_index
end

---------------------------------------------------------------
-- Instrument list helpers
---------------------------------------------------------------

--- Get names of all instruments, prefixed with 1-based index.
-- @return table  Array of strings like "1: Kick"
function TrackManager.get_instrument_names()
  local names = {}
  for i, instrument in ipairs(renoise.song().instruments) do
    table.insert(names, i .. ": " .. instrument.name)
  end
  return names
end

--- Refresh all instrument dropdown items, preserving selections.
function TrackManager.refresh_instrument_dropdowns()
  local vb = State.vb
  local updated_names = TrackManager.get_instrument_names()

  for r = 1, #State.sequencer_data do
    local popup_id = "instrument_popup_" .. tostring(r)
    if vb and vb.views[popup_id] then
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

---------------------------------------------------------------
-- Apply global note constraints to all rows
---------------------------------------------------------------

--- Re-constrain all row notes and per-step notes to current scale/range.
-- Updates both state and UI rotaries + pattern data.
function TrackManager.apply_global_note_constraints()
  if not State.sequencer_data then return end

  local vb = State.vb

  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row then
      local base = row.base_note_value or 48
      local min_note, max_note = MusicTheory.compute_note_range(base, State.global_octave_range)

      local constrained = MusicTheory.snap_to_scale(
        MusicTheory.clamp_note(row.note_value or base),
        min_note, max_note, State.global_scale_mode, State.global_scale_key
      )
      row.note_value = constrained

      local rotary_id = "note_rotary_" .. tostring(r)
      if vb and vb.views[rotary_id] then
        vb.views[rotary_id].value = MusicTheory.note_to_percentage(constrained, base, State.global_octave_range)
      end

      -- Per-step notes
      if row.step_notes then
        for s, n in pairs(row.step_notes) do
          local new_n = MusicTheory.snap_to_scale(
            MusicTheory.clamp_note(n), min_note, max_note,
            State.global_scale_mode, State.global_scale_key
          )
          row.step_notes[s] = new_n
          local sr_id = "step_note_rotary_" .. tostring(r) .. "_" .. tostring(s)
          if vb and vb.views[sr_id] then
            vb.views[sr_id].value = MusicTheory.note_to_percentage(new_n, base, State.global_octave_range)
          end
          if row.step_states and row.step_states[s] and row.step_states[s] == 1 then
            PatternWriter.update_step_note_in_pattern(r, s, new_n)
          end
        end
      end

      -- Steps using track note (no per-step override)
      if row.step_states then
        for s = 1, State.num_steps do
          if row.step_states[s] and row.step_states[s] == 1 and (not row.step_notes or not row.step_notes[s]) then
            PatternWriter.update_step_note_in_pattern(r, s, constrained)
          end
        end
      end

      -- Mirror scale to instrument trigger options
      if row.instrument and row.instrument >= 1 and row.instrument <= #renoise.song().instruments then
        local inst = renoise.song().instruments[row.instrument]
        if State.global_scale_mode ~= "None" then
          pcall(function()
            inst.trigger_options.scale_mode = State.global_scale_mode
            inst.trigger_options.scale_key  = State.global_scale_key
          end)
        end
      end
    end
  end
end

return TrackManager
