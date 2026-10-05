import 'package:beat_pads/screen_pads_menu/drop_down_enum.dart';
import 'package:beat_pads/screen_pads_menu/drop_down_modulation.dart';
import 'package:beat_pads/screen_pads_menu/slider_int.dart';
import 'package:beat_pads/screen_pads_menu/slider_modulation_size.dart';
import 'package:beat_pads/screen_pads_menu/slider_non_linear.dart';
import 'package:beat_pads/services/services.dart';
import 'package:beat_pads/shared_components/_shared.dart';
import 'package:beat_pads/shared_components/divider_title.dart';
import 'package:beat_pads/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final showModPreview = StateProvider<bool>((ref) => false);

class MenuInput extends ConsumerWidget {
  const MenuInput();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        Column(
          children: [
            ColoredBox(
              color: Palette.darkGrey,
              child: ListTile(
                title: const Text(
                  '高级演奏模式',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                // subtitle: const Text(
                //   'Choose how the grid reacts to slides',
                // ),
                trailing: DropdownEnum(
                  values: PlayMode.values,
                  readValue: ref.watch(playModeProv),
                  setValue: (PlayMode v) =>
                      ref.read(playModeProv.notifier).setAndSave(v),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(
                  bottom: ThemeConst.listViewBottomPadding,
                ),
                children: <Widget>[
                  if (ref.watch(playModeProv) == PlayMode.mpeTargetPb)
                    const StringInfoBox(
                      header: 'Push 风格 MPE',
                      body: [
                        '手指滑向其他鼓垫时，音高会向目标音符连续弯音。',
                        'Y 轴可发送调制数据，默认是 Slide / CC74。',
                        '提示：建议把音源的 MPE 弯音范围设置为 48 个半音。',
                        '该模式仍在持续完善。',
                      ],
                    ),
                  if (ref.watch(playModeProv) == PlayMode.channelMod)
                    const StringInfoBox(
                      header: '通道触后',
                      body: [
                        '滑动手指，为当前通道上的音符发送单声道 Aftertouch。',
                        '同一时间只处理一组通道触后调制。',
                      ],
                    ),
                  if (ref.watch(playModeProv) == PlayMode.polyAT)
                    const StringInfoBox(
                      header: '复音触后',
                      body: [
                        '滑动手指，为当前音符发送 Poly Aftertouch。',
                        '每个音符都可以独立处理触后调制。',
                      ],
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpe)
                    const StringInfoBox(
                      header: 'MPE',
                      body: [
                        '滑动手指可为当前激活音符发送自定义 MPE 调制，并显示实时调制覆盖层。',
                        '可选择一维半径调制，或以初始触点为中心的 X/Y 二维调制。',
                      ],
                    ),
                  if (ref.watch(playModeProv) == PlayMode.slide)
                    const StringInfoBox(
                      header: '滑动触发音符',
                      body: [
                        '按下后滑过的音符都会被触发。',
                      ],
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpeTargetPb)
                    ListTile(
                      title: const Text('Y 轴'),
                      trailing: DropdownEnum(
                        values: MPEpushStyleYAxisMods.values,
                        readValue: ref.watch(mpePushYAxisModeProv),
                        setValue: (MPEpushStyleYAxisMods v) => ref
                            .read(mpePushYAxisModeProv.notifier)
                            .setAndSave(v),
                      ),
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpeTargetPb)
                    ListTile(
                      title: const Text('仅当前行鼓垫'),
                      subtitle: const Text(
                        '忽略当前行上方或下方鼓垫产生的调制',
                      ),
                      trailing: Switch(
                        value: ref.watch(mpeOnlyOnRowProv),
                        onChanged: (bool v) =>
                            ref.read(mpeOnlyOnRowProv.notifier).setAndSave(v),
                      ),
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpeTargetPb)
                    IntSliderTile(
                      max: 75,
                      label: '稳定音高区域',
                      subtitle:
                          '设置鼓垫中心保持稳定音高的区域宽度百分比',
                      trailing: ref.watch(pitchDeadzoneProv).toString(),
                      readValue: ref.watch(pitchDeadzoneProv),
                      setValue: (int v) =>
                          ref.read(pitchDeadzoneProv.notifier).set(v),
                      resetValue: ref.read(pitchDeadzoneProv.notifier).reset,
                      onChangeEnd: ref.read(pitchDeadzoneProv.notifier).save,
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpeTargetPb)
                    ListTile(
                      title: const Text('相对模式'),
                      subtitle: const Text(
                        '初始触点将作为该鼓垫的弯音与 Slide 中心',
                      ),
                      trailing: Switch(
                        value: ref.watch(mpeRelativeModeProv),
                        onChanged: (bool v) => ref
                            .read(mpeRelativeModeProv.notifier)
                            .setAndSave(v),
                      ),
                    ),
                  if (ref.watch(playModeProv).modulationOverlay)
                    ModSizeSliderTile(
                      min: ref.watch(modulationRadiusProv.notifier).min,
                      max: ref.watch(modulationRadiusProv.notifier).max,
                      label: '调制区域大小',
                      subtitle:
                          '调制区域相对于鼓垫显示区域的宽度',
                      trailing: Text(
                        '${(ref.watch(modulationRadiusProv) * 100).toInt()}%',
                      ),
                      readValue: ref
                          .watch(modulationRadiusProv)
                          .clamp(
                            ref.watch(modulationRadiusProv.notifier).min,
                            ref.watch(modulationRadiusProv.notifier).max,
                          ),
                      setValue: (double v) =>
                          ref.read(modulationRadiusProv.notifier).set(v),
                      resetValue: ref.read(modulationRadiusProv.notifier).reset,
                      onChangeEnd: ref.read(modulationRadiusProv.notifier).save,
                    ),
                  if (ref.watch(playModeProv).modulationOverlay)
                    ModSizeSliderTile(
                      min: ref.watch(modulationDeadZoneProv.notifier).min,
                      max: ref.watch(modulationDeadZoneProv.notifier).max,
                      label: '中心死区',
                      subtitle:
                          '调制区域中心不响应的范围',
                      trailing: Text(
                        '${(ref.watch(modulationDeadZoneProv) * 100).toInt()}%',
                      ),
                      readValue: ref
                          .watch(modulationDeadZoneProv)
                          .clamp(
                            ref.watch(modulationDeadZoneProv.notifier).min,
                            ref.watch(modulationDeadZoneProv.notifier).max,
                          ),
                      setValue: (double v) =>
                          ref.read(modulationDeadZoneProv.notifier).set(v),
                      resetValue: ref
                          .read(modulationDeadZoneProv.notifier)
                          .reset,
                      onChangeEnd: ref
                          .read(modulationDeadZoneProv.notifier)
                          .save,
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpe)
                    const DividerTitle('MPE'),
                  if (ref.watch(playModeProv) == PlayMode.mpe)
                    ListTile(
                      title: const Text('二维调制'),
                      subtitle: const Text(
                        'X/Y 轴分别控制两个参数；也可只使用半径控制一个参数（括号内为 CC）',
                      ),
                      trailing: Switch(
                        value: ref.watch(modulation2DProv),
                        onChanged: (v) =>
                            ref.read(modulation2DProv.notifier).setAndSave(v),
                      ),
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpe &&
                      ref.watch(modulation2DProv))
                    ListTile(
                      title: const Text('X 轴'),
                      trailing: DropdownModulation(
                        readValue: ref.watch(mpe2DXProv),
                        setValue: (MPEmods v) =>
                            ref.read(mpe2DXProv.notifier).setAndSave(v),
                        otherValue: ref.watch(mpe2DYProv),
                      ),
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpe &&
                      ref.watch(modulation2DProv))
                    ListTile(
                      title: const Text('Y 轴'),
                      trailing: DropdownModulation(
                        readValue: ref.watch(mpe2DYProv),
                        setValue: (MPEmods v) =>
                            ref.read(mpe2DYProv.notifier).setAndSave(v),
                        otherValue: ref.watch(mpe2DXProv),
                      ),
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpe &&
                      ref.watch(modulation2DProv) == false)
                    ListTile(
                      title: const Text('半径'),
                      trailing: DropdownModulation(
                        dimensions: Dims.one,
                        readValue: ref.watch(mpe1DRadiusProv),
                        setValue: (MPEmods v) =>
                            ref.read(mpe1DRadiusProv.notifier).setAndSave(v),
                      ),
                    ),
                  if (ref.watch(playModeProv) == PlayMode.mpe)
                    if (ref.watch(mpe1DRadiusProv).exclusiveGroup ==
                            Group.pitch ||
                        ref.watch(mpe2DXProv).exclusiveGroup == Group.pitch ||
                        ref.watch(mpe2DYProv).exclusiveGroup == Group.pitch)
                      IntSliderTile(
                        min: 1,
                        max: 48,
                        label: '弯音范围',
                        subtitle: 'MPE 最大弯音范围（半音）',
                        trailing: '${ref.watch(mpePitchbendRangeProv)} st',
                        readValue: ref.watch(mpePitchbendRangeProv),
                        setValue: (int v) =>
                            ref.read(mpePitchbendRangeProv.notifier).set(v),
                        resetValue: ref
                            .read(mpePitchbendRangeProv.notifier)
                            .reset,
                        onChangeEnd: ref
                            .read(mpePitchbendRangeProv.notifier)
                            .save,
                      ),
                  const DividerTitle('松手行为'),
                  NonLinearSliderTile(
                    label: '音符释放延迟',
                    subtitle: '松开鼓垫后延迟发送 NoteOff，单位毫秒',
                    readValue: ref.watch(noteReleaseStepProv),
                    setValue: (int v) =>
                        ref.read(noteReleaseStepProv.notifier).set(v),
                    resetFunction: ref.read(noteReleaseStepProv.notifier).reset,
                    displayValue: ref.watch(noteReleaseUsable) == 0
                        ? '关闭'
                        : ref.watch(noteReleaseUsable) < 1000
                        ? '${ref.watch(noteReleaseUsable)} ms'
                        : '${ref.watch(noteReleaseUsable) / 1000} s',
                    steps: Timing.releaseDelayTimes.length ~/ 1.5,
                    onChangeEnd: ref.read(noteReleaseStepProv.notifier).save,
                  ),
                  if (ref.watch(playModeProv).modulationOverlay)
                    NonLinearSliderTile(
                      label: '调制平滑回中',
                      subtitle:
                          '松开鼓垫后调制参数平滑回到 0 的时间，单位毫秒',
                      readValue: ref.watch(modReleaseStepProv),
                      setValue: (int v) =>
                          ref.read(modReleaseStepProv.notifier).set(v),
                      resetFunction: ref
                          .read(modReleaseStepProv.notifier)
                          .reset,
                      displayValue: ref.watch(modReleaseUsable) == 0
                          ? '关闭'
                          : ref.watch(modReleaseUsable) < 1000
                          ? '${ref.watch(modReleaseUsable)} ms'
                          : '${ref.watch(modReleaseUsable) / 1000} s',
                      steps: Timing.releaseDelayTimes.length ~/ 1.5,
                      onChangeEnd: ref.read(modReleaseStepProv.notifier).save,
                    ),
                  if (ref.watch(playModeProv).singleChannel)
                    const DividerTitle('CC'),
                  if (ref.watch(playModeProv).singleChannel)
                    ListTile(
                      title: const Text('控制变化 CC'),
                      subtitle: const Text(
                        '发送音符时同时在高一号 MIDI 通道发送 CC 消息',
                      ),
                      trailing: Switch(
                        value: ref.watch(sendCCProv),
                        onChanged: (v) =>
                            ref.read(sendCCProv.notifier).setAndSave(v),
                      ),
                    ),
                  SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
        if (ref.watch(showModPreview)) const PaintModPreview(),
        if (ref.watch(layoutProv) == Layout.progrChange)
          Container(
            padding: const EdgeInsets.all(24),
            color: Palette.darkGrey.withValues(alpha: 0.86),
            child: Center(
              child: Text(
                '使用 Program Change 布局时，高级设置不可用',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Palette.whiteLike,
                  fontSize: Theme.of(context).textTheme.headlineSmall!.fontSize,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
