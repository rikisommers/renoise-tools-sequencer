local vb = renoise.ViewBuilder()

-- Sequencer settings
local num_steps = 8
local num_rows = 4

-- Create a grid for the sequencer
local function create_step_grid(steps, rows)
  local grid = vb:row{}
  for r = 1, rows do
    local row = vb:horizontal_aligner{}
    for s = 1, steps do
      row:add_child(vb:checkbox{
        value = false,
        tooltip = "Step " .. s
      })
    end
    grid:add_child(row)
  end
  return grid
end

-- Create the main dialog window
local function show_sequencer_dialog()
  renoise.app():show_custom_dialog("Step Sequencer", vb:column{
    vb:row{
      vb:text{
        text = "Steps:",
      },
      vb:popup{
        items = {"8", "16", "32"},
        value = 1,
        notifier = function(value)
          -- Adjust steps based on selection
          num_steps = tonumber(vb.views.steps_dropdown.items[value])
        end
      }
    },
    vb:row{
      vb:button{
        text = "Add Row",
        notifier = function()
          num_rows = num_rows + 1
          -- Add additional row
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
