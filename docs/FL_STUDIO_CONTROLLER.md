# FL Studio Controller mode

This branch adds a dedicated low-latency performance surface on top of Midi Poly Grid's existing MIDI stack.

## What is included

- 25-note multi-touch chromatic keyboard with octave shifting
- 4x4 FPC/drum pad bank with 16-note bank shifting
- Pitch bend, modulation wheel and sustain controls
- MIDI panic / all-notes-off
- Connected MIDI-device status
- Five learnable transport controls for FL Studio
- Existing USB/Bluetooth MIDI device drawer remains available

## FL Studio setup

1. Connect the Android device by USB MIDI or another MIDI transport supported by the app.
2. In FL Studio, open **Options > MIDI settings**.
3. Enable the input exposed by the phone/MIDI bridge.
4. Use the keyboard and drum pads as normal note input.
5. For transport controls, map these momentary CC messages once in FL Studio:

| Control | CC |
| --- | ---: |
| Record | 110 |
| Play | 111 |
| Stop | 112 |
| Loop | 113 |
| Metronome | 114 |

The controller sends value 127 on press and 0 shortly after release/trigger.

## Design notes

The FL Studio workspace intentionally reuses the existing `flutter_midi_command` send path rather than adding a parallel transport layer. That keeps note, pitch, CC and sustain traffic on the same tested path as the existing pad/MPE modes and avoids additional buffering.

The existing Midi Poly Grid workflow remains unchanged. The FL Studio screen is an additive workspace reachable from the piano icon in the main menu.

## Next implementation targets

- true piano geometry with glissando pointer hand-off
- pressure/area-derived velocity when available
- user-editable CC map and saved FL profiles
- Mackie/transport protocol experiment behind an opt-in setting
- latency telemetry and Android USB-specific tuning
