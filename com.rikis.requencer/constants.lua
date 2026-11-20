-- Renoise API provides the 'renoise' global at runtime

local Constants = {}

-- UI Sizing (from Renoise ViewBuilder defaults)
Constants.control_margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
Constants.control_spacing = 1
Constants.control_height = renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT
Constants.control_mini_height = renoise.ViewBuilder.DEFAULT_MINI_CONTROL_HEIGHT
Constants.dialog_margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
Constants.dialog_spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
Constants.button_height = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT
Constants.section_spacing = 8
Constants.row_spacing = 2
Constants.indicator_spacing = 2

-- Step count options
Constants.num_steps_options = {"8", "16", "32", "64"}
Constants.default_pattern = 1
Constants.default_pattern_length = 16

-- Cell sizing
Constants.cellSize = 24
Constants.cellSizeLg = 24 * 4  -- 96

-- Widths of the controls left of the step buttons in the main step row:
-- instrument, chord toggle, arp toggle, chord popup, arp popup,
-- TN, TD, TV, N, V, D, P, R. Sub-rows mirror these slots (same spacing)
-- so every column lines up vertically with the step row.
Constants.LEFT_SLOTS = {
  Constants.cellSizeLg, Constants.cellSize, Constants.cellSize,
  Constants.cellSizeLg, Constants.cellSizeLg,
  Constants.cellSize, Constants.cellSize, Constants.cellSize, Constants.cellSize,
  Constants.cellSize, Constants.cellSize, Constants.cellSize, Constants.cellSize,
}

-- Fixed width of the left control area in every row (step row, sub-rows,
-- header). Wrapping each left area in a container of this width guarantees
-- the step columns start at the same x, even if a Renoise control renders a
-- few px wider/narrower than requested. Includes slack for such differences.
Constants.LEFT_AREA_SLACK = 8
Constants.LEFT_AREA_WIDTH = (function()
  local w = 0
  for _, sw in ipairs(Constants.LEFT_SLOTS) do w = w + sw end
  return w + (#Constants.LEFT_SLOTS - 1) * Constants.control_spacing + Constants.LEFT_AREA_SLACK
end)()

Constants.SLOT_INSTRUMENT  = 1
Constants.SLOT_CHORD_POPUP = 4
Constants.SLOT_ARP_POPUP   = 5

-- Button color palette
Constants.BUTTON_COLOR_ACTIVE = {255, 200, 0}
Constants.BUTTON_COLOR_INACTIVE = {80, 80, 80}
Constants.BUTTON_COLOR_PLAY = {147, 245, 66}
Constants.BUTTON_COLOR_STOP = {245, 66, 93}
Constants.BUTTON_COLOR_WARNING = {245, 194, 66}
Constants.BUTTON_COLOR_HAS_VALUES = {90, 160, 230}  -- sub-row collapsed but holds values

-- Row container styling
Constants.ROW_BACKGROUND_COLOR = {191, 191, 191}
Constants.ROW_PADDING = 4

-- Step indicator colors
Constants.INACTIVE_COLOR = {130, 130, 130}
Constants.ACTIVE_COLOR = {255, 255, 100}
Constants.BLOCK_START_COLOR = {150, 150, 150}

-- Empty step buttons: two tones so beat starts (every LPB steps) stand out
Constants.STEP_EMPTY_COLOR      = {62, 62, 62}
Constants.STEP_EMPTY_BEAT_COLOR = {95, 95, 95}

-- Scale intervals (semitone offsets within one octave)
Constants.SCALE_INTERVALS = {
  ["Chromatic"] = {0,1,2,3,4,5,6,7,8,9,10,11},
  ["Major"] = {0,2,4,5,7,9,11},
  ["Natural Minor"] = {0,2,3,5,7,8,10},
  ["Harmonic Minor"] = {0,2,3,5,7,8,11},
  ["Melodic Minor"] = {0,2,3,5,7,9,11},
  ["Dorian"] = {0,2,3,5,7,9,10},
  ["Phrygian"] = {0,1,3,5,7,8,10},
  ["Lydian"] = {0,2,4,6,7,9,11},
  ["Mixolydian"] = {0,2,4,5,7,9,10},
  ["Locrian"] = {0,1,3,5,6,8,10},
  ["Whole Tone"] = {0,2,4,6,8,10},
  ["Pentatonic Major"] = {0,2,4,7,9},
  ["Pentatonic Minor"] = {0,3,5,7,10},
  ["Blues"] = {0,3,5,6,7,10}
}

-- Key names for scale root selection
Constants.KEY_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

-- Chord type definitions (semitone intervals from root)
-- Piano roll
Constants.PIANO_ROLL_TRIGGER_COLOR = {255, 220, 50}  -- Yellow: arp trigger notes
Constants.PIANO_ROLL_ARP_COLOR     = {80, 150, 255}  -- Blue: generated arp notes
Constants.BUTTON_COLOR_OFF         = {30, 30, 30}    -- Empty cell
Constants.PIANO_ROLL_VISIBLE_ROWS  = 12              -- rows in the scrollable piano roll window
Constants.PIANO_ROLL_OFFSCREEN_COLOR = {60, 110, 40} -- edge marker: step note is above/below the window

-- Note repeat (Renoise Rxy retrigger effect: x = volume change, y = ticks between retriggers)
Constants.REPEAT_EFFECT        = "0R"
Constants.REPEAT_SPEED_OPTIONS = {"R01","R02","R03","R04","R05","R06","R07","R08","R09","R0A","R0B","R0C","R0D","R0E","R0F"}
Constants.REPEAT_DEFAULT_SPEED = 3   -- R03
Constants.REPEAT_STEP_COLOR    = {66, 194, 245}

-- Arp modes
Constants.ARP_MODES = {"up", "down", "updown", "downup", "random"}

Constants.CHORD_TYPES = {
  ["None"] = {},
  ["Major"] = {0, 4, 7},
  ["Minor"] = {0, 3, 7},
  ["Diminished"] = {0, 3, 6},
  ["Augmented"] = {0, 4, 8},
  ["Major 7"] = {0, 4, 7, 11},
  ["Minor 7"] = {0, 3, 7, 10},
  ["Dominant 7"] = {0, 4, 7, 10},
  ["Sus2"] = {0, 2, 7},
  ["Sus4"] = {0, 5, 7}
}

return Constants
