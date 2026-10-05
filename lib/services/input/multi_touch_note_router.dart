typedef PointerNoteOn = void Function(
  int note, {
  int? velocity,
  required int pointerId,
});
typedef PointerNoteOff = void Function(int note, {required int pointerId});

/// Pointer-id based note ownership.
///
/// It supports true chords, repeated touches on the same note and glissando.
/// A MIDI NoteOff is emitted only after the last pointer owning a note leaves.
final class MultiTouchNoteRouter {
  MultiTouchNoteRouter({
    required PointerNoteOn onNoteOn,
    required PointerNoteOff onNoteOff,
  })  : _onNoteOn = onNoteOn,
        _onNoteOff = onNoteOff;

  final PointerNoteOn _onNoteOn;
  final PointerNoteOff _onNoteOff;

  final Map<int, int> _pointerToNote = <int, int>{};
  final Map<int, int> _noteOwners = <int, int>{};

  Set<int> get activeNotes => _noteOwners.keys.toSet();

  void down(int pointerId, int note, {int? velocity}) {
    final old = _pointerToNote[pointerId];
    if (old == note) return;
    if (old != null) _release(pointerId, old);

    _pointerToNote[pointerId] = note;
    final owners = (_noteOwners[note] ?? 0) + 1;
    _noteOwners[note] = owners;
    if (owners == 1) {
      _onNoteOn(note, velocity: velocity, pointerId: pointerId);
    }
  }

  void move(int pointerId, int? note, {int? velocity}) {
    final old = _pointerToNote[pointerId];
    if (old == note) return;

    if (old != null) _release(pointerId, old);
    if (note != null) down(pointerId, note, velocity: velocity);
  }

  void up(int pointerId) {
    final note = _pointerToNote[pointerId];
    if (note != null) _release(pointerId, note);
  }

  void cancelAll() {
    final pointers = _pointerToNote.keys.toList(growable: false);
    for (final pointer in pointers) {
      up(pointer);
    }
  }

  void _release(int pointerId, int note) {
    _pointerToNote.remove(pointerId);
    final owners = (_noteOwners[note] ?? 1) - 1;
    if (owners <= 0) {
      _noteOwners.remove(note);
      _onNoteOff(note, pointerId: pointerId);
    } else {
      _noteOwners[note] = owners;
    }
  }
}
