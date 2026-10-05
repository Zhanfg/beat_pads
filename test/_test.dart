import 'dart:ui';

import 'package:beat_pads/services/input/multi_touch_note_router.dart';
import 'package:beat_pads/services/input/touch_geometry.dart';
import 'package:beat_pads/services/protocol/axyp_event.dart';
import 'package:beat_pads/services/protocol/midi_note_gate.dart';
import 'package:beat_pads/services/session/studio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MultiTouchNoteRouter', () {
    test('keeps independent fingers active for chords and glissando', () {
      final on = <String>[];
      final off = <String>[];
      final router = MultiTouchNoteRouter(
        onNoteOn: (
          int note, {
          int? velocity,
          required int pointerId,
        }) {
          on.add('$pointerId:$note:${velocity ?? -1}');
        },
        onNoteOff: (int note, {required int pointerId}) {
          off.add('$pointerId:$note');
        },
      );

      router.down(11, 60, velocity: 90);
      router.down(22, 64, velocity: 100);

      expect(router.activeNotes, <int>{60, 64});
      expect(on, <String>['11:60:90', '22:64:100']);

      router.move(11, 62, velocity: 95);

      expect(router.activeNotes, <int>{62, 64});
      expect(off, contains('11:60'));
      expect(on, contains('11:62:95'));

      router.up(22);
      router.up(11);
      expect(router.activeNotes, isEmpty);
    });

    test('keeps the original voice pointer until the shared note ends', () {
      final offPointers = <int>[];
      final router = MultiTouchNoteRouter(
        onNoteOn: (
          int note, {
          int? velocity,
          required int pointerId,
        }) {},
        onNoteOff: (int note, {required int pointerId}) {
          offPointers.add(pointerId);
        },
      );

      router.down(31, 60);
      router.down(42, 60);
      router.up(31);
      router.up(42);

      expect(offPointers, <int>[31]);
    });

    test('does not release a shared note until its final owner leaves', () {
      int noteOnCount = 0;
      int noteOffCount = 0;
      final router = MultiTouchNoteRouter(
        onNoteOn: (
          int note, {
          int? velocity,
          required int pointerId,
        }) {
          noteOnCount++;
        },
        onNoteOff: (int note, {required int pointerId}) {
          noteOffCount++;
        },
      );

      router.down(1, 60);
      router.down(2, 60);
      expect(noteOnCount, 1);

      router.up(1);
      expect(noteOffCount, 0);

      router.up(2);
      expect(noteOffCount, 1);
    });
  });


  group('TouchViewportPolicy', () {
    test('does not cram 25 notes into a portrait phone', () {
      expect(
        TouchViewportPolicy.pianoNoteCount(const Size(690, 1200)),
        17,
      );
      expect(
        TouchViewportPolicy.pianoNoteCount(const Size(390, 820)),
        13,
      );
      expect(
        TouchViewportPolicy.pianoNoteCount(const Size(1200, 600)),
        31,
      );
    });

    test('maps a fretboard point without per-cell gesture listeners', () {
      const geometry = FretboardGeometry(
        size: Size(700, 480),
        stringCount: 6,
        firstFret: 0,
        visibleFretCount: 8,
      );

      expect(geometry.stringAt(const Offset(100, 20)), 0);
      expect(geometry.stringAt(const Offset(100, 470)), 5);
      expect(geometry.fretAt(const Offset(20, 100)), isNull);
      expect(geometry.fretAt(const Offset(60, 100)), 0);
      expect(geometry.fretAt(const Offset(699, 100)), 7);
    });
  });

  group('StudioSession', () {
    test('records AXYP note timing into a playable clip', () async {
      final session = StudioSession();
      session.startRecording();

      session.ingest(
        const AxypNoteOn(
          sequence: 1,
          timestampMicros: 1,
          channel: 0,
          pointerId: 8,
          note: 60,
          velocity: 105,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      session.ingest(
        const AxypNoteOff(
          sequence: 2,
          timestampMicros: 2,
          channel: 0,
          pointerId: 8,
          note: 60,
        ),
      );
      session.stopRecording();

      expect(session.clip.notes, hasLength(1));
      expect(session.clip.notes.single.note, 60);
      expect(session.clip.notes.single.velocity, 105);
      expect(session.clip.notes.single.durationMicros, greaterThan(0));
      expect(session.clip.lengthMicros, greaterThan(0));
      session.dispose();
    });
  });

  group('Workstation project', () {
    test('supports multiple tracks and deterministic undo redo', () {
      final session = StudioSession();
      final piano = session.addTrack(
        instrumentId: 'keyboard',
        name: '钢琴',
      );
      session.addNoteToSelectedClip(
        note: 60,
        startMicros: 0,
        durationMicros: 120000,
        velocity: 96,
      );
      final bass = session.addTrack(
        instrumentId: 'bass',
        name: '贝斯',
      );
      session.addNoteToSelectedClip(
        note: 36,
        startMicros: 0,
        durationMicros: 120000,
        velocity: 104,
      );

      expect(session.project.tracks, hasLength(2));
      expect(session.project.tracks.first.id, piano);
      expect(session.project.tracks.last.id, bass);
      expect(session.project.tracks.first.clips.single.notes.single.note, 60);
      expect(session.project.tracks.last.clips.single.notes.single.note, 36);

      session.undo();
      expect(session.project.tracks.last.clips, isEmpty);
      session.redo();
      expect(session.project.tracks.last.clips.single.notes.single.note, 36);
      session.dispose();
    });

    test('autosaves and restores the project graph', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      final writer = StudioSession(storage: prefs);
      writer.addTrack(
        instrumentId: 'keyboard',
        name: '主钢琴',
      );
      writer.addNoteToSelectedClip(
        note: 64,
        startMicros: 24000,
        durationMicros: 96000,
        velocity: 111,
      );
      writer.setTrackVolume(writer.selectedTrack!.id, 0.82);
      await Future<void>.delayed(const Duration(milliseconds: 240));
      writer.dispose();

      final reader = StudioSession(storage: prefs);
      expect(reader.project.tracks, hasLength(1));
      expect(reader.project.tracks.single.name, '主钢琴');
      expect(reader.project.tracks.single.volume, closeTo(0.82, 0.001));
      expect(reader.project.tracks.single.clips.single.notes.single.note, 64);
      expect(
        reader.project.tracks.single.clips.single.notes.single.velocity,
        111,
      );
      reader.dispose();
    });

    test('stores multiple named projects in the library', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final session = StudioSession(storage: prefs);

      session.newProject(name: 'A');
      session.addTrack(instrumentId: 'keyboard', name: '钢琴 A');
      session.saveProjectAs('A');

      session.newProject(name: 'B');
      session.addTrack(instrumentId: 'bass', name: '贝斯 B');
      session.saveProjectAs('B');

      expect(session.savedProjectNames, <String>['A', 'B']);
      expect(session.loadProject('A'), isTrue);
      expect(session.project.name, 'A');
      expect(session.project.tracks.single.name, '钢琴 A');

      session.deleteSavedProject('B');
      expect(session.savedProjectNames, <String>['A']);
      session.dispose();
    });

    test('splits and trims clips without corrupting crossing notes', () {
      final session = StudioSession();
      session.addTrack(instrumentId: 'keyboard');
      session.addNoteToSelectedClip(
        note: 60,
        startMicros: 0,
        durationMicros: 300000,
        velocity: 100,
      );
      session.addNoteToSelectedClip(
        note: 64,
        startMicros: 200000,
        durationMicros: 200000,
        velocity: 100,
      );

      final sourceLength = session.selectedClip!.lengthMicros;
      expect(sourceLength, 400000);

      session.splitSelectedClipAt(250000);
      expect(session.selectedTrack!.clips, hasLength(2));

      final left = session.selectedTrack!.clips.first;
      final right = session.selectedTrack!.clips.last;
      expect(left.lengthMicros, 250000);
      expect(right.startMicros, 250000);
      expect(left.notes, hasLength(2));
      expect(right.notes, hasLength(2));
      expect(left.notes.first.durationMicros, 250000);
      expect(right.notes.first.startMicros, 0);

      session.selectClip(right.id);
      session.trimSelectedClipStart(50000);
      expect(session.selectedClip!.startMicros, 300000);
      expect(session.selectedClip!.lengthMicros, 100000);

      session.trimSelectedClipEnd(25000);
      expect(session.selectedClip!.lengthMicros, 75000);
      session.dispose();
    });

    test('quantize transpose and velocity edit mutate actual notes', () {
      final session = StudioSession();
      session.addTrack(instrumentId: 'keyboard');
      session.addNoteToSelectedClip(
        note: 60,
        startMicros: 133000,
        durationMicros: 121000,
        velocity: 90,
      );

      session.quantizeSelectedClip(division: 16);
      session.transposeSelectedClip(2);
      session.changeSelectedVelocity(10);

      final note = session.selectedClip!.notes.single;
      expect(note.note, 62);
      expect(note.velocity, 100);
      expect(note.startMicros % 125000, 0);
      expect(note.durationMicros % 125000, 0);
      session.dispose();
    });
  });

  group('MidiNoteGate', () {
    test('holds a MIDI note until the final AXYP owner releases it', () {
      final gate = MidiNoteGate();
      expect(gate.acquire(0, 60), isTrue);
      expect(gate.acquire(0, 60), isFalse);
      expect(gate.ownersOf(0, 60), 2);

      expect(gate.release(0, 60), isFalse);
      expect(gate.ownersOf(0, 60), 1);
      expect(gate.release(0, 60), isTrue);
      expect(gate.ownersOf(0, 60), 0);
    });
  });
  group('AXYP/1', () {
    test('round-trips pointer-aware NoteOn frames', () {
      const event = AxypNoteOn(
        sequence: 42,
        timestampMicros: 123456789,
        channel: 3,
        pointerId: 77,
        note: 64,
        velocity: 111,
        percussive: false,
      );

      final frame = AxypCodec.encode(event);
      expect(frame.take(4), <int>[0x41, 0x58, 0x59, 0x50]);
      expect(frame[4], AxypCodec.version);
      expect(frame.length, AxypCodec.headerLength + 3);

      final decoded = AxypCodec.decode(frame);
      expect(decoded, isA<AxypNoteOn>());
      final note = decoded as AxypNoteOn;
      expect(note.sequence, 42);
      expect(note.timestampMicros, 123456789);
      expect(note.channel, 3);
      expect(note.pointerId, 77);
      expect(note.note, 64);
      expect(note.velocity, 111);
    });

    test('rejects malformed frame lengths', () {
      const event = AxypPanic(
        sequence: 1,
        timestampMicros: 2,
        channel: 0,
      );
      final frame = AxypCodec.encode(event);
      expect(
        () => AxypCodec.decode(frame.sublist(0, frame.length - 1)),
        throwsFormatException,
      );
    });
  });
}
