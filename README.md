# Requencer
A step sequencer tool for Renoise with pattern integration and MIDI control.
This provides similar functionality to Paketti Groovebox 8120 but with more fine-grained control over note, volume and delay per step.

## Supported Renoise Versions
- Renoise 3.4
- Renoise 3.5


## USE CASES

### Drum Programming
One of my main goals in making this was to allow for more humanized programming of drums.
When programming drums I often add delay to individual tracks and notes to create a 'groove' effect. This allows for a more human feel rather than the global groove which produces a very noticeable garage-esque swing but not so great for more subtle effects.
Note offset can be applied per track and per individual step.

### Chord Programming
Chord mode can be enabled per track to allow for more complex chord progressions.
Chord types: Major, Minor, Diminished, Augmented, 7th chords, Sus2, Sus4
Automatic note column expansion for chord voicings.

### External Hardware
I also wanted to be able to control steps via hardware similar to an analog step sequencer.
All steps including the base note, volume and delay can be controlled via MIDI.
This means you can turn any boolean or rotary MIDI controller into a step sequencer via Renoise.
I have tested using a BCR2000 and it works great for controlling external synths with some one-time MIDI config required.
Note that it does pay to save your MIDI config as a preset to avoid having to reconfigure your hardware every time you start Renoise.

### Exploratory Programming
Save sequences as phrases and use them in other patterns or as a standalone instrument.
Seaquenbces can also be loaded from the pattern via pattern sync.
So if you save your sequence as a phrase you can load it back into the pattern via pattern sync later.

## Similar tools
I would recommend having a look at [Paketti Groovebox 8120](https://www.perplexity.ai/search/in-the-renoise-tools-porttal-h-nG_CVo4yTbal6BF_L.mH9g) which provides features like track delay Probability, randomize and automation utils alongside a tonne of other features.


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
- Octave range control (1-4 octaves) - this limits the track and individual step rotary range.
- Automatic scale snapping

### Chord Mode
- Enable chord mode per track
- Multiple chord types: Major, Minor, Diminished, Augmented, 7th chords, Sus2, Sus4

### Volume & Dynamics
- Per-step volume control
- Track-level volume control
- Stop notes for cutting sustaining sounds (samples only)

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
- Direct pattern writing at configurable intervals - if sequencing 8 steps in a 64 step pattern the 8 steps will be duplicated 8 times in the pattern.
- Load existing sequencer tracks from pattern
- Clear pattern and sequencer data

### Phrase Export
- Save sequencer rows as Renoise phrases, this allows you to use the phrases in other patterns or as a standalone instrument.

### MIDI Control
- MIDI mappings for all step state ( play, stop, off) & rotary controls
- Per-row mappings: Track Note, Track Delay, Track Volume
- Per-step mappings: Step Note, Step Volume, Step Delay


## Usage
Access the tool from Renoise menu: **Tools → Requencer**


## Bugs
There are a few bugs that I am aware of and will be fixed in the future.
If you find any bugs, please let me know. 