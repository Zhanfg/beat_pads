import 'package:beat_pads/services/services.dart';

enum PlayMode {
  noSlide('关闭滑奏'),
  slide('滑动触发音符'),

  channelMod(
    '通道触后',
    modulationOverlay: true,
  ),

  polyAT(
    '复音触后',
    modulationOverlay: true,
  ),

  mpe(
    'MPE',
    modulationOverlay: true,
    oneDimensional: false,
    singleChannel: false,
  ),

  mpeTargetPb(
    'MPE · Push 风格',
    oneDimensional: false,
    singleChannel: false,
  );

  const PlayMode(
    this.title, {
    this.modulationOverlay = false,
    this.oneDimensional = true,
    this.singleChannel = true,
  });

  final String title;

  /// Layout uses a modulation overlay and can be modulated by finger panning
  final bool modulationOverlay;

  /// Layout uses a modulation overlay that is circular with only
  /// one modulated parameter
  final bool oneDimensional;

  /// Layout sends Midi on one channel only (Usually all Non-MPE Layouts)
  final bool singleChannel;

  @override
  String toString() => title;

  PlayModeHandler getPlayModeApi(
    SendSettings settings,
    void Function() notifyParent,
  ) {
    switch (this) {
      case PlayMode.mpe:
        return PlayModeMPE(settings, notifyParent);
      case PlayMode.mpeTargetPb:
        return PlayModeMPETargetPb(settings, notifyParent);
      case PlayMode.noSlide:
        return PlayModeNoSlide(settings, notifyParent);
      case PlayMode.slide:
        return PlayModeSlide(settings, notifyParent);
      case PlayMode.polyAT:
        return PlayModePolyAT(settings, notifyParent);
      case PlayMode.channelMod:
        return PlayModeChannelMod(settings, notifyParent);
    }
  }
}
