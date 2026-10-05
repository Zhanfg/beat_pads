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

  RecordedNote copyWith({
    int? note,
    int? velocity,
    int? startMicros,
    int? durationMicros,
  }) {
    return RecordedNote(
      note: note ?? this.note,
      velocity: velocity ?? this.velocity,
      startMicros: startMicros ?? this.startMicros,
      durationMicros: durationMicros ?? this.durationMicros,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'note': note,
        'velocity': velocity,
        'startMicros': startMicros,
        'durationMicros': durationMicros,
      };

  static RecordedNote fromJson(Map<String, Object?> json) {
    return RecordedNote(
      note: (json['note'] as num).toInt(),
      velocity: (json['velocity'] as num).toInt(),
      startMicros: (json['startMicros'] as num).toInt(),
      durationMicros: (json['durationMicros'] as num).toInt(),
    );
  }
}

final class StudioClip {
  const StudioClip({
    required this.id,
    required this.name,
    required this.notes,
    required this.lengthMicros,
    this.startMicros = 0,
    this.loop = false,
  });

  final String id;
  final String name;
  final List<RecordedNote> notes;
  final int lengthMicros;
  final int startMicros;
  final bool loop;

  bool get isEmpty => notes.isEmpty;
  int get endMicros => startMicros + lengthMicros;

  StudioClip copyWith({
    String? id,
    String? name,
    List<RecordedNote>? notes,
    int? lengthMicros,
    int? startMicros,
    bool? loop,
  }) {
    return StudioClip(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      lengthMicros: lengthMicros ?? this.lengthMicros,
      startMicros: startMicros ?? this.startMicros,
      loop: loop ?? this.loop,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'notes': notes.map((note) => note.toJson()).toList(),
        'lengthMicros': lengthMicros,
        'startMicros': startMicros,
        'loop': loop,
      };

  static StudioClip fromJson(Map<String, Object?> json) {
    final rawNotes = (json['notes'] as List<Object?>? ?? const <Object?>[]);
    return StudioClip(
      id: json['id'] as String,
      name: json['name'] as String? ?? '片段',
      notes: rawNotes
          .map((item) => RecordedNote.fromJson(
                Map<String, Object?>.from(item! as Map),
              ))
          .toList(growable: false),
      lengthMicros: (json['lengthMicros'] as num? ?? 0).toInt(),
      startMicros: (json['startMicros'] as num? ?? 0).toInt(),
      loop: json['loop'] as bool? ?? false,
    );
  }
}

final class StudioTrack {
  const StudioTrack({
    required this.id,
    required this.name,
    required this.instrumentId,
    required this.clips,
    this.muted = false,
    this.solo = false,
    this.volume = 1.0,
    this.pan = 0.0,
  });

  final String id;
  final String name;
  final String instrumentId;
  final List<StudioClip> clips;
  final bool muted;
  final bool solo;
  final double volume;
  final double pan;

  StudioTrack copyWith({
    String? id,
    String? name,
    String? instrumentId,
    List<StudioClip>? clips,
    bool? muted,
    bool? solo,
    double? volume,
    double? pan,
  }) {
    return StudioTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      instrumentId: instrumentId ?? this.instrumentId,
      clips: clips ?? this.clips,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'instrumentId': instrumentId,
        'clips': clips.map((clip) => clip.toJson()).toList(),
        'muted': muted,
        'solo': solo,
        'volume': volume,
        'pan': pan,
      };

  static StudioTrack fromJson(Map<String, Object?> json) {
    final rawClips = (json['clips'] as List<Object?>? ?? const <Object?>[]);
    return StudioTrack(
      id: json['id'] as String,
      name: json['name'] as String? ?? '轨道',
      instrumentId: json['instrumentId'] as String? ?? 'keyboard',
      clips: rawClips
          .map((item) => StudioClip.fromJson(
                Map<String, Object?>.from(item! as Map),
              ))
          .toList(growable: false),
      muted: json['muted'] as bool? ?? false,
      solo: json['solo'] as bool? ?? false,
      volume: (json['volume'] as num? ?? 1).toDouble(),
      pan: (json['pan'] as num? ?? 0).toDouble(),
    );
  }
}

final class StudioProject {
  const StudioProject({
    required this.name,
    required this.tempo,
    required this.tracks,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final String name;
  final int tempo;
  final List<StudioTrack> tracks;

  StudioProject copyWith({
    int? schemaVersion,
    String? name,
    int? tempo,
    List<StudioTrack>? tracks,
  }) {
    return StudioProject(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      name: name ?? this.name,
      tempo: tempo ?? this.tempo,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'schemaVersion': schemaVersion,
        'name': name,
        'tempo': tempo,
        'tracks': tracks.map((track) => track.toJson()).toList(),
      };

  static StudioProject empty({String name = '未命名工程', int tempo = 120}) {
    return StudioProject(
      name: name,
      tempo: tempo,
      tracks: const <StudioTrack>[],
    );
  }

  static StudioProject fromJson(Map<String, Object?> json) {
    final rawTracks = (json['tracks'] as List<Object?>? ?? const <Object?>[]);
    return StudioProject(
      schemaVersion: (json['schemaVersion'] as num? ?? 1).toInt(),
      name: json['name'] as String? ?? '未命名工程',
      tempo: (json['tempo'] as num? ?? 120).toInt(),
      tracks: rawTracks
          .map((item) => StudioTrack.fromJson(
                Map<String, Object?>.from(item! as Map),
              ))
          .toList(growable: false),
    );
  }
}
