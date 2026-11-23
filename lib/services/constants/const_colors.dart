import 'package:flutter/material.dart';

abstract final class Palette {
  static const Color cadetBlue = Color(0xFF8AA8D8);
  static const Color lightPink = Color(0xFFF4A3A3);
  static const Color darkGrey = Color(0xFF424242);

  static Color darker(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
        .toColor();
  }
}
