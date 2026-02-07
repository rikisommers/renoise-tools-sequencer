-- MIDI mapping registration and cleanup.

local State = require("state")

local MidiMappings = {}

-- Remove all existing MIDI mappings to avoid duplicates when reopening dialog
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

-- Register MIDI mappings for track-level controls (delay, volume, note)
function MidiMappings.register_track_mappings(row_index)
  local vb = State.vb

  local track_delay_mapping = "Step Sequencer: Row " .. row_index .. " Track Delay"
  pcall(function() renoise.tool():remove_midi_mapping(track_delay_mapping) end)
  renoise.tool():add_midi_mapping{
    name = track_delay_mapping,
    invoke = function(message)
      if (message:is_abs_value()) then
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
        local percentage = (message.int_value / 127) * 100
        local control_id = "note_rotary_" .. tostring(row_index)
        if vb.views[control_id] then
          vb.views[control_id].value = percentage
        end
      end
    end
  }
end

-- Register MIDI mapping for a step note rotary
function MidiMappings.register_step_note_mapping(row_index, step, rotary_id)
  local vb = State.vb
  local mapping_name = "Step Sequencer: Row " .. row_index .. " Step " .. step .. " Note"
  renoise.tool():add_midi_mapping{
    name = mapping_name,
    invoke = function(message)
      if (message:is_abs_value()) then
        local percentage = (message.int_value / 127) * 100
        if vb.views[rotary_id] then
          vb.views[rotary_id].value = percentage
        end
      end
    end
  }
end

-- Register MIDI mapping for a step volume rotary
function MidiMappings.register_step_volume_mapping(row_index, step, rotary_id)
  local vb = State.vb
  local mapping_name = "Step Sequencer: Row " .. row_index .. " Step " .. step .. " Volume"
  renoise.tool():add_midi_mapping{
    name = mapping_name,
    invoke = function(message)
      if (message:is_abs_value()) then
        local percentage = (message.int_value / 127) * 100
        if vb.views[rotary_id] then
          vb.views[rotary_id].value = percentage
        end
      end
    end
  }
end

-- Register MIDI mapping for a step delay rotary
function MidiMappings.register_step_delay_mapping(row_index, step, rotary_id)
  local vb = State.vb
  local mapping_name = "Step Sequencer: Row " .. row_index .. " Step " .. step .. " Delay"
  pcall(function() renoise.tool():remove_midi_mapping(mapping_name) end)
  renoise.tool():add_midi_mapping{
    name = mapping_name,
    invoke = function(message)
      if (message:is_abs_value()) then
        local delay_value = (message.int_value / 127) * 255
        if vb.views[rotary_id] then
          vb.views[rotary_id].value = delay_value
        end
      end
    end
  }
end

return MidiMappings
