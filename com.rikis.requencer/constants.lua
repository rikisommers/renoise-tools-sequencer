---------------------------------------------------------------
-- constants.lua
-- All static configuration: UI sizing, colors, music data.
-- Returns a single read-only table.
---------------------------------------------------------------

local C = {}

-- UI sizing (Renoise ViewBuilder defaults)
C.CONTROL_MARGIN  = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
C.CONTROL_SPACING = 1
C.CONTROL_HEIGHT  = renoise.ViewBuilder.DEFAULT_CONTROL_HEIGHT
C.CONTROL_MINI_HEIGHT = renoise.ViewBuilder.DEFAULT_MINI_CONTROL_HEIGHT
C.DIALOG_MARGIN   = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
C.DIALOG_SPACING  = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
C.BUTTON_HEIGHT   = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT

C.SECTION_SPACING   = 8   -- Between major sections (controls, indicators, grid)
C.ROW_SPACING       = 2   -- Between sequencer rows
C.INDICATOR_SPACING = 2   -- Between step indicators and first row

C.NUM_STEPS_OPTIONS = {"8", "16", "32", "64"}
C.DEFAULT_PATTERN_LENGTH = 16
C.CELL_SIZE    = 24
C.CELL_SIZE_LG = 24 * 4  -- cellSize * 4

-- Button color constants (matching Renoise theme)
C.BUTTON_COLOR_ACTIVE   = {255, 200, 0}    -- Yellow/orange
C.BUTTON_COLOR_INACTIVE = {80, 80, 80}     -- Gray
C.BUTTON_COLOR_PLAY     = {147, 245, 66}   -- Green
C.BUTTON_COLOR_STOP     = {245, 66, 93}    -- Red
C.BUTTON_COLOR_WARNING  = {245, 194, 66}   -- Orange
C.BUTTON_COLOR_OFF      = {40, 40, 40}     -- Dark gray (step off)
C.BUTTON_COLOR_DARK     = {30, 30, 30}     -- Near black (utility buttons)

-- Row container styling
C.ROW_BACKGROUND_COLOR = {191, 191, 191}
C.ROW_PADDING = 4

-- Step indicator colors
C.INACTIVE_COLOR    = {130, 130, 130}  -- Light gray
C.ACTIVE_COLOR      = {255, 255, 100}  -- Light yellow for active step
C.BLOCK_START_COLOR = {150, 150, 150}  -- Lighter gray for block start

-- Track color for newly created sequencer tracks
C.TRACK_COLOR = {0x60, 0xC0, 0xFF}

-- Scale intervals (semitone offsets within one octave)
C.SCALE_INTERVALS = {
  ["Chromatic"]       = {0,1,2,3,4,5,6,7,8,9,10,11},
  ["Major"]           = {0,2,4,5,7,9,11},
  ["Natural Minor"]   = {0,2,3,5,7,8,10},
  ["Harmonic Minor"]  = {0,2,3,5,7,8,11},
  ["Melodic Minor"]   = {0,2,3,5,7,9,11},
  ["Dorian"]          = {0,2,3,5,7,9,10},
  ["Phrygian"]        = {0,1,3,5,7,8,10},
  ["Lydian"]          = {0,2,4,6,7,9,11},
  ["Mixolydian"]      = {0,2,4,5,7,9,10},
  ["Locrian"]         = {0,1,3,5,6,8,10},
  ["Whole Tone"]      = {0,2,4,6,8,10},
  ["Pentatonic Major"] = {0,2,4,7,9},
  ["Pentatonic Minor"] = {0,3,5,7,10},
  ["Blues"]            = {0,3,5,6,7,10},
}

-- Key names for scale root selection
C.KEY_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

-- Chord definitions (semitone intervals from root)
C.CHORD_TYPES = {
  ["None"]       = {},
  ["Major"]      = {0, 4, 7},
  ["Minor"]      = {0, 3, 7},
  ["Diminished"] = {0, 3, 6},
  ["Augmented"]  = {0, 4, 8},
  ["Major 7"]    = {0, 4, 7, 11},
  ["Minor 7"]    = {0, 3, 7, 10},
  ["Dominant 7"] = {0, 4, 7, 10},
  ["Sus2"]       = {0, 2, 7},
  ["Sus4"]       = {0, 5, 7},
}

return C
