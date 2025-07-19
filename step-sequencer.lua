local vb = renoise.ViewBuilder()

local control_margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
local control_spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
local control_height = renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT
local control_mini_height = renoise.ViewBuilder.DEFAULT_MINI_CONTROL_HEIGHT
local dialog_margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
local dialog_spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
local button_height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT

local num_steps_options = {"8", "16", "32", "64"}
local pattern = renoise.song().selected_pattern_index
local patternLength = renoise.song().patterns[pattern].number_of_lines






-- Sequencer settings
local num_steps = patternLength
local num_rows = 4
local current_step = 1
local is_playing = false

-- Grid for storing the current sequencer
local step_grid_view = nil
local sequencer_data = {}
local step_indicators = {}
step_indicators_row = nil  -- Declare as a global variable

-- Color definitions
local INACTIVE_COLOR = {80, 80, 80}
local ACTIVE_COLOR = {255, 255, 0}  -- Yellow for active step
local BLOCK_START_COLOR = {99, 99, 99}  -- Light gray for block start

-- NEW FUNCTION: Create default track group and add all tracks
local function setup_default_track_group()
  
  -- Create new group at position 1
  local new_group = renoise.song():insert_group_at(1)

  -- Set group name
  if new_group then
    new_group.name = "Sequencer"
  end
end

-- -- Initialize default group when tool starts
setup_default_track_group()

-- Create a row of step indicators
local function create_step_indicators(steps)


  
  local row = vb:horizontal_aligner{}
    local trackDelayLabel = vb:text{
      width = 40,
      text = "TDel"
      
  }
  local noteLabel = vb:text{
    width = 40,
    text = "Note"
  }
  local noteDelayLabel = vb:text{
    width = 40,
    text = "NDel:"
  }
  
  local instrumentLabel = vb:text{
      width = 100,
      text = "Inst"
  }
  
  

--        update_step_count(num_steps)
--        local new_indicators_row = create_step_indicators(num_steps)
--        dialog_content:remove_child(step_indicators_row)
--        dialog_content:add_child(new_indicators_row)  -- Insert at index 2 (after the controls row)
--        step_indicators_row = new_indicators_row
 
 
   row:add_child(trackDelayLabel)
   row:add_child(noteLabel)
   row:add_child(noteDelayLabel)
  row:add_child(instrumentLabel)  -- Corrected variable name and removed comma
 -- step_indicators = {}  -- Clear existing indicators
  for step = 1, steps do
    local indicator = vb:button{
      width = 18,
      height = 18,
      color = (step % 4 == 1) and BLOCK_START_COLOR or INACTIVE_COLOR,
      active = false
    }
    row:add_child(indicator)
    table.insert(step_indicators, indicator)
  end
  return row
end


-- Function to trigger a sample for a specific row
local function trigger_sample(row_index)
  local data = sequencer_data[row_index]
  if data and data.instrument then
    local instrument_index = data.instrument
    local instrument = renoise.song().instruments[instrument_index]
    
    -- Check if the instrument has samples
    if #instrument.samples > 0 then
      local sample = instrument.samples[1]  -- Trigger the first sample in the instrument
      local note_value = data.note_value or 48  -- Use dynamic note value or default to C3
      local velocity = 100   -- 0-127 range
      
      -- Trigger the sample
      sample:trigger_attack(note_value, velocity)
      
      print("Triggered sample on instrument " .. instrument_index .. " ('" .. instrument.name .. "') with note " .. note_value)
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
  local row = vb:horizontal_aligner{
    
      vb:rotary{
        id = "track_delay_rotary_" .. tostring(row_index),  -- Unique ID for track delay rotary
        min = -100,  -- Minimum delay value
        max = 100,   -- Maximum delay value
        value = 0,   -- Initialize with 0
        width = 40,  -- Set width of the rotary control
        notifier = function(value)
          -- Update the track delay
          update_delay_value(value)
        end
      },
      vb:rotary{
        id = "note_rotary_" .. tostring(row_index),  -- Unique ID for note rotary
        min = 0,     -- 0% (C1)
        max = 100,   -- 100% (C6)
        value = 50,  -- 50% (C3 default)
        width = 40,  -- Set width of the rotary control
        notifier = function(value)
          -- Convert percentage to MIDI note value (24-96 range)
          local note_value = math.floor(24 + (value / 100) * (96 - 24))
          
          -- Update the note value for this row
          sequencer_data[row_index].note_value = note_value
          
          -- Update all existing notes in the pattern for this track
          local song = renoise.song()
          local current_pattern_index = song.selected_pattern_index
          local pattern_track = song:pattern(current_pattern_index):track(row_index)
          
          for line_index = 1, song.patterns[current_pattern_index].number_of_lines do
            local line = pattern_track:line(line_index)
            local note_column = line:note_column(1)
            
            -- If there's a note in this line, update its pitch
            if note_column.note_value < 121 then  -- 121 means empty note
              note_column.note_value = note_value
            end
          end
          
          print("Set note value to " .. note_value .. " (" .. value .. "%) for row " .. row_index)
        end
      },
      
      vb:rotary{
        id = "note_delay_rotary_" .. tostring(row_index),  -- Unique ID for note delay rotary
        min = 0,     -- Minimum note delay value
        max = 255,   -- Maximum note delay value (Renoise uses 0-255 for note delay)
        value = 0,   -- Initialize with 0
        width = 40,  -- Set width of the rotary control
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
        width = 100,
        items = get_instrument_names(),
        notifier = function(index)
          sequencer_data[row_index].instrument = index
          print("Selected instrument " .. index .. " for row " .. row_index)
        end
      },
  }
  
  for s = 1, steps do
    row:add_child(vb:checkbox{
      id = "checkbox_" .. tostring(row_index) .. "_" .. tostring(s),  -- Unique ID for each checkbox
      value = false,
      notifier = function(new_value)
        local old_value = sequencer_data[row_index].steps[s]
        sequencer_data[row_index].steps[s] = new_value
        
        print("Checkbox changed:")
        print("  Row: " .. row_index)
        print("  Step: " .. s)
        print("  Old value: " .. tostring(old_value))
        print("  New value: " .. tostring(new_value))
        
        -- Add or remove note based on checkbox state
        update_note_in_pattern(row_index, s, new_value)
      end
    })
  end
  
  return row
end



-- Get names of all instruments
function get_instrument_names()
  local names = {}
  for i, instrument in ipairs(renoise.song().instruments) do
    table.insert(names, i .. ": " .. instrument.name)
  end
  return names
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
local function clear_notes_outside_range(new_steps)
  local song = renoise.song()
  local current_pattern_index = song.selected_pattern_index
  local pattern = song:pattern(current_pattern_index)
  
  -- Loop through all tracks and clear notes outside the new step range
  for track_index = 1, #song.tracks do
    local pattern_track = pattern:track(track_index)
    
    -- Clear notes that are outside the new step range
    for line_index = 1, pattern.number_of_lines do
      local current_step = ((line_index - 1) % num_steps) + 1
      
      if current_step > new_steps then
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
-- Create the main dialog window
local function show_sequencer_dialog()
  step_grid_view = vb:column{}
  step_indicators_row = create_step_indicators(num_steps)  -- Assign to the global variable

  create_step_indicators(num_steps)
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
    if step_grid_view then
      -- Clear existing step rows to prevent ID conflicts
      -- Remove all children individually since remove_children() doesn't exist
      while #step_grid_view.children > 0 do
        step_grid_view:remove_child(step_grid_view.children[1])
      end
      
      -- Clear notes outside of the new step range in the pattern
      clear_notes_outside_range(new_steps)
      
      -- Update step indicators row
      if step_indicators_row and dialog_content then
        step_indicators = {}  -- Clear existing indicators array
        
        -- Create a new row of step indicators based on the updated number of steps
        local new_indicators_row = create_step_indicators(new_steps)
        dialog_content:remove_child(step_indicators_row)
        dialog_content:add_child(new_indicators_row)  -- Add the new indicators row
        step_indicators_row = new_indicators_row  -- Update the reference
      end
      
      -- Reset sequencer data
      sequencer_data = {}
      
      -- Create new step rows with the updated step count
      for r = 1, num_rows do
        step_grid_view:add_child(create_step_row(r, new_steps))
        sequencer_data[r] = {instrument = 1, note_value = 48, steps = {}}
        for s = 1, new_steps do
          sequencer_data[r].steps[s] = false
        end
      end
      
      print("Updated sequencer to " .. new_steps .. " steps")
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
          -- Create a new track after the group
          local new_track_index = sequencer_group_index + 1
          song:insert_track_at(new_track_index)
          
          -- Add the new track to the Sequencer group
          song:add_track_to_group(new_track_index, sequencer_group_index)
          
          print("Added new track " .. new_track_index .. " to Sequencer group at index " .. sequencer_group_index)
        else
          print("Sequencer group not found!")
        end
        
        -- Update sequencer UI
        num_rows = num_rows + 1
        local new_row_index = #sequencer_data + 1
        step_grid_view:add_child(create_step_row(new_row_index, num_steps))
        sequencer_data[new_row_index] = {instrument = 1, note_value = 48, steps = {}}
        for s = 1, num_steps do
          sequencer_data[new_row_index].steps[s] = false
        end
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
  }

  dialog_content = vb:column{
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

  renoise.app():show_custom_dialog("Step Sequencer", dialog_content)
end

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Step Sequencer",
  invoke = show_sequencer_dialog
}



