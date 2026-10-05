import 'package:beat_pads/screen_pads_menu/_screen_pads_menu.dart';
import 'package:beat_pads/screen_pads_menu/box_credits.dart';
import 'package:beat_pads/screen_pads_menu/switch_wake_lock.dart';
import 'package:beat_pads/services/services.dart';
import 'package:beat_pads/shared_components/_shared.dart';
import 'package:beat_pads/shared_components/divider_title.dart';
import 'package:beat_pads/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MenuSystem extends ConsumerWidget {
  const MenuSystem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: ThemeConst.listViewBottomPadding),
      children: <Widget>[
        const DividerTitle('系统'),
        const SwitchWakeLockTile(),
        ListTile(
          title: const Text('滑杆轨道可直接触控'),
          subtitle: const Text(
            '点击滑杆轨道任意位置即可直接移动滑块',
          ),
          trailing: Switch(
            value: ref.watch(sliderTapAndSlideProv),
            onChanged: (bool v) =>
                ref.read(sliderTapAndSlideProv.notifier).setAndSave(v),
          ),
        ),
        ListTile(
          title: const Text('显示启动画面'),
          subtitle: const Text('应用启动时显示动画启动页'),
          trailing: Switch(
            value: ref.watch(splashScreenProv),
            onChanged: (bool v) =>
                ref.read(splashScreenProv.notifier).setAndSave(v),
          ),
        ),
        const DividerTitle('重置'),
        const SizedBox(height: 20),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: ThemeConst.menuButtonMinWidth,
            ),
            child: SnackMessageButton(
              label: '重置 MIDI 缓冲区',
              message: 'MIDI 缓冲区已清空，并已发送“关闭全部音符”',
              onPressed: () {
                ref.read(rxNoteProvider.notifier).reset();
                MidiUtils.sendAllNotesOffMessage(ref.read(channelUsableProv));
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: ThemeConst.menuButtonMinWidth,
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Palette.lightPink,
              ),
              child: const Text('重置全部预设'),
              onPressed: () {
                showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: const Text('重置'),
                    content: const Text(
                      '将全部预设恢复为默认值？',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'Cancel'),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context, 'OK');
                          ref.read(resetAllProv.notifier).resetAllPresets();
                          ref.read(selectedMenuState.notifier).state =
                              Menu.layout;
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

        const SizedBox(height: 20),

        const StringInfoBox(
          header: '致谢',
          body: [
            '感谢以下用户提供的宝贵反馈：',
            'Samplix,  A. Samek,  Gavinski,  tyslothrop1,  tput73,  bruques',
            '也感谢所有未能逐一列出的贡献者！',
          ],
        ),
        const CreditsBox(),
        SizedBox(height: 50),
      ],
    );
  }
}
