# AXYP/1 — Axymorrsen eXtensible Performance Protocol

AXYP is the internal performance event protocol used by the mobile instrument core. Touch surfaces publish AXYP events once; MIDI, local audio and future desktop/network bridges consume the same event stream.

## Design goals

- pointer-aware from the start, so every finger can have independent note ownership;
- transport-neutral: the same event model can feed local audio, MIDI, USB, BLE or a future network bridge;
- versioned and binary-framed;
- monotonically sequenced and timestamped;
- small fixed header with explicit payload length for forward-compatible extensions.

## Binary frame

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | Magic ASCII `AXYP` |
| 4 | 1 | Protocol version, currently `1` |
| 5 | 1 | Event type |
| 6 | 1 | MIDI-style channel 0–15 |
| 7 | 1 | Flags, reserved in v1 |
| 8 | 4 | Sequence number, big-endian |
| 12 | 8 | Timestamp in microseconds, big-endian |
| 20 | 4 | Signed pointer ID, `-1` for generated/non-touch events |
| 24 | 2 | Payload length, big-endian |
| 26 | n | Event payload |

## Event types

1. Note On — note, velocity, percussive flag
2. Note Off — note
3. Control — controller, value
4. Pitch — signed 16-bit normalized bend
5. Sustain — enabled
6. Transport — controller, pressed/released
7. Panic — no payload

## Routing

`PerformanceRouter` is the single runtime boundary. UI code must not send MIDI or local-audio commands directly. Generated instruments such as the arpeggiator also enter through the router, using pointer ID `-1`.

Physical touch instruments use `MultiTouchNoteRouter`, which owns the mapping:

`pointerId -> note`

and reference-counts notes. Two fingers may therefore hold different notes as a chord, or even share one note without an early Note Off. Moving one finger performs a clean per-pointer Note Off / Note On transition, enabling glissando without affecting the other fingers.

## Extension rules

- Existing event type codes and field semantics are immutable within v1.
- New optional behavior should use flags or new event types.
- A receiver must reject unknown protocol versions rather than guessing.
- Future network/desktop bridges should preserve sequence, timestamp and pointer ID unchanged.
- MIDI is an output adapter, not the canonical internal representation.
