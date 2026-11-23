abstract final class MidiUtils {
  static const List<String> _notes = <String>[
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static String getNoteName(
    int value, {
    bool showOctaveIndex = true,
  }) {
    if (value < 0 || value > 127) return '#Range';

    final octave = value ~/ 12 - 2;
    final note = _notes[value % 12];
    return showOctaveIndex ? '$note$octave' : note;
  }
}
