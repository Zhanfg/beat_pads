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
- Material 3 performance deck with adaptive dark color system
- Five persistent scenes backed by the existing preset system
- Scale Lock with Chromatic, Major, Minor, Dorian and Minor Pentatonic modes
- Hardware-pressure Velocity mapping with safe fixed-Velocity fallback
- Two-axis XY control with user-editable X/Y CC assignments
- Four user-editable MIDI CC macro controls for FL Studio Link to controller

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

## 1.2.0 interaction model

Smart-control settings are stored locally. Scale, root note, Scale Lock, Touch Dynamics and CC assignments survive restarts. Scene buttons P1–P5 reuse Midi Poly Grid's existing persistent preset system.

Touch Dynamics uses real pressure data only when the platform reports a usable pressure range. Devices that expose a constant placeholder pressure keep the configured fixed Velocity, avoiding accidental full-velocity notes.

The XY pad defaults to CC74/CC71 and the four macro controls default to CC20–CC23. All six assignments are editable from the controller UI.

## Next implementation targets

- true piano geometry with glissando pointer hand-off
- optional chord/voicing layer
- Mackie/transport protocol experiment behind an opt-in setting
- MIDI receive feedback for motor-style macro state
- latency telemetry and Android USB-specific tuning
