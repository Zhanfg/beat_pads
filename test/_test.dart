import 'dart:ui';

import 'package:beat_pads/services/input/multi_touch_note_router.dart';
import 'package:beat_pads/services/input/touch_geometry.dart';
import 'package:beat_pads/services/protocol/axyp_event.dart';
import 'package:beat_pads/services/session/studio_session.dart';
import 'package:flutter_test/flutter_test.dart';

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
