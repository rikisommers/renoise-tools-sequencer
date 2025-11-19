# Requencer - MIDI Workflow Guide

## Overview

The Renoise Requencer tool provides comprehensive MIDI mapping support for all controls, allowing you to use hardware MIDI controllers to manipulate the sequencer in real-time. This guide explains how to set up and use MIDI Learn to control your Requencer.

---

## Quick Start: MIDI Learn

### How to Map a MIDI Control

1. **Open Renoise Preferences**
   - macOS: `Renoise → Preferences` or `Cmd + ,`
   - Windows/Linux: `Edit → Preferences` or `Ctrl + ,`

2. **Navigate to MIDI Mapping**
   - Click the **MIDI** tab
   - Select **MIDI Mapping** section

3. **Use MIDI Learn**
   - Click on any mapping name (e.g., "Requencer: Row 1 Track Volume")
   - Move/turn the control on your MIDI controller
   - The mapping is automatically assigned!

4. **Test Your Mapping**
   - The control on your MIDI controller should now directly manipulate the sequencer parameter
   - Real-time control with no latency

---

## Available MIDI Mappings

### Track-Level Controls (Per Row)

Each sequencer row provides three track-level MIDI mappings:

| Mapping Name | Control | Range | Description |
|--------------|---------|-------|-------------|
| `Requencer: Row X Track Note` | Track Note Rotary (TN) | 0-100% | Base pitch for all steps in the row |
| `Requencer: Row X Track Delay` | Track Delay Rotary (TD) | -100 to +100ms | Timing offset for entire track |
| `Requencer: Row X Track Volume` | Track Volume Rotary (TV) | 0-100% | Master volume for entire row |

**Example:** `Requencer: Row 1 Track Volume`
- Maps to the TV rotary on Row 1
- Controls the track's master volume
- 0% = silent, 100% = full volume

---

### Step-Level Controls (Per Step, Per Row)

Each individual step in each row provides three MIDI mappings:

| Mapping Name | Control | Range | Description |
|--------------|---------|-------|-------------|
| `Requencer: Row X Step Y Note` | Step Note Rotary | 0-100% | Individual pitch for this step |
| `Requencer: Row X Step Y Volume` | Step Volume Rotary | 0-127 | Individual volume for this step |
| `Requencer: Row X Step Y Delay` | Step Delay Rotary | 0-255 | Individual timing offset for this step |

**Example:** `Requencer: Row 1 Step 4 Note`
- Maps to the note rotary for Step 4 on Row 1
- Adjusts the pitch of only that specific step
- Respects scale and octave constraints

---

## MIDI Controller Setup Examples

### Example 1: 8-Knob Controller (Volume Control)

Perfect for controlling step volumes on a single row:

```
Row 1, Step 1 Volume → Knob 1
Row 1, Step 2 Volume → Knob 2
Row 1, Step 3 Volume → Knob 3
Row 1, Step 4 Volume → Knob 4
Row 1, Step 5 Volume → Knob 5
Row 1, Step 6 Volume → Knob 6
Row 1, Step 7 Volume → Knob 7
Row 1, Step 8 Volume → Knob 8
```

**Use Case:** Create dynamic volume sequences, accent patterns, or fade effects.

---

### Example 2: Grid Controller (Step Notes)

Use a 4×4 grid controller for melodic step control:

```
Row 1:
  Step 1-4 Notes → Top row (4 encoders)
  Step 5-8 Notes → Second row (4 encoders)
  Step 9-12 Notes → Third row (4 encoders)
  Step 13-16 Notes → Bottom row (4 encoders)
```

**Use Case:** Perform live melodic variations on your drum patterns.

---

### Example 3: DJ Controller (Multi-Row Control)

Use faders and knobs for multiple rows:

```
Faders (Track Volumes):
  Row 1 Track Volume → Fader 1
  Row 2 Track Volume → Fader 2
  Row 3 Track Volume → Fader 3
  Row 4 Track Volume → Fader 4

Knobs (Track Notes/Pitch):
  Row 1 Track Note → Knob 1
  Row 2 Track Note → Knob 2
  Row 3 Track Note → Knob 3
  Row 4 Track Note → Knob 4
```

**Use Case:** Live performance mixing with pitch control.

---

### Example 4: Full Setup (Akai APC-style)

Combine multiple controller types:

```
8 Faders → Row 1, Steps 1-8 Volume
8 Knobs → Row 1, Steps 1-8 Note
8 Endless Encoders → Row 1, Steps 1-8 Delay

4 Large Faders → Rows 1-4 Track Volume
4 Large Knobs → Rows 1-4 Track Note
```

**Use Case:** Complete hands-on control over a single row or multiple rows.

---

## Tips & Best Practices

### 1. **Use Absolute vs. Relative Controls**

- **Absolute knobs/faders**: Best for volume, note pitch
  - Position directly maps to parameter value
  - Visual feedback matches physical position

- **Endless encoders**: Great for delay, fine-tuning
  - Rotate infinitely for precise adjustments
  - No "jump" when parameter doesn't match knob position

### 2. **Organize by Row**

Map one row completely before moving to the next:
```
Row 1 Complete Setup → Test → Row 2 Setup → Test → etc.
```

### 3. **Save Your Mapping**

Renoise saves MIDI mappings automatically, but you can:
- Export your mapping configuration
- Document your setup for quick reference
- Share setups with collaborators

### 4. **Use Templates**

Create mapping templates for common workflows:
- **Template A**: Volume-focused (all step volumes)
- **Template B**: Melody-focused (all step notes)
- **Template C**: Timing-focused (all step delays)
- **Template D**: Track-level mix control

### 5. **Combine with Pattern Commands**

Use MIDI control + Renoise pattern commands for:
- **0Vxx** - Volume slide while MIDI adjusts base volume
- **Uxx** - Delay effects combined with step delays
- **01xx/02xx** - Pitch slides on top of MIDI note changes

---

## MIDI Mapping Technical Details

### MIDI Value Ranges

The tool automatically scales MIDI CC values to appropriate ranges:

| Parameter Type | MIDI Input | Output Range | Conversion |
|----------------|------------|--------------|------------|
| Track Volume | 0-127 | 0-100% | `(midi / 127) × 100` |
| Track Note | 0-127 | 0-100% | `(midi / 127) × 100` |
| Track Delay | 0-127 | -100 to +100ms | `((midi / 127) × 200) - 100` |
| Step Volume | 0-127 | 0-127 | Direct pass-through |
| Step Note | 0-127 | 0-100% | `(midi / 127) × 100` |
| Step Delay | 0-127 | 0-255 | `(midi / 127) × 255` |

### MIDI Message Types

The tool responds to:
- ✅ **Control Change (CC)** messages
- ✅ **Absolute values** (standard knobs/faders)
- ❌ Note On/Off (not supported for mappings)
- ❌ Program Change (not supported)

### Mapping Name Format

All mappings follow consistent naming:
```
"Requencer: Row [ROW_NUMBER] [CONTROL_TYPE]"
"Requencer: Row [ROW_NUMBER] Step [STEP_NUMBER] [CONTROL_TYPE]"
```

Examples:
- `Requencer: Row 1 Track Volume`
- `Requencer: Row 2 Step 5 Note`
- `Requencer: Row 3 Track Delay`

---

## Troubleshooting

### MIDI Control Not Working?

1. **Check MIDI Input Device**
   - Preferences → MIDI → Inputs
   - Ensure your device is enabled

2. **Verify Mapping**
   - Preferences → MIDI → MIDI Mapping
   - Look for your mapping in the list
   - Re-learn if necessary

3. **Check for Conflicts**
   - Ensure the same CC isn't mapped to multiple parameters
   - Remove duplicate mappings

4. **Test with Renoise's Built-in Tools**
   - Try mapping to a native Renoise parameter first
   - If that works, the issue is tool-specific

### Parameter Not Responding Correctly?

1. **Check Value Range**
   - Some controls have specific ranges (e.g., 0-100 vs 0-127)
   - MIDI input is automatically scaled

2. **Rotary vs. Absolute**
   - Ensure your controller sends absolute values
   - Relative/incremental encoders need specific CC modes

3. **Timing Issues**
   - MIDI learn captures the first message received
   - Ensure you're moving the correct control

---

## Advanced Workflows

### Live Performance Setup

1. **Row Assignment**
   - Row 1: Kick drum pattern
   - Row 2: Snare/clap pattern  
   - Row 3: Hi-hat pattern
   - Row 4: Percussion/effects

2. **Controller Mapping**
   - 4 Faders → Track volumes (mix control)
   - 16 Knobs → Step 1-16 volumes on Row 3 (hi-hat dynamics)
   - 4 Encoders → Track notes (pitch variations)

3. **Performance Technique**
   - Use faders for build-ups/breakdowns
   - Adjust hi-hat volumes for groove variations
   - Pitch shift drums for transitions

### Studio Production Setup

1. **Detailed Step Control**
   - Map all 16 step volumes for Row 1
   - Map all 16 step notes for Row 1
   - Use for precise drum programming

2. **Multi-Row Orchestration**
   - Map 4 track volumes to 4 faders
   - Map 4 track notes to 4 knobs
   - Control multiple patterns simultaneously

---

## Recommended MIDI Controllers

### Budget-Friendly
- **Korg nanoKONTROL2** - 8 faders, 8 knobs, compact
- **Akai LPD8** - 8 pads, 8 knobs, portable

### Mid-Range
- **Novation Launch Control** - Grid layout, good for step sequencing
- **Behringer X-Touch Mini** - Compact, lots of controls

### Professional
- **Akai APC40 MKII** - Full grid + faders + knobs
- **Novation Launch Control XL** - Extensive control surface

---

## Resources

- **Renoise Manual**: [MIDI Mapping Documentation](https://tutorials.renoise.com/wiki/MIDI_Mapping)
- **Forum**: [Renoise Tools Forum](https://forum.renoise.com/c/tool-development/)
- **Tool Source**: `main.lua` (lines 1384-1422 for track mappings, 1577+ for step mappings)

---

## Support

For issues or questions:
1. Check this documentation first
2. Review the Renoise MIDI Mapping manual
3. Test with native Renoise controls
4. Post in the Renoise Tools forum with:
   - Your MIDI controller model
   - Renoise version
   - Specific mapping that's not working
   - Error messages (if any)

---

**Happy Sequencing! 🎵**

