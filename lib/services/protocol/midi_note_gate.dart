/// Collapses pointer-aware AXYP voices into safe standard-MIDI note ownership.
///
/// MIDI 1.0 NoteOn/NoteOff has no voice identifier. If two independent AXYP
/// voices own the same channel/note, forwarding both NoteOff events directly
/// can end the other voice early on many receivers. This gate emits one MIDI
/// NoteOn for the first owner and one NoteOff for the final owner.
final class MidiNoteGate {
  final Map<(int, int), int> _owners = <(int, int), int>{};

  bool acquire(int channel, int note) {
    final key = (channel, note);
    final count = (_owners[key] ?? 0) + 1;
    _owners[key] = count;
    return count == 1;
  }

  bool release(int channel, int note) {
    final key = (channel, note);
    final count = _owners[key];
    if (count == null) return false;
    if (count <= 1) {
      _owners.remove(key);
      return true;
    }
    _owners[key] = count - 1;
    return false;
  }

  int ownersOf(int channel, int note) => _owners[(channel, note)] ?? 0;

  void clear() => _owners.clear();
}
