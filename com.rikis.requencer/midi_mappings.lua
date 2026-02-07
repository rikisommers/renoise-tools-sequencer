---------------------------------------------------------------
-- midi_mappings.lua
-- MIDI mapping registration for all sequencer controls.
-- Separated from UI builder so mappings can be managed
-- independently of view construction.
---------------------------------------------------------------

local State = require("state")

local MidiMappings = {}

---------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------

--- Remove all known MIDI mappings to avoid duplicates on dialog reopen.
function MidiMappings.cleanup_all_mappings()
  for r = 1, 20 do
    pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Track Delay") end)
    pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Track Note") end)
    pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Track Volume") end)
    for s = 1, 64 do
      pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Step " .. s .. " Note") end)
      pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Step " .. s .. " Volume") end)
      pcall(function() renoise.tool():remove_midi_mapping("Step Sequencer: Row " .. r .. " Step " .. s .. " Delay") end)
    end
  end
end

---------------------------------------------------------------
-- Track-level mappings (delay, volume, note rotaries)
---------------------------------------------------------------

--- Register MIDI mappings for a track's delay, volume and note rotaries.
-- @param row_index  number
function MidiMappings.register_track_mappings(row_index)
  local vb = State.vb

  -- Track Delay
  local delay_name = "Step Sequencer: Row " .. row_index .. " Track Delay"
  pcall(function() renoise.tool():remove_midi_mapping(delay_name) end)
  renoise.tool():add_midi_mapping{
    name = delay_name,
    invoke = function(message)
      if message:is_abs_value() then
        local val = ((message.int_value / 127) * 200) - 100
        local ctl = vb and vb.views["track_delay_rotary_" .. tostring(row_index)]
        if ctl then ctl.value = val end
      end
    end
  }

  -- Track Volume
  local vol_name = "Step Sequencer: Row " .. row_index .. " Track Volume"
  pcall(function() renoise.tool():remove_midi_mapping(vol_name) end)
  renoise.tool():add_midi_mapping{
    name = vol_name,
    invoke = function(message)
      if message:is_abs_value() then
        local pct = (message.int_value / 127) * 100
        local ctl = vb and vb.views["track_volume_rotary_" .. tostring(row_index)]
        if ctl then ctl.value = pct end
      end
    end
  }

  -- Track Note
  local note_name = "Step Sequencer: Row " .. row_index .. " Track Note"
  pcall(function() renoise.tool():remove_midi_mapping(note_name) end)
  renoise.tool():add_midi_mapping{
    name = note_name,
    invoke = function(message)
      if message:is_abs_value() then
        local pct = (message.int_value / 127) * 100
        local ctl = vb and vb.views["note_rotary_" .. tostring(row_index)]
        if ctl then ctl.value = pct end
      end
    end
  }
end

---------------------------------------------------------------
-- Step-level mappings (note, volume, delay rotaries)
---------------------------------------------------------------

--- Register a MIDI mapping for a per-step note rotary.
-- @param row_index  number
-- @param step       number
function MidiMappings.register_step_note_mapping(row_index, step)
  local vb = State.vb
  local name = "Step Sequencer: Row " .. row_index .. " Step " .. step .. " Note"
  pcall(function() renoise.tool():remove_midi_mapping(name) end)
  renoise.tool():add_midi_mapping{
    name = name,
    invoke = function(message)
      if message:is_abs_value() then
        local pct = (message.int_value / 127) * 100
        local ctl = vb and vb.views["step_note_rotary_" .. tostring(row_index) .. "_" .. tostring(step)]
        if ctl then ctl.value = pct end
      end
    end
  }
end

--- Register a MIDI mapping for a per-step volume rotary.
-- @param row_index  number
-- @param step       number
function MidiMappings.register_step_volume_mapping(row_index, step)
  local vb = State.vb
  local name = "Step Sequencer: Row " .. row_index .. " Step " .. step .. " Volume"
  pcall(function() renoise.tool():remove_midi_mapping(name) end)
  renoise.tool():add_midi_mapping{
    name = name,
    invoke = function(message)
      if message:is_abs_value() then
        local pct = (message.int_value / 127) * 100
        local ctl = vb and vb.views["step_volume_rotary_" .. tostring(row_index) .. "_" .. tostring(step)]
        if ctl then ctl.value = pct end
      end
    end
  }
end

--- Register a MIDI mapping for a per-step delay rotary.
-- @param row_index  number
-- @param step       number
function MidiMappings.register_step_delay_mapping(row_index, step)
  local vb = State.vb
  local name = "Step Sequencer: Row " .. row_index .. " Step " .. step .. " Delay"
  pcall(function() renoise.tool():remove_midi_mapping(name) end)
  renoise.tool():add_midi_mapping{
    name = name,
    invoke = function(message)
      if message:is_abs_value() then
        local val = (message.int_value / 127) * 255
        local ctl = vb and vb.views["step_delay_rotary_" .. tostring(row_index) .. "_" .. tostring(step)]
        if ctl then ctl.value = val end
      end
    end
  }
end

return MidiMappings
