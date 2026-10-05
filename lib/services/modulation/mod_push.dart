import 'package:beat_pads/services/services.dart';

enum MPEpushStyleYAxisMods {
  mpeAftertouch64('触后压力 · 中心 64', Dims.two, Group.at),
  slide64('Slide [74] · 中心 64', Dims.two, Group.slide),
  pan64('声像 [10] · 中心 64', Dims.two, Group.pan),
  gain64('增益 [7] · 中心 64', Dims.two, Group.gain),
  none('无', Dims.one, Group.none);

  const MPEpushStyleYAxisMods(this.title, this.dimensions, this.exclusiveGroup);
  @override
  String toString() => title;

  final String title;
  final Dims dimensions;
  final Group exclusiveGroup;

  Mod getMod() {
    switch (this) {
      case MPEpushStyleYAxisMods.mpeAftertouch64:
        return ModChannelAftertouch642D();
      case MPEpushStyleYAxisMods.slide64:
        return ModCC642D(CC.slide);
      case MPEpushStyleYAxisMods.pan64:
        return ModCC642D(CC.pan);
      case MPEpushStyleYAxisMods.gain64:
        return ModCC642D(CC.gain);
      case MPEpushStyleYAxisMods.none:
        return ModNull();
    }
  }
}
