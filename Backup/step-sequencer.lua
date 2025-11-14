local vb = renoise.ViewBuilder()

-- Sequencer settings
local num_steps = 8
local num_rows = 4

-- Grid for storing the current sequencer state
local sequencer_data = {}

-- Initialize sequencer data for each row
local function initialize_sequencer_data()
  for r = 1, num_rows do
    if not sequencer_data[r] then
      sequencer_data[r] = {
        instrument = 1,  -- Default to first instrument
        steps = {}
      }
      for s = 1, num_steps do
        sequencer_data[r].steps[s] = false
      end
    end
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

    -- Calculate the line index based on the step and loop every num_steps
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
        print("Added note C3 on instrument " .. (instrument_index + 1) .. " in track " .. track_index .. " at line " .. line_index)
      else
        -- Remove the note
        note_column.note_value = 121 -- 121 represents an empty note
        note_column.instrument_value = 255 -- 255 represents no instrument
        note_column.volume_value = 255 -- 255 represents no volume change
        print("Removed note in track " .. track_index .. " at line " .. line_index)
      end
    end
  else
    print("No instrument data for row " .. row_index)
  end
end

-- Create a grid for the sequencer
local function create_step_grid(steps, rows)
  local grid = vb:row{}
  for r = 1, rows do
    local row = vb:horizontal_aligner{}
    for s = 1, steps do
      row:add_child(vb:checkbox{
        id = "checkbox_" .. tostring(r) .. "_" .. tostring(s),
        value = sequencer_data[r] and sequencer_data[r].steps[s] or false,
        tooltip = "Step " .. s,
        notifier = function(new_value)
          -- Update sequencer data
          if not sequencer_data[r] then
            sequencer_data[r] = {instrument = 1, steps = {}}
          end
          sequencer_data[r].steps[s] = new_value
          
          -- Add or remove note in pattern based on checkbox state
          update_note_in_pattern(r, s, new_value)
        end
      })
    end
    grid:add_child(row)
  end
  return grid
end

-- Create the main dialog window
local function show_sequencer_dialog()
  -- Initialize sequencer data before creating UI
  initialize_sequencer_data()
  
  renoise.app():show_custom_dialog("Step Sequencer", vb:column{
    vb:row{
      vb:text{
        text = "Steps:",
      },
      vb:popup{
        id = "steps_dropdown",
        items = {"8", "16", "32"},
        value = 1,
        notifier = function(index)
          -- Adjust steps based on selection
          local new_steps = tonumber(vb.views.steps_dropdown.items[index])
          if new_steps then
            num_steps = new_steps
          end
          -- Update sequencer data structure for new step count
          for r = 1, num_rows do
            if sequencer_data[r] then
              -- Extend or truncate steps array
              local old_steps = sequencer_data[r].steps
              sequencer_data[r].steps = {}
              for s = 1, num_steps do
                sequencer_data[r].steps[s] = old_steps[s] or false
              end
            end
          end
        end
      }
    },
    vb:row{
      vb:button{
        text = "Add Row",
        notifier = function()
          num_rows = num_rows + 1
          -- Initialize new row data
          sequencer_data[num_rows] = {instrument = 1, steps = {}}
          for s = 1, num_steps do
            sequencer_data[num_rows].steps[s] = false
          end
        end
      }
    },
    create_step_grid(num_steps, num_rows)
  })
end

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Step Sequencer",
  invoke = show_sequencer_dialog
}
