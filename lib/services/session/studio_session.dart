import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:beat_pads/services/protocol/axyp_event.dart';
import 'package:beat_pads/services/session/studio_project.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Persistent multi-track project/session core.
///
/// Touch surfaces publish AXYP events. This class records those events into a
/// serializable project model and exposes editor operations without depending
/// on widgets, MIDI or the local audio backend.
final class StudioSession extends ChangeNotifier {
  StudioSession({SharedPreferences? storage}) : _storage = storage {
    _restore();
  }

  static const String _storageKey = 'axyp-workstation-project-v1';
  static const String _libraryKey = 'axyp-workstation-library-v1';
  static const StudioClip _emptyClip = StudioClip(
    id: 'empty',
    name: '空片段',
    notes: <RecordedNote>[],
    lengthMicros: 0,
  );

  final SharedPreferences? _storage;
  final Map<String, _PendingNote> _pending = <String, _PendingNote>{};
  final List<RecordedNote> _recordingNotes = <RecordedNote>[];
  final List<Timer> _playbackTimers = <Timer>[];
  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];
  final Map<String, String> _library = <String, String>{};

  StudioProject _project = StudioProject.empty();
  String? _selectedTrackId;
  String? _selectedClipId;
  bool _recording = false;
  bool _playing = false;
  int _recordStartMicros = 0;
  int _idCounter = 0;
  Timer? _saveDebounce;
  String? _activeLibraryName;

  StudioProject get project => _project;
  bool get recording => _recording;
  bool get playing => _playing;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get selectedTrackId => _selectedTrackId;
  String? get selectedClipId => _selectedClipId;
  String? get activeLibraryName => _activeLibraryName;
  List<String> get savedProjectNames => _library.keys.toList()..sort();

  StudioTrack? get selectedTrack {
    final id = _selectedTrackId;
    if (id == null) return _project.tracks.firstOrNull;
    return _project.tracks.where((track) => track.id == id).firstOrNull;
  }

  StudioClip? get selectedClip {
    final track = selectedTrack;
    if (track == null) return null;
    final id = _selectedClipId;
    if (id == null) return track.clips.lastOrNull;
    return track.clips.where((clip) => clip.id == id).firstOrNull;
  }

  StudioClip get clip => selectedClip ?? _emptyClip;

  int get projectLengthMicros {
    int result = 0;
    for (final track in _project.tracks) {
      for (final clip in track.clips) {
        result = math.max(result, clip.endMicros);
      }
    }
    return result;
  }

  void newProject({String name = '未命名工程', int tempo = 120}) {
    _snapshot();
    stopPlayback();
    _project = StudioProject.empty(name: name, tempo: tempo);
    _activeLibraryName = null;
    _selectedTrackId = null;
    _selectedClipId = null;
    _recording = false;
    _pending.clear();
    _recordingNotes.clear();
    _commit();
  }

  void renameProject(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _project.name) return;
    _snapshot();
    final oldLibraryName = _activeLibraryName;
    _project = _project.copyWith(name: trimmed);
    if (oldLibraryName != null) {
      _library.remove(oldLibraryName);
      _activeLibraryName = trimmed;
      _library[trimmed] = _encodeState();
      _saveLibrary();
    }
    _commit();
  }

  void saveProjectAs(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_project.name != trimmed) {
      _project = _project.copyWith(name: trimmed);
    }
    _activeLibraryName = trimmed;
    _library[trimmed] = _encodeState();
    _saveLibrary();
    _commit();
  }

  bool loadProject(String name) {
    final raw = _library[name];
    if (raw == null) return false;
    stopPlayback();
    try {
      _restoreState(raw);
      _activeLibraryName = name;
      _undo.clear();
      _redo.clear();
      _commit();
      return true;
    } on Object {
      return false;
    }
  }

  void deleteSavedProject(String name) {
    if (_library.remove(name) == null) return;
    if (_activeLibraryName == name) _activeLibraryName = null;
    _saveLibrary();
    notifyListeners();
  }

  String addTrack({
    String instrumentId = 'keyboard',
    String? name,
    bool select = true,
  }) {
    _snapshot();
    final id = _newId('track');
    final trackNumber = _project.tracks.length + 1;
    final track = StudioTrack(
      id: id,
      name: name ?? '轨道 $trackNumber',
      instrumentId: instrumentId,
      clips: const <StudioClip>[],
    );
    _project = _project.copyWith(
      tracks: <StudioTrack>[..._project.tracks, track],
    );
    if (select) {
      _selectedTrackId = id;
      _selectedClipId = null;
    }
    _commit();
    return id;
  }

  void deleteTrack(String trackId) {
    final index = _project.tracks.indexWhere((track) => track.id == trackId);
    if (index < 0) return;
    _snapshot();
    final next = [..._project.tracks]..removeAt(index);
    _project = _project.copyWith(tracks: next);
    if (_selectedTrackId == trackId) {
      _selectedTrackId =
          next.isEmpty ? null : next[math.min(index, next.length - 1)].id;
      _selectedClipId = null;
    }
    _commit();
  }

  void selectTrack(String trackId) {
    if (!_project.tracks.any((track) => track.id == trackId)) return;
    _selectedTrackId = trackId;
    _selectedClipId = null;
    notifyListeners();
  }

  void selectClip(String clipId) {
    final track = selectedTrack;
    if (track == null || !track.clips.any((clip) => clip.id == clipId)) return;
    _selectedClipId = clipId;
    notifyListeners();
  }

  void renameTrack(String trackId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _editTrack(trackId, (track) => track.copyWith(name: trimmed));
  }

  void setTrackInstrument(String trackId, String instrumentId) {
    _editTrack(
      trackId,
      (track) => track.copyWith(instrumentId: instrumentId),
    );
  }

  void setTrackMute(String trackId, bool muted) {
    _editTrack(trackId, (track) => track.copyWith(muted: muted));
  }

  void setTrackSolo(String trackId, bool solo) {
    _editTrack(trackId, (track) => track.copyWith(solo: solo));
  }

  void setTrackVolume(String trackId, double volume) {
    _editTrack(
      trackId,
      (track) => track.copyWith(volume: volume.clamp(0.0, 1.5)),
      snapshot: false,
    );
  }

  void setTempo(int tempo) {
    final next = tempo.clamp(40, 240).toInt();
    if (_project.tempo == next) return;
    _snapshot();
    _project = _project.copyWith(tempo: next);
    _commit();
  }

  void startRecording({String instrumentId = 'keyboard'}) {
    stopPlayback();

    var track = selectedTrack;
    if (track == null) {
      final id = addTrack(instrumentId: instrumentId);
      track = _project.tracks.firstWhere((item) => item.id == id);
    } else if (track.instrumentId != instrumentId) {
      setTrackInstrument(track.id, instrumentId);
    }

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
          durationMicros:
              (now - pending.startMicros).clamp(1000, math.max(1000, now)).toInt(),
        ),
      );
    }
    _pending.clear();
    _recordingNotes.sort((a, b) => a.startMicros.compareTo(b.startMicros));

    final track = selectedTrack;
    if (track != null && _recordingNotes.isNotEmpty) {
      _snapshot();
      final length = _recordingNotes.fold<int>(
        0,
        (current, note) => math.max(current, note.endMicros),
      );
      final start = track.clips.fold<int>(
        0,
        (current, clip) => math.max(current, clip.endMicros),
      );
      final clip = StudioClip(
        id: _newId('clip'),
        name: '片段 ${track.clips.length + 1}',
        notes: List<RecordedNote>.unmodifiable(_recordingNotes),
        lengthMicros: length,
        startMicros: start,
      );
      _replaceTrack(
        track.copyWith(clips: <StudioClip>[...track.clips, clip]),
      );
      _selectedClipId = clip.id;
    }

    _recording = false;
    _recordingNotes.clear();
    _commit();
  }

  void ingest(AxypEvent event) {
    if (!_recording) return;

    switch (event) {
      case AxypNoteOn e:
        _pending[_key(e.pointerId, e.note)] = _PendingNote(
          note: e.note,
          velocity: e.velocity,
          startMicros: _relativeNow(),
        );
        break;
      case AxypNoteOff e:
        final pending = _pending.remove(_key(e.pointerId, e.note));
        if (pending == null) return;
        final end = _relativeNow();
        _recordingNotes.add(
          RecordedNote(
            note: pending.note,
            velocity: pending.velocity,
            startMicros: pending.startMicros,
            durationMicros:
                (end - pending.startMicros).clamp(1000, math.max(1000, end)).toInt(),
          ),
        );
        break;
      default:
        break;
    }
  }

  void duplicateSelectedClip() {
    final track = selectedTrack;
    final source = selectedClip;
    if (track == null || source == null) return;
    _snapshot();
    final duplicate = source.copyWith(
      id: _newId('clip'),
      name: '${source.name} 副本',
      startMicros: track.clips.fold<int>(
        0,
        (current, clip) => math.max(current, clip.endMicros),
      ),
      notes: List<RecordedNote>.unmodifiable(source.notes),
    );
    _replaceTrack(
      track.copyWith(clips: <StudioClip>[...track.clips, duplicate]),
    );
    _selectedClipId = duplicate.id;
    _commit();
  }

  void deleteSelectedClip() {
    final track = selectedTrack;
    final source = selectedClip;
    if (track == null || source == null) return;
    _snapshot();
    final clips = track.clips.where((clip) => clip.id != source.id).toList();
    _replaceTrack(track.copyWith(clips: clips));
    _selectedClipId = clips.lastOrNull?.id;
    _commit();
  }

  void clear() => deleteSelectedClip();

  void setSelectedClipLoop(bool loop) {
    _editSelectedClip((clip) => clip.copyWith(loop: loop));
  }

  void moveSelectedClip(int deltaMicros) {
    _editSelectedClip(
      (clip) => clip.copyWith(
        startMicros: math.max(0, clip.startMicros + deltaMicros),
      ),
    );
  }

  void quantizeSelectedClip({required int division}) {
    final source = selectedClip;
    if (source == null || division <= 0) return;
    final beatMicros = 60000000 / _project.tempo;
    final step = math.max(1000, (beatMicros * 4 / division).round());
    _editSelectedClip((clip) {
      final notes = clip.notes.map((note) {
        final start = (note.startMicros / step).round() * step;
        final end = (note.endMicros / step).round() * step;
        return note.copyWith(
          startMicros: math.max(0, start),
          durationMicros: math.max(step, end - start),
        );
      }).toList()
        ..sort((a, b) => a.startMicros.compareTo(b.startMicros));
      return _clipWithRecomputedLength(clip, notes);
    });
  }

  void transposeSelectedClip(int semitones) {
    _editSelectedClip((source) {
      final notes = source.notes
          .map(
            (note) => note.copyWith(
              note: (note.note + semitones).clamp(0, 127).toInt(),
            ),
          )
          .toList(growable: false);
      return source.copyWith(notes: notes);
    });
  }

  void changeSelectedVelocity(int delta) {
    _editSelectedClip((source) {
      final notes = source.notes
          .map(
            (note) => note.copyWith(
              velocity: (note.velocity + delta).clamp(1, 127).toInt(),
            ),
          )
          .toList(growable: false);
      return source.copyWith(notes: notes);
    });
  }

  void addNoteToSelectedClip({
    required int note,
    required int startMicros,
    required int durationMicros,
    int velocity = 100,
  }) {
    final track = selectedTrack;
    if (track == null) return;

    var source = selectedClip;
    if (source == null) {
      _snapshot();
      source = StudioClip(
        id: _newId('clip'),
        name: '片段 ${track.clips.length + 1}',
        notes: const <RecordedNote>[],
        lengthMicros: 0,
        startMicros: track.clips.fold<int>(
          0,
          (current, clip) => math.max(current, clip.endMicros),
        ),
      );
      _replaceTrack(
        track.copyWith(clips: <StudioClip>[...track.clips, source]),
      );
      _selectedClipId = source.id;
    } else {
      _snapshot();
    }

    final notes = <RecordedNote>[
      ...source.notes,
      RecordedNote(
        note: note.clamp(0, 127).toInt(),
        velocity: velocity.clamp(1, 127).toInt(),
        startMicros: math.max(0, startMicros),
        durationMicros: math.max(1000, durationMicros),
      ),
    ]..sort((a, b) => a.startMicros.compareTo(b.startMicros));

    _replaceSelectedClip(_clipWithRecomputedLength(source, notes));
    _commit();
  }

  void removeNoteFromSelectedClip(int index) {
    final source = selectedClip;
    if (source == null || index < 0 || index >= source.notes.length) return;
    _snapshot();
    final notes = [...source.notes]..removeAt(index);
    _replaceSelectedClip(_clipWithRecomputedLength(source, notes));
    _commit();
  }

  void updateNoteInSelectedClip(
    int index, {
    int? note,
    int? startMicros,
    int? durationMicros,
    int? velocity,
  }) {
    final source = selectedClip;
    if (source == null || index < 0 || index >= source.notes.length) return;
    _snapshot();
    final notes = [...source.notes];
    final current = notes[index];
    notes[index] = current.copyWith(
      note: note?.clamp(0, 127).toInt(),
      startMicros: startMicros == null ? null : math.max(0, startMicros),
      durationMicros:
          durationMicros == null ? null : math.max(1000, durationMicros),
      velocity: velocity?.clamp(1, 127).toInt(),
    );
    notes.sort((a, b) => a.startMicros.compareTo(b.startMicros));
    _replaceSelectedClip(_clipWithRecomputedLength(source, notes));
    _commit();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_encodeState());
    _restoreState(_undo.removeLast());
    _commit();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_encodeState());
    _restoreState(_redo.removeLast());
    _commit();
  }

  void play({
    required void Function(int note, int velocity) noteOn,
    required void Function(int note) noteOff,
  }) {
    playProject(
      noteOn: (_, note, velocity, _) => noteOn(note, velocity),
      noteOff: (_, note, _) => noteOff(note),
    );
  }

  void playProject({
    required void Function(
      StudioTrack track,
      int note,
      int velocity,
      int voiceId,
    ) noteOn,
    required void Function(
      StudioTrack track,
      int note,
      int voiceId,
    ) noteOff,
  }) {
    if (_project.tracks.every((track) => track.clips.isEmpty)) return;

    stopPlayback();
    final soloing = _project.tracks.any((track) => track.solo);
    final activeTracks = _project.tracks.where(
      (track) => !track.muted && (!soloing || track.solo),
    );
    final beatMicros = (60000000 / _project.tempo).round();
    final minimumSongLength = beatMicros * 16;
    final songLength = math.max(projectLengthMicros, minimumSongLength);
    int scheduledEvents = 0;
    int nextVoiceId = -2;

    for (final track in activeTracks) {
      for (final clip in track.clips) {
        if (clip.isEmpty) continue;
        final repeatLength = math.max(1000, clip.lengthMicros);
        int iterationStart = clip.startMicros;
        int iterations = 0;

        while (iterationStart < songLength && iterations < 256) {
          for (final note in clip.notes) {
            final onAt = iterationStart + note.startMicros;
            if (onAt >= songLength) continue;
            final offAt = iterationStart + note.endMicros;
            final velocity =
                (note.velocity * track.volume).round().clamp(1, 127).toInt();
            final voiceId = nextVoiceId--;

            _playbackTimers.add(
              Timer(
                Duration(microseconds: onAt),
                () => noteOn(track, note.note, velocity, voiceId),
              ),
            );
            _playbackTimers.add(
              Timer(
                Duration(microseconds: offAt),
                () => noteOff(track, note.note, voiceId),
              ),
            );
            scheduledEvents += 2;
          }

          if (!clip.loop) break;
          iterationStart += repeatLength;
          iterations++;
        }
      }
    }

    if (scheduledEvents == 0) return;
    _playing = true;
    notifyListeners();
    _playbackTimers.add(
      Timer(
        Duration(microseconds: songLength + 2000),
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

  void _editTrack(
    String trackId,
    StudioTrack Function(StudioTrack track) edit, {
    bool snapshot = true,
  }) {
    final index = _project.tracks.indexWhere((track) => track.id == trackId);
    if (index < 0) return;
    if (snapshot) _snapshot();
    final tracks = [..._project.tracks];
    tracks[index] = edit(tracks[index]);
    _project = _project.copyWith(tracks: tracks);
    _commit();
  }

  void _editSelectedClip(StudioClip Function(StudioClip clip) edit) {
    final source = selectedClip;
    if (source == null) return;
    _snapshot();
    _replaceSelectedClip(edit(source));
    _commit();
  }

  void _replaceSelectedClip(StudioClip replacement) {
    final track = selectedTrack;
    if (track == null) return;
    final clips = [...track.clips];
    final index = clips.indexWhere((clip) => clip.id == replacement.id);
    if (index < 0) return;
    clips[index] = replacement;
    _replaceTrack(track.copyWith(clips: clips));
  }

  void _replaceTrack(StudioTrack replacement) {
    final tracks = [..._project.tracks];
    final index = tracks.indexWhere((track) => track.id == replacement.id);
    if (index < 0) return;
    tracks[index] = replacement;
    _project = _project.copyWith(tracks: tracks);
  }

  StudioClip _clipWithRecomputedLength(
    StudioClip source,
    List<RecordedNote> notes,
  ) {
    final length = notes.fold<int>(
      0,
      (current, note) => math.max(current, note.endMicros),
    );
    return source.copyWith(
      notes: List<RecordedNote>.unmodifiable(notes),
      lengthMicros: length,
    );
  }

  void _snapshot() {
    _undo.add(_encodeState());
    if (_undo.length > 32) _undo.removeAt(0);
    _redo.clear();
  }

  String _encodeState() {
    return jsonEncode(<String, Object?>{
      'project': _project.toJson(),
      'selectedTrackId': _selectedTrackId,
      'selectedClipId': _selectedClipId,
    });
  }

  void _restoreState(String raw) {
    final root = Map<String, Object?>.from(jsonDecode(raw) as Map);
    _project = StudioProject.fromJson(
      Map<String, Object?>.from(root['project']! as Map),
    );
    _selectedTrackId = root['selectedTrackId'] as String?;
    _selectedClipId = root['selectedClipId'] as String?;
  }

  void _restore() {
    final libraryRaw = _storage?.getString(_libraryKey);
    if (libraryRaw != null && libraryRaw.isNotEmpty) {
      try {
        final decoded = Map<String, Object?>.from(jsonDecode(libraryRaw) as Map);
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is String) _library[entry.key] = value;
        }
      } on Object {
        _library.clear();
      }
    }

    final raw = _storage?.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      _restoreState(raw);
      final matchingName = _project.name;
      if (_library.containsKey(matchingName)) {
        _activeLibraryName = matchingName;
      }
    } on Object {
      _project = StudioProject.empty();
      _selectedTrackId = null;
      _selectedClipId = null;
    }
  }

  void _saveLibrary() {
    _storage?.setString(_libraryKey, jsonEncode(_library));
  }

  void _commit() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 180), () {
      final encoded = _encodeState();
      _storage?.setString(_storageKey, encoded);
      final activeName = _activeLibraryName;
      if (activeName != null) {
        _library[activeName] = encoded;
        _saveLibrary();
      }
    });
    notifyListeners();
  }

  int _relativeNow() =>
      DateTime.now().microsecondsSinceEpoch - _recordStartMicros;

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  static String _key(int pointerId, int note) => '$pointerId:$note';

  @override
  void dispose() {
    _saveDebounce?.cancel();
    stopPlayback();
    super.dispose();
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

extension _ListLastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
