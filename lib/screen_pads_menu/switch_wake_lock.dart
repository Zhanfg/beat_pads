import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final _wakeLockProv = StateProvider<bool>((ref) => false);

class SwitchWakeLockTile extends ConsumerWidget {
  const SwitchWakeLockTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: const Text('保持屏幕常亮'),
      subtitle: const Text('演奏时阻止屏幕自动熄灭'),
      trailing: Switch(
        value: ref.watch(_wakeLockProv),
        onChanged: (v) {
          ref.read(_wakeLockProv.notifier).state = v;
          WakelockPlus.toggle(enable: v);
        },
      ),
    );
  }
}
