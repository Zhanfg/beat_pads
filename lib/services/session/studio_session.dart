import 'dart:async';

import 'package:beat_pads/services/protocol/axyp_event.dart';
import 'package:flutter/foundation.dart';

final class RecordedNote {
  const RecordedNote({
    required this.note,
    required this.velocity,
    required this.startMicros,
    required this.durationMicros,
  });

  final int note;
  final int velocity;
  final int startMicros;
  final int durationMicros;

  int get endMicros => startMicros + durationMicros;
}

final class StudioClip {
  const StudioClip({
    required this.notes,
    required this.lengthMicros,
  });

  final List<RecordedNote> notes;
  final int lengthMicros;

  bool get isEmpty => notes.isEmpty;
}

final class _PendingNote {
  const _PendingNote({
    required this.note,
    required this.velocity,
    required this.startMicros,
  });

  final int note;
  final int velocity;
  final int startMicros;
}

/// Minimal local session timeline.
///
/// AXYP is the source of truth: recording consumes protocol events rather than
/// reaching back into widgets. That keeps future Piano Roll, quantize, export
/// and network recording independent from the touch UI.
final class StudioSession extends ChangeNotifier {
  final Map<String, _PendingNote> _pending = <String, _PendingNote>{};
  final List<RecordedNote> _recordingNotes = <RecordedNote>[];
  final List<Timer> _playbackTimers = <Timer>[];

  StudioClip _clip = const StudioClip(
    notes: <RecordedNote>[],
    lengthMicros: 0,
  );
  bool _recording = false;
  bool _playing = false;
  int _recordStartMicros = 0;

  StudioClip get clip => _clip;
  bool get recording => _recording;
  bool get playing => _playing;

  void startRecording() {
    stopPlayback();
    _recording = true;
    _recordStartMicros = DateTime.now().microsecondsSinceEpoch;
    _pending.clear();
    _recordingNotes.clear();
    notifyListeners();
  }

  void stopRecording() {
    if (!_recording) return;
    final now = _relativeNow();

    for (final pending in _pending.values) {
      _recordingNotes.add(
        RecordedNote(
          note: pending.note,
          velocity: pending.velocity,
          startMicros: pending.startMicros,
          durationMicros: (now - pending.startMicros).clamp(1000, now).toInt(),
        ),
      );
    }
    _pending.clear();

    _recordingNotes.sort(
      (a, b) => a.startMicros.compareTo(b.startMicros),
    );
    final length = _recordingNotes.fold<int>(
      0,
      (current, note) => note.endMicros > current ? note.endMicros : current,
    );
    _clip = StudioClip(
      notes: List<RecordedNote>.unmodifiable(_recordingNotes),
      lengthMicros: length,
    );
    _recording = false;
    notifyListeners();
  }

  void clear() {
    stopPlayback();
    _pending.clear();
    _recordingNotes.clear();
    _clip = const StudioClip(
      notes: <RecordedNote>[],
      lengthMicros: 0,
    );
    _recording = false;
    notifyListeners();
  }

  void ingest(AxypEvent event) {
    if (!_recording) return;

    switch (event) {
      case AxypNoteOn e:
        final key = _key(e.pointerId, e.note);
        _pending[key] = _PendingNote(
          note: e.note,
          velocity: e.velocity,
          startMicros: _relativeNow(),
        );
        break;
      case AxypNoteOff e:
        final key = _key(e.pointerId, e.note);
        final pending = _pending.remove(key);
        if (pending == null) return;
        final end = _relativeNow();
        _recordingNotes.add(
          RecordedNote(
            note: pending.note,
            velocity: pending.velocity,
            startMicros: pending.startMicros,
            durationMicros:
                (end - pending.startMicros).clamp(1000, end).toInt(),
          ),
        );
        break;
      default:
        break;
    }
  }

  void play({
    required void Function(int note, int velocity) noteOn,
    required void Function(int note) noteOff,
  }) {
    if (_clip.isEmpty) return;

    stopPlayback();
    _playing = true;
    notifyListeners();

    for (final note in _clip.notes) {
      _playbackTimers.add(
        Timer(
          Duration(microseconds: note.startMicros),
          () => noteOn(note.note, note.velocity),
        ),
      );
      _playbackTimers.add(
        Timer(
          Duration(microseconds: note.endMicros),
          () => noteOff(note.note),
        ),
      );
    }

    _playbackTimers.add(
      Timer(
        Duration(microseconds: _clip.lengthMicros + 2000),
        () {
          _playing = false;
          _playbackTimers.clear();
          notifyListeners();
        },
      ),
    );
  }

  void stopPlayback() {
    for (final timer in _playbackTimers) {
      timer.cancel();
    }
    _playbackTimers.clear();
    if (_playing) {
      _playing = false;
      notifyListeners();
    }
  }

  int _relativeNow() =>
      DateTime.now().microsecondsSinceEpoch - _recordStartMicros;

  static String _key(int pointerId, int note) => '$pointerId:$note';

  @override
  void dispose() {
    stopPlayback();
    super.dispose();
  }
}
