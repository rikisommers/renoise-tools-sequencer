-- Arpeggiator: generates note sequences from per-step trigger notes
-- and writes them into the Renoise pattern.

local State         = require("state")
local MusicTheory   = require("music_theory")
local PatternWriter = require("pattern_writer")

local Arp = {}

-- Generate and write arp notes for one row.
-- Also updates step_states/step_notes to reflect arp output.
function Arp.apply_to_row(row_index)
  local row = State.sequencer_data[row_index]
  if not row or not row.arp_enabled then return end

  -- Generate sequence
  local arp_notes = MusicTheory.generate_arp_sequence(
    row.arp_trigger_notes or {},
    row.arp_mode          or "up",
    State.num_steps,
    State.global_scale_mode,
    State.global_scale_key
  )

  row.arp_notes = arp_notes

  -- Apply to pattern: trigger steps keep trigger note; arp-filled steps get generated note
  for s = 1, State.num_steps do
    local trigger_note = row.arp_trigger_notes and row.arp_trigger_notes[s]
    local arp_note     = arp_notes[s]

    if trigger_note then
      -- Trigger step — write trigger note (already set in step_notes/step_states by click handler)
      PatternWriter.update_step_note_in_pattern(row_index, s, trigger_note)
    elseif arp_note then
      -- Arp-filled step
      row.step_states[s] = 1
      row.step_notes[s]  = arp_note
      PatternWriter.update_step_note_in_pattern(row_index, s, arp_note)
    else
      -- No note at this step
      row.step_states[s] = 0
      row.step_notes[s]  = nil
      PatternWriter.clear_step_from_pattern(row_index, s)
    end
  end

  -- Refresh piano roll colors (lazy require avoids circular dep at load time)
  local PianoRoll = require("piano_roll")
  PianoRoll.update_display(row_index)
  require("sub_rows").refresh_indicators(row_index)
end

-- Regenerate arp for all rows that have arp enabled
function Arp.refresh_all()
  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row and row.arp_enabled then
      Arp.apply_to_row(r)
    end
  end
end

return Arp
