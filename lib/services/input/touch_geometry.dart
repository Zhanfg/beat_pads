import 'dart:ui';

abstract final class TouchViewportPolicy {
  /// Portrait phones need playable key width more than raw note count.
  /// Values are chromatic-note counts starting at C.
  static int pianoNoteCount(Size size) {
    final portrait = size.height > size.width;
    if (portrait) {
      if (size.width < 430) return 13;
      if (size.width < 760) return 17;
      return 19;
    }

    if (size.width < 760) return 19;
    if (size.width < 1100) return 25;
    return 31;
  }

  /// Number of fret columns shown at once. Paging, rather than horizontal
  /// scrolling, keeps the entire fretboard under one raw-pointer hit surface.
  static int visibleFretCount(Size size, int totalFrets) {
    final usableWidth = (size.width - 58).clamp(1.0, double.infinity);
    final targetCell = size.height > size.width ? 70.0 : 62.0;
    final count = (usableWidth / targetCell).floor().clamp(5, totalFrets + 1);
    return count.toInt();
  }
}

final class FretboardGeometry {
  const FretboardGeometry({
    required this.size,
    required this.stringCount,
    required this.firstFret,
    required this.visibleFretCount,
    this.labelWidth = 58,
  });

  final Size size;
  final int stringCount;
  final int firstFret;
  final int visibleFretCount;
  final double labelWidth;

  double get playableWidth =>
      (size.width - labelWidth).clamp(1.0, size.width).toDouble();
  double get fretWidth => playableWidth / visibleFretCount;
  double get stringHeight => size.height / stringCount;

  int? stringAt(Offset position) {
    if (position.dy < 0 || position.dy >= size.height) return null;
    return (position.dy / stringHeight)
        .floor()
        .clamp(0, stringCount - 1)
        .toInt();
  }

  int? fretAt(Offset position) {
    if (position.dx < labelWidth || position.dx >= size.width) return null;
    final column = ((position.dx - labelWidth) / fretWidth)
        .floor()
        .clamp(0, visibleFretCount - 1)
        .toInt();
    return firstFret + column;
  }
}
