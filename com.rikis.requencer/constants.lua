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

-- Button color palette
Constants.BUTTON_COLOR_ACTIVE = {255, 200, 0}
Constants.BUTTON_COLOR_INACTIVE = {80, 80, 80}
Constants.BUTTON_COLOR_PLAY = {147, 245, 66}
Constants.BUTTON_COLOR_STOP = {245, 66, 93}
Constants.BUTTON_COLOR_WARNING = {245, 194, 66}

-- Row container styling
Constants.ROW_BACKGROUND_COLOR = {191, 191, 191}
Constants.ROW_PADDING = 4

-- Step indicator colors
Constants.INACTIVE_COLOR = {130, 130, 130}
Constants.ACTIVE_COLOR = {255, 255, 100}
Constants.BLOCK_START_COLOR = {150, 150, 150}

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
