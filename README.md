# audionerd/acid

a tb-303-style sequencer for crow + x0x-heart + grid

influenced by [“Analysis of the µPD650C-133 CPU timing”](https://sonic-potions.com/Documentation/Analysis_of_the_D650C-133_CPU_timing.pdf)

designed for use with the open source [x0x-heart + pacemaker](http://openmusiclabs.com/projects/x0x-heart)

## sequencing

![monome grid](acid.svg)

`playhead` row shows current step during playback, and a cursor for the currently selected step when editing.

for each step:
- `gate/accent` can be off, gate on, or accent on
- `slide` can be off or on
- `up`/`down` set the octave of the note

hold `meta` and select a `gate/accent` step to immediately turn it off.

`left/right` moves the cursor between steps. the `keyboard` will display the note assigned to the step, which can be changed by pressing a `keyboard` key.

## future
- save/load patterns
- range selection
- crow "satellite" mode (allow continued playback disconnected from norns, re-connect to edit pattern)
- random pattern generation
- MIDI out support
