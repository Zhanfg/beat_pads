import 'package:beat_pads/services/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FlScale {
  chromatic('半音阶', <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
  major('大调', <int>[0, 2, 4, 5, 7, 9, 11]),
  naturalMinor('自然小调', <int>[0, 2, 3, 5, 7, 8, 10]),
  harmonicMinor('和声小调', <int>[0, 2, 3, 5, 7, 8, 11]),
  melodicMinor('旋律小调', <int>[0, 2, 3, 5, 7, 9, 11]),
  dorian('多利亚', <int>[0, 2, 3, 5, 7, 9, 10]),
  mixolydian('混合利底亚', <int>[0, 2, 4, 5, 7, 9, 10]),
  phrygian('弗里吉亚', <int>[0, 1, 3, 5, 7, 8, 10]),
  majorPentatonic('大调五声音阶', <int>[0, 2, 4, 7, 9]),
  minorPentatonic('小调五声音阶', <int>[0, 3, 5, 7, 10]),
  blues('布鲁斯', <int>[0, 3, 5, 6, 7, 10]);

  const FlScale(this.label, this.intervals);

  final String label;
  final List<int> intervals;

  bool containsNote(int midiNote, int root) {
    final relative = (midiNote - root) % 12;
    return intervals.contains(relative < 0 ? relative + 12 : relative);
  }
}

final flScaleProvider =
    NotifierProvider<SettingEnumNotifier<FlScale>, FlScale>(() {
  return SettingEnumNotifier<FlScale>(
    nameMap: FlScale.values.asNameMap(),
    key: 'fl_scale',
    defaultValue: FlScale.chromatic,
    usesPresets: false,
  );
});

final flScaleRootProvider = NotifierProvider<SettingIntNotifier, int>(() {
  return SettingIntNotifier(
    key: 'fl_scale_root',
    defaultValue: 0,
    min: 0,
    max: 11,
    usesPresets: false,
  );
});

final flScaleLockProvider = NotifierProvider<SettingBoolNotifier, bool>(() {
  return SettingBoolNotifier(
    key: 'fl_scale_lock',
    defaultValue: false,
    usesPresets: false,
  );
});

final flTouchDynamicsProvider = NotifierProvider<SettingBoolNotifier, bool>(() {
  return SettingBoolNotifier(
    key: 'fl_touch_dynamics',
    defaultValue: true,
    usesPresets: false,
  );
});

final flTempoProvider = NotifierProvider<SettingIntNotifier, int>(() {
  return SettingIntNotifier(
    key: 'fl_tempo',
    defaultValue: 120,
    min: 40,
    max: 240,
    usesPresets: false,
  );
});

final flMacro1CcProvider = _ccProvider('fl_macro_1_cc', 20);
final flMacro2CcProvider = _ccProvider('fl_macro_2_cc', 21);
final flMacro3CcProvider = _ccProvider('fl_macro_3_cc', 22);
final flMacro4CcProvider = _ccProvider('fl_macro_4_cc', 23);
final flXyXCcProvider = _ccProvider('fl_xy_x_cc', 74);
final flXyYCcProvider = _ccProvider('fl_xy_y_cc', 71);

NotifierProvider<SettingIntNotifier, int> _ccProvider(
  String key,
  int defaultValue,
) {
  return NotifierProvider<SettingIntNotifier, int>(() {
    return SettingIntNotifier(
      key: key,
      defaultValue: defaultValue,
      min: 0,
      max: 127,
      usesPresets: false,
    );
  });
}
