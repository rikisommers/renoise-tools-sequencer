-- Arpeggiator: generates note sequences from per-step trigger notes.

local State         = require("state")
local MusicTheory   = require("music_theory")
local PatternWriter = require("pattern_writer")

local Arp = {}

function Arp.apply_to_row(row_index)
  local row = State.sequencer_data[row_index]
  if not row or not row.arp_enabled then return end

  local arp_notes = MusicTheory.generate_arp_sequence(
    row.arp_trigger_notes or {},
    row.arp_mode          or "up",
    State.num_steps,
    State.global_scale_mode,
    State.global_scale_key
  )
  row.arp_notes = arp_notes

  for s = 1, State.num_steps do
    local trigger_note = row.arp_trigger_notes and row.arp_trigger_notes[s]
    local arp_note     = arp_notes[s]

    if trigger_note then
      PatternWriter.update_step_note_in_pattern(row_index, s, trigger_note)
    elseif arp_note then
      row.step_states[s] = 1
      row.step_notes[s]  = arp_note
      PatternWriter.update_step_note_in_pattern(row_index, s, arp_note)
    else
      row.step_states[s] = 0
      row.step_notes[s]  = nil
      PatternWriter.clear_step_from_pattern(row_index, s)
    end
  end

  local PianoRoll = require("piano_roll")
  PianoRoll.update_display(row_index)
end

function Arp.refresh_all()
  for r = 1, #State.sequencer_data do
    local row = State.sequencer_data[r]
    if row and row.arp_enabled then
      Arp.apply_to_row(r)
    end
  end
end

return Arp
