import 'package:beat_pads/services/state/shared_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final channelSettingProv = NotifierProvider<SettingIntNotifier, int>(() {
  return SettingIntNotifier(
    key: 'channel',
    defaultValue: 0,
    max: 15,
  );
});

final channelUsableProv = Provider<int>((ref) {
  return ref.watch(channelSettingProv);
});

final velocityProv = NotifierProvider<SettingIntNotifier, int>(() {
  return SettingIntNotifier(
    key: 'velocity',
    defaultValue: 110,
    min: 1,
    max: 127,
  );
});
