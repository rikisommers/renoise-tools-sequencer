local vb = renoise.ViewBuilder()

-- Sequencer settings
local num_steps = 8
local num_rows = 4
local current_step = 1
local is_playing = false

-- Grid for storing the current sequencer
local step_grid_view = nil
local sequencer_data = {}
local step_indicators = {}


-- Color definitions
local INACTIVE_COLOR = {80, 80, 80}
local ACTIVE_COLOR = {255, 255, 0}  -- Yellow for active step
local BLOCK_START_COLOR = {99, 99, 99}  -- Light gray for block start

-- Create a row of step indicators
local function create_step_indicators()
  local row = vb:horizontal_aligner{}
    local delayLabel = vb:text{
      width = 100,
      text = "Track Delay:"
  }
  
  local instrumentLabel = vb:text{
      width = 160,
      text = "Sample:"
  }
  
  

--        update_step_count(num_steps)
--        local new_indicators_row = create_step_indicators(num_steps)
--        dialog_content:remove_child(step_indicators_row)
--        dialog_content:add_child(new_indicators_row)  -- Insert at index 2 (after the controls row)
--        step_indicators_row = new_indicators_row
 
 
 
  row:add_child(instrumentLabel)  -- Corrected variable name and removed comma
  step_indicators = {}  -- Clear existing indicators
  for step = 1, num_steps do
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
      local note_value = 48  -- C3 in MIDI note numbers
      local velocity = 100   -- 0-127 range
      
      -- Trigger the sample
      sample:trigger_attack(note_value, velocity)
      
      print("Triggered sample on instrument " .. instrument_index .. " ('" .. instrument.name .. "')")
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
    local note_value = 48 -- C3 in MIDI note numbers

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
        print("Added note C3 on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at tick " .. tick)
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
  print("Set track delay to " .. value)
end



-- Create a row for the sequencer
local function create_step_row(row_index, steps)
  local row = vb:horizontal_aligner{
    
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
    
    vb:popup{
      width = 160,
      items = get_instrument_names(),
      notifier = function(index)
        sequencer_data[row_index].instrument = index
        print("Selected instrument " .. index .. " for row " .. row_index)
      end
    },
  }
  
  for s = 1, steps do
    row:add_child(vb:checkbox{
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



-- Update the number of steps in all rows
local function update_step_count(new_steps)
  if step_grid_view then
    --step_indicators = {}
    --step_grid_view = {}
    --step_grid_view:remove_children()
    --step_grid_view:add_child(create_step_indicators(new_steps))

--local num_steps = 8
--local num_rows = 4
--local current_step = 1
--local is_playing = false

    print("SGV: ", step_grid_view)
    --sequencer_data = {}
    for r = 1, num_rows do

       --  print("SGV: ", step_grid_view)
    
      step_grid_view:add_child(create_step_row(r, new_steps))
      sequencer_data[r] = {instrument = 1, steps = {}}
      for s = 1, new_steps do
        sequencer_data[r].steps[s] = false
      end
    end
  end
end

-- Update step indicators
local function update_step_indicators()
  print("Updating step indicators. Count: " .. #step_indicators)
  local song = renoise.song()
  local current_line = song.transport.playback_pos.line
   print("playing line t: ", current_line)
  for s, indicator in ipairs(step_indicators) do
    if s == current_line then
      indicator.color = ACTIVE_COLOR
    elseif s % 4 == 1 then
      indicator.color = BLOCK_START_COLOR
    else
      indicator.color = INACTIVE_COLOR
    end
  end
end

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
  local step_indicators_row = create_step_indicators(num_steps)
  local dialog_content
  create_step_indicators(num_steps)
  setup_line_change_notifier()


  local controls_row = vb:row{
    vb:text{ text = "Steps:" },
    vb:popup{
      id = "steps_dropdown",
      items = {"8", "16", "32"},
      value = table.find({"8", "16", "32"}, tostring(num_steps)), -- Set the value to match num_steps
      notifier = function(index)
      num_steps = tonumber(vb.views.steps_dropdown.items[index])
        update_step_count(num_steps)
        
        
        if step_grid_view then
         
         step_grid_view = vb:column{}


          print("SGV: ", step_grid_view)
          print("NS: ", num_steps)
          --sequencer_data = {}
          for r = 1, num_rows do
                   print("S: ",r)
            step_grid_view:add_child(create_step_row(r, num_steps))
           
           
            sequencer_data[r] = {instrument = 1, steps = {}} 
            for s = 1, num_steps do
              sequencer_data[r].steps[s] = false
            end
            
          end
        end
  
  
        -- Recreate step indicators when step count changes
        local new_indicators_row = create_step_indicators(num_steps)
        dialog_content:remove_child(step_indicators_row)
        dialog_content:add_child(new_indicators_row)  -- Insert at index 2 (after the controls row)
        step_indicators_row = new_indicators_row
      end
    },
    vb:button{
      text = "Add Row",
      notifier = function()
        num_rows = num_rows + 1
        local new_row_index = #sequencer_data + 1
        step_grid_view:add_child(create_step_row(new_row_index, num_steps))
        sequencer_data[new_row_index] = {instrument = 1, steps = {}}
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
    }
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

