# Mobile Workstation Architecture

## Product direction

The project is no longer treated as a single MIDI-controller screen. The target is a standalone mobile music workstation that can also act as a low-latency FL Studio companion.

## Runtime layers

1. **Touch Surfaces** — keyboard, fretboards, drums, chord strips, Smart Drums and sequencers.
2. **Input Core** — raw pointer ownership, multi-touch, pressure and instrument-specific gestures.
3. **AXYP/1** — canonical timestamped performance events independent from MIDI and audio.
4. **Session** — clips, timeline, recording, future Piano Roll/quantize/automation/project persistence.
5. **Audio** — local synth today; multi-sampler, SF2/SFZ, sample cache and FX graph next.
6. **Adapters** — USB/BLE/virtual MIDI, FL Studio mappings, future desktop/network AXYP bridges.

## Workspace model

### Instrument
The low-latency play surface. Each instrument owns its performance ergonomics.

### Tracks
Timeline and clips. 1.7.0 begins with a real AXYP-recorded note clip. The target is multi-track regions, Piano Roll, quantize, loop, trim and automation.

### Mixer
Track/master routing. The current functional controls live here first; the target is per-track volume/pan/mute/solo, sends, insert FX and master limiting.

### Browser
Instrument/content selection. The target is searchable instruments, user samples, SF2/SFZ banks, drum kits, loops and presets.

## Orientation policy

Portrait and landscape are not scaled copies.

- **Portrait:** fewer, wider touch targets and bottom workspace navigation.
- **Landscape:** larger performance viewport, side navigation and more simultaneous controls.
- **Keyboard landscape gestures:** Glissando, Scroll and Pitch are separate modes.
- **Fretboards:** paging and raw hit-testing avoid scroll-view conflicts with multi-touch.

## Capability targets

### Performance
- [x] polyphonic multi-touch keyboard
- [x] adaptive portrait keyboard
- [x] landscape full-range navigation
- [x] Glissando / Scroll / Pitch keyboard modes
- [x] multi-touch guitar and bass fretboards
- [x] drum pads
- [x] chords / arpeggiator / smart drums / step sequencer / live loops
- [ ] guitar/bass chord strips, autoplay and string bending
- [ ] strings family and articulation engine
- [ ] instrument-specific sound presets and controls

### Session / editing
- [x] AXYP note capture
- [x] local clip recording and playback
- [x] multi-track project graph
- [x] Piano Roll editing
- [x] quantize / transpose / velocity editing
- [x] clip move / duplicate / delete / real loop playback
- [ ] clip trim / split
- [x] undo/redo history
- [ ] automation lanes
- [x] multi-project save/load and autosave

### Audio
- [x] standalone low-latency local output
- [ ] production multi-sampler
- [ ] user sample import
- [ ] SF2 / SFZ
- [ ] microphone / line recording
- [ ] time stretching
- [ ] track FX / sends
- [ ] master limiter
- [ ] offline render/export

### External integration
- [x] MIDI output
- [x] safe overlapping-note ownership when AXYP voices degrade to MIDI 1.0
- [x] FL Studio learnable transport CCs
- [x] AXYP wire framing
- [ ] desktop AXYP companion
- [ ] bidirectional MIDI feedback
- [ ] DAW-specific scripts/profiles

## Development release semantics

- 1.8.x is a development line and is not a declaration that the first product release is complete.
- The first user-approved release will be renamed to 0.9.0.
- A green CI build proves the branch builds and its automated invariants pass; it does not substitute for product acceptance or OnePlus 13 hardware validation.
- Controls are only exposed as completed when they affect the runtime. For example, track pan was intentionally removed until a real per-track audio bus exists.

## 1.8 minimum closed-loop baseline

The minimum closed loop is: create project → add tracks → perform/record → edit notes/clips → arrange → basic mix → play → save/load multiple projects → resume after restart.
