# Requencer
A step sequencer tool for Renoise with pattern integration and MIDI control.

## Features

### Sequencer Grid
- Configurable step count: 8, 16, 32, or 64 steps
- Multiple sequencer rows (tracks)
- 3-state step buttons: Off, Play, Stop
- Visual step indicators showing current playback position

### Note Control
- Per-step note control with rotary dials
- Track-level note (base pitch) control
- Musical scale constraints (Major, Minor, Harmonic Minor, Melodic Minor, modes, Pentatonic, Blues, etc.)
- Key selection (C through B)
- Octave range control (1-4 octaves)
- Automatic scale snapping

### Chord Mode
- Enable chord mode per track
- Multiple chord types: Major, Minor, Diminished, Augmented, 7th chords, Sus2, Sus4
- Automatic note column expansion for chord voicings

### Volume & Dynamics
- Per-step volume control
- Track-level volume control
- Stop notes for cutting sustaining sounds

### Timing & Delay
- Per-step delay (0-255)
- Track-level delay (-100ms to +100ms)

### Instrument & Track Management
- Instrument selection per row
- Auto-refresh instrument dropdowns when instruments change
- Track muting
- Add/remove sequencer rows dynamically
- Clear row or delete row and track
- Track naming based on instrument

### Pattern Integration
- Direct pattern writing at configurable intervals
- Load existing sequencer tracks from pattern
- Clear pattern and sequencer data

### Looping
- Automatic step sequence looping during playback
- Pattern-based looping: sequences repeat every num_steps lines
- Visual playback indicator follows loop position
- Step count independent of pattern length
- Seamless integration with Renoise pattern loop

### Phrase Export
- Save sequencer rows as Renoise phrases
- Preserves notes, volumes, and delays

### UI Features
- Collapsible note, volume, and delay rows per track
- Color-coded controls and step states
- Responsive layout

### MIDI Control
- MIDI mappings for all rotary controls
- Per-row mappings: Track Note, Track Delay, Track Volume
- Per-step mappings: Step Note, Step Volume, Step Delay

## Usage

Access the tool from Renoise menu: **Tools → Requencer**

