import 'package:beat_pads/screen_beat_pads/button_presets.dart';
import 'package:beat_pads/screen_pads_menu/counter_int.dart';
import 'package:beat_pads/screen_pads_menu/drop_down_enum.dart';
import 'package:beat_pads/screen_pads_menu/drop_down_int.dart';
import 'package:beat_pads/screen_pads_menu/drop_down_notes.dart';
import 'package:beat_pads/screen_pads_menu/preview_beat_pads.dart';
import 'package:beat_pads/screen_pads_menu/slider_int.dart';
import 'package:beat_pads/screen_pads_menu/slider_non_linear.dart';
import 'package:beat_pads/services/services.dart';
import 'package:beat_pads/shared_components/divider_title.dart';
import 'package:beat_pads/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MenuLayout extends ConsumerWidget {
  const MenuLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dropdownLayout = DropdownEnum<Layout>(
      highlight: const [Layout.customIntervals, Layout.scaleNotesCustom],
      values: Layout.values,
      readValue: ref.watch<Layout>(layoutProv),
      setValue: (Layout v) {
        ref.read(layoutProv.notifier).setAndSave(v);
      },
    );

    final dropdownProgram = DropdownInt(
      readValue: ref.watch(baseProgramProv) + 1,
      setValue: (int v) => ref.read(baseProgramProv.notifier).setAndSave(v - 1),
      size: 128,
      start: 1,
    );

    final dropdownScale = DropdownEnum<Scale>(
      values: Scale.values,
      readValue: ref.watch(scaleProv),
      setValue: (Scale v) {
        ref.read(scaleProv.notifier).setAndSave(v);
        ref.read(baseProv.notifier).setAndSave(ref.read(rootProv));
      },
    );

    final dropdownRootNote = DropdownRootNote(
      setValue: (int v) {
        ref.read(rootProv.notifier).setAndSave(v);
        ref.read(baseProv.notifier).setAndSave(v);
      },
      readValue: ref.watch(rootProv),
    );

    final dropdownBaseNote = DropdownRootNote(
      enabledList: ref.watch(layoutProv).chromatic
          ? null
          : MidiUtils.absoluteScaleNotes(
              ref.watch(rootProv),
              ref.watch(scaleProv).intervals,
            ),
      setValue: (int v) => ref.read(baseProv.notifier).setAndSave(v),
      readValue: ref.watch(baseProv),
    );

    final bool resizableGrid = ref
        .watch(layoutProv)
        .resizable; // Is the layout fixed or resizable?
    final bool isPortrait =
        MediaQuery.of(context).orientation.name == 'portrait';

    return Flex(
      direction: isPortrait ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: isPortrait
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,

      children: [
        Flexible(
          fit: FlexFit.tight,
          flex: isPortrait ? 4 : 7,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: isPortrait ? Alignment.topCenter : Alignment.center,
            child: RepaintBoundary(
              child: PreviewPads(), // PADS PREVIEW
            ),
          ),
        ),
        RotatedBox(
          quarterTurns: isPortrait ? 0 : 1,
          child: const Divider(height: 0, thickness: 3),
        ),
        Expanded(
          flex: 8,
          child: ListView(
            scrollCacheExtent: ScrollCacheExtent.pixels(1500),
            padding: const EdgeInsets.only(
              bottom: ThemeConst.listViewBottomPadding,
            ),
            children: <Widget>[
              const DividerTitle('场景预设'),
              const PresetButtons(
                clickType: ClickType.tap,
                row: true,
                minimumSize: true,
              ),
              ListTile(
                title: const Text('显示预设按钮'),
                subtitle: const Text('双击按钮切换预设'),
                trailing: Switch(
                  value: ref.watch(presetButtonsProv),
                  onChanged: (v) =>
                      ref.read(presetButtonsProv.notifier).setAndSave(v),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: ThemeConst.menuButtonMinWidth,
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Palette.laserLemon,
                    ),
                    child: const Text('重置当前预设'),
                    onPressed: () {
                      showDialog<String>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          title: const Text('重置'),
                          content: const Text(
                            '将当前预设恢复为默认值？',
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'Cancel'),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, 'OK');
                                ref.read(resetAllProv.notifier).resetAll();
                              },
                              child: const Text('确定'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              /////////////////////////////////////
              const DividerTitle('布局'),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                color: Palette.darkGrey,
                child: ListTile(
                  title: const Text(
                    '布局',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: dropdownLayout,
                ),
              ),
              if (ref.watch(layoutProv) == Layout.progrChange)
                ListTile(
                  title: const Text('起始 Program'),
                  subtitle: const Text('网格左下角的最低 Program 编号'),
                  trailing: dropdownProgram,
                ),
              if (resizableGrid && ref.watch(layoutProv).custom)
                IntCounterTile(
                  label: ref.watch(layoutProv) == Layout.scaleNotesCustom
                      ? 'X：音阶级数'
                      : 'X：半音数',
                  setValue: (int v) =>
                      ref.read(customIntervalXProv.notifier).setAndSave(v),
                  readValue: ref.watch(customIntervalXProv),
                ),
              if (resizableGrid && ref.watch(layoutProv).custom)
                IntCounterTile(
                  label: ref.watch(layoutProv) == Layout.scaleNotesCustom
                      ? 'Y：音阶级数'
                      : 'Y：半音数',
                  setValue: (int v) =>
                      ref.read(customIntervalYProv.notifier).setAndSave(v),
                  readValue: ref.watch(customIntervalYProv),
                ),
              if (resizableGrid) const DividerTitle('网格尺寸'),
              if (resizableGrid)
                IntCounterTile(
                  label: '宽度',
                  setValue: (int v) =>
                      ref.read(widthProv.notifier).setAndSave(v),
                  readValue: ref.watch(widthProv),
                ),
              if (resizableGrid)
                IntCounterTile(
                  label: '高度',
                  setValue: (int v) =>
                      ref.read(heightProv.notifier).setAndSave(v),
                  readValue: ref.watch(heightProv),
                ),
              if (resizableGrid && ref.watch(layoutProv) != Layout.progrChange)
                const DividerTitle('音阶'),
              if (resizableGrid && ref.watch(layoutProv) != Layout.progrChange)
                ListTile(title: const Text('音阶'), trailing: dropdownScale),
              if (resizableGrid && ref.watch(layoutProv) != Layout.progrChange)
                ListTile(
                  title: const Text('根音'),
                  subtitle: const Text('所选音阶的根音'),
                  trailing: dropdownRootNote,
                ),
              if (resizableGrid && ref.watch(layoutProv) != Layout.progrChange)
                ListTile(
                  title: const Text('起始音符'),
                  subtitle: const Text('网格左下角的最低音符'),
                  trailing: dropdownBaseNote,
                ),
              if (resizableGrid && ref.watch(layoutProv) != Layout.progrChange)
                IntCounterTile(
                  label: '八度',
                  modDisplay: (v) => '${v - 2}',
                  readValue: ref.watch(baseOctaveProv),
                  setValue: (int v) =>
                      ref.read(baseOctaveProv.notifier).setAndSave(v),
                  resetFunction: ref.read(baseOctaveProv.notifier).reset,
                ),
              /////////////////////////////////////
              const DividerTitle('演奏控制'),
              if (resizableGrid)
                ListTile(
                  title: const Text('八度按钮'),
                  subtitle: const Text(
                    '在鼓垫旁显示八度升降按钮',
                  ),
                  trailing: Switch(
                    value: ref.watch(octaveButtonsProv),
                    onChanged: (bool v) =>
                        ref.read(octaveButtonsProv.notifier).setAndSave(v),
                  ),
                ),
              ListTile(
                title: const Text('延音按钮'),
                subtitle: const Text(
                  '在鼓垫旁显示延音按钮；双击可锁定延音',
                ),
                trailing: Switch(
                  value: ref.watch(sustainButtonProv),
                  onChanged: (bool v) =>
                      ref.read(sustainButtonProv.notifier).setAndSave(v),
                ),
              ),
              ListTile(
                title: const Text('力度'),
                subtitle: const Text('在鼓垫旁显示力度滑杆'),
                trailing: Switch(
                  value: ref.watch(velocitySliderProv),
                  onChanged: (bool v) =>
                      ref.read(velocitySliderProv.notifier).setAndSave(v),
                ),
              ),
              ListTile(
                title: const Text('调制轮'),
                subtitle: const Text('在鼓垫旁显示调制轮滑杆'),
                trailing: Switch(
                  value: ref.watch<bool>(modWheelProv),
                  onChanged: (bool v) =>
                      ref.read(modWheelProv.notifier).setAndSave(v),
                ),
              ),
              ListTile(
                title: const Text('弯音'),
                subtitle: const Text('在鼓垫旁显示弯音滑杆'),
                trailing: Switch(
                  value: ref.watch(pitchBendProv),
                  onChanged: (bool v) =>
                      ref.read(pitchBendProv.notifier).setAndSave(v),
                ),
              ),
              if (ref.watch(pitchBendProv))
                ColoredBox(
                  color: Palette.dirtyTranslucent,
                  child: NonLinearSliderTile(
                    label: '弯音回中',
                    subtitle:
                        '设置松手后弯音滑杆平滑回到中心的时间',
                    readValue: ref.watch(pitchBendEaseStepProv),
                    setValue: (int v) =>
                        ref.read(pitchBendEaseStepProv.notifier).set(v),
                    resetFunction: ref
                        .read(pitchBendEaseStepProv.notifier)
                        .reset,
                    displayValue: ref.watch(pitchBendEaseUsable) == 0
                        ? '关闭'
                        : ref.watch(pitchBendEaseUsable) < 1000
                        ? '${ref.watch(pitchBendEaseUsable)} ms'
                        : '${ref.watch(pitchBendEaseUsable) / 1000} s',
                    steps: Timing.releaseDelayTimes.length - 1,
                    onChangeEnd: ref.read(pitchBendEaseStepProv.notifier).save,
                  ),
                ),
              /////////////////////////////////////
              const DividerTitle('显示'),
              ListTile(
                title: const Text('配色模式'),
                subtitle: const Text('设置色轮如何映射到音符'),
                trailing: DropdownEnum<PadColors>(
                  values: PadColors.values,
                  readValue: ref.watch(padColorsProv),
                  setValue: (PadColors v) =>
                      ref.read(padColorsProv.notifier).setAndSave(v),
                ),
              ),
              if (ref.watch(padColorsProv) != PadColors.pianoKeys &&
                  ref.watch(padColorsProv) != PadColors.neutral)
                IntSliderTile(
                  label: '基准颜色',
                  max: 360,
                  subtitle: '旋转整体色轮',
                  trailing: ref.watch(baseHueProv).toString(),
                  readValue: ref.watch(baseHueProv),
                  setValue: (int v) => ref.read(baseHueProv.notifier).set(v),
                  resetValue: ref.read(baseHueProv.notifier).reset,
                  onChangeEnd: ref.read(baseHueProv.notifier).save,
                ),
              ListTile(
                title: const Text('鼓垫标签'),
                subtitle: const Text(
                  '选择显示 MIDI 数值或音名',
                ),
                trailing: DropdownEnum<PadLabels>(
                  values: PadLabels.values,
                  readValue: ref.watch<PadLabels>(padLabelsProv),
                  setValue: (PadLabels v) =>
                      ref.read(padLabelsProv.notifier).setAndSave(v),
                ),
              ),
              ListTile(
                title: const Text('GM 打击乐名称'),
                subtitle: const Text(
                  '在鼓垫上显示 General MIDI 标准打击乐名称',
                ),
                trailing: Switch(
                  value: ref.watch(gmLabelsProv),
                  onChanged: (bool v) =>
                      ref.read(gmLabelsProv.notifier).setAndSave(v),
                ),
              ),
              ListTile(
                title: const Text('显示力度反馈'),
                subtitle: const Text(
                  '在鼓垫上可视化显示实际发送的力度',
                ),
                trailing: Switch(
                  value: ref.watch(velocityVisualProv),
                  onChanged: (bool v) {
                    ref.read(velocityVisualProv.notifier).setAndSave(v);
                  },
                ),
              ),
              /////////////////////////////////////
              const DividerTitle('方向'),
              ListTile(
                title: const Text('水平翻转'),
                // subtitle: const Text('Mirror'),
                trailing: Switch(
                  value: ref.watch(flipLayoutHorizontalProv),
                  onChanged: (bool v) =>
                      ref.read(flipLayoutHorizontalProv.notifier).setAndSave(v),
                ),
              ),
              ListTile(
                title: const Text('垂直翻转'),
                trailing: Switch(
                  value: ref.watch(flipLayoutVerticalProv),
                  onChanged: (bool v) =>
                      ref.read(flipLayoutVerticalProv.notifier).setAndSave(v),
                ),
              ),
              const DividerTitle('实验功能'),
              ListTile(
                title: const Text('三和弦圆'),
                subtitle: const Text(
                  '更适合西方调式音阶',
                ),
                trailing: Switch(
                  value: ref.watch(triadCirclesProv),
                  onChanged: (bool v) =>
                      ref.read(triadCirclesProv.notifier).setAndSave(v),
                ),
              ),
              SizedBox(height: 50),
            ],
          ),
        ),
      ],
    );
  }
}
