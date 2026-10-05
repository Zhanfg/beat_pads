import 'dart:async';
import 'dart:math' as math;

import 'package:beat_pads/screen_midi_devices/_drawer_devices.dart';
import 'package:beat_pads/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _TouchInstrument {
  keyboard('键盘', Icons.piano),
  drums('鼓组', Icons.grid_view_rounded),
  smartChords('智能和弦', Icons.library_music_rounded),
  arpeggiator('琶音器', Icons.graphic_eq_rounded),
  smartDrums('智能鼓机', Icons.auto_awesome_rounded),
  beatSequencer('节拍音序器', Icons.grid_on_rounded),
  liveLoops('现场循环', Icons.view_module_rounded);

  const _TouchInstrument(this.label, this.icon);

  final String label;
  final IconData icon;
}


class FlStudioScreen extends ConsumerStatefulWidget {
  const FlStudioScreen({super.key});

  @override
  ConsumerState<FlStudioScreen> createState() => _FlStudioScreenState();
}

class _FlStudioScreenState extends ConsumerState<FlStudioScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _TouchInstrument _instrument = _TouchInstrument.keyboard;
  int _keyboardBaseNote = 48;
  int _fpcBaseNote = 36;
  double _pitch = 0;
  double _mod = 0;
  bool _sustain = false;

  int get _channel => ref.read(channelUsableProv);
  int get _velocity => ref.read(velocityProv);

  @override
  void dispose() {
    final channel = _channel;
    MidiUtils.sendSustainMessage(channel, state: false);
    MidiUtils.sendAllNotesOffMessage(channel);
    PitchBendMessage(channel: channel).send();
    super.dispose();
  }

  void _noteOn(int note, {int? velocity}) {
    NoteOnMessage(
      channel: _channel,
      note: note.clamp(0, 127).toInt(),
      velocity: (velocity ?? _velocity).clamp(1, 127).toInt(),
    ).send();
  }

  void _noteOff(int note) {
    NoteOffMessage(channel: _channel, note: note.clamp(0, 127).toInt()).send();
  }

  void _setPitch(double value) {
    setState(() => _pitch = value);
    PitchBendMessage(channel: _channel, bend: value).send();
  }

  void _resetPitch() {
    setState(() => _pitch = 0);
    PitchBendMessage(channel: _channel).send();
  }

  void _setMod(double value) {
    setState(() => _mod = value);
    MidiUtils.sendModWheelMessage(_channel, value.round());
  }

  void _setSustain(bool enabled) {
    setState(() => _sustain = enabled);
    MidiUtils.sendSustainMessage(_channel, state: enabled);
  }

  Future<void> _sendMomentaryCc(int controller) async {
    final channel = _channel;
    CCMessage(channel: channel, controller: controller, value: 127).send();
    await Future<void>.delayed(const Duration(milliseconds: 24));
    CCMessage(channel: channel, controller: controller, value: 0).send();
  }

  void _panic() {
    HapticFeedback.mediumImpact();
    _setSustain(false);
    _resetPitch();
    MidiUtils.sendAllNotesOffMessage(_channel);
  }

  void _sendCc(int controller, int value) {
    CCMessage(
      channel: _channel,
      controller: controller.clamp(0, 127).toInt(),
      value: value.clamp(0, 127).toInt(),
    ).send();
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectedDevicesProv);
    final channel = ref.watch(channelUsableProv);
    final velocity = ref.watch(velocityProv);
    final scale = ref.watch(flScaleProvider);
    final scaleRoot = ref.watch(flScaleRootProvider);
    final scaleLock = ref.watch(flScaleLockProvider);
    final touchDynamics = ref.watch(flTouchDynamicsProvider);
    final tempo = ref.watch(flTempoProvider);

    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4A90E2),
      brightness: Brightness.dark,
      surface: const Color(0xFF171717),
    );
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF111111),
      dividerColor: Colors.white12,
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
    );

    final controls = _ControlArea(
      pitch: _pitch,
      mod: _mod,
      sustain: _sustain,
      channel: channel,
      velocity: velocity,
      onPitchChanged: _setPitch,
      onPitchEnd: _resetPitch,
      onModChanged: _setMod,
      onSustainChanged: _setSustain,
      onCc: _sendCc,
      onPanic: _panic,
    );

    void showControls() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: scheme.surface,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.88,
              child: SingleChildScrollView(child: controls),
            ),
          );
        },
      );
    }

    void showInstrumentBrowser() {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: scheme.surface,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '触控乐器',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  for (final item in _TouchInstrument.values) ...[
                    _InstrumentBrowserTile(
                      instrument: item,
                      selected: item == _instrument,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _instrument = item);
                        Navigator.pop(sheetContext);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }

    Widget instrumentView() {
      switch (_instrument) {
        case _TouchInstrument.keyboard:
          return _KeyboardInstrumentView(
            baseNote: _keyboardBaseNote,
            velocity: velocity,
            scale: scale,
            scaleRoot: scaleRoot,
            scaleLock: scaleLock,
            touchDynamics: touchDynamics,
            sustain: _sustain,
            onSustainChanged: _setSustain,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
            onOctaveDown: () {
              setState(() {
                _keyboardBaseNote =
                    (_keyboardBaseNote - 12).clamp(0, 96).toInt();
              });
            },
            onOctaveUp: () {
              setState(() {
                _keyboardBaseNote =
                    (_keyboardBaseNote + 12).clamp(0, 96).toInt();
              });
            },
          );
        case _TouchInstrument.drums:
          return _DrumsInstrumentView(
            baseNote: _fpcBaseNote,
            velocity: velocity,
            touchDynamics: touchDynamics,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
            onBankDown: () {
              setState(() {
                _fpcBaseNote = (_fpcBaseNote - 16).clamp(0, 111).toInt();
              });
            },
            onBankUp: () {
              setState(() {
                _fpcBaseNote = (_fpcBaseNote + 16).clamp(0, 111).toInt();
              });
            },
          );
        case _TouchInstrument.smartChords:
          return _SmartChordsView(
            scale: scale,
            scaleRoot: scaleRoot,
            velocity: velocity,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
          );
        case _TouchInstrument.arpeggiator:
          return _ArpeggiatorView(
            tempo: tempo,
            scale: scale,
            scaleRoot: scaleRoot,
            velocity: velocity,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
          );
        case _TouchInstrument.smartDrums:
          return _SmartDrumsView(
            tempo: tempo,
            velocity: velocity,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
          );
        case _TouchInstrument.beatSequencer:
          return _BeatSequencerView(
            tempo: tempo,
            velocity: velocity,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
          );
        case _TouchInstrument.liveLoops:
          return _LiveLoopsView(
            velocity: velocity,
            onNoteOn: _noteOn,
            onNoteOff: _noteOff,
          );
      }
    }

    return Theme(
      data: theme,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const Drawer(child: MidiConfig()),
        body: SafeArea(
          child: Column(
            children: [
              _GarageControlBar(
                instrument: _instrument,
                connectedCount: connected.length,
                onOpenInstrumentBrowser: showInstrumentBrowser,
                onOpenMidiDevices: () => _scaffoldKey.currentState?.openDrawer(),
                onGoToBeginning: () => _sendMomentaryCc(115),
                onPlay: () => _sendMomentaryCc(111),
                onStop: () => _sendMomentaryCc(112),
                onRecord: () => _sendMomentaryCc(110),
                onMetronome: () => _sendMomentaryCc(114),
                onControls: showControls,
                onPanic: _panic,
              ),
              const _MeasureRuler(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey(_instrument),
                    child: instrumentView(),
                  ),
                ),
              ),
              _InstrumentStatusBar(
                channel: channel,
                velocity: velocity,
                scale: scale,
                scaleRoot: scaleRoot,
                scaleLock: scaleLock,
                tempo: tempo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _GarageControlBar extends StatelessWidget {
  const _GarageControlBar({
    required this.instrument,
    required this.connectedCount,
    required this.onOpenInstrumentBrowser,
    required this.onOpenMidiDevices,
    required this.onGoToBeginning,
    required this.onPlay,
    required this.onStop,
    required this.onRecord,
    required this.onMetronome,
    required this.onControls,
    required this.onPanic,
  });

  final _TouchInstrument instrument;
  final int connectedCount;
  final VoidCallback onOpenInstrumentBrowser;
  final VoidCallback onOpenMidiDevices;
  final VoidCallback onGoToBeginning;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRecord;
  final VoidCallback onMetronome;
  final VoidCallback onControls;
  final VoidCallback onPanic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF202020),
      child: SizedBox(
        height: 54,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            return Row(
              children: [
                const SizedBox(width: 2),
                _BarButton(
                  tooltip: 'Touch Instruments',
                  onPressed: onOpenInstrumentBrowser,
                  icon: Icons.apps_rounded,
                ),
                _BarButton(
                  tooltip: 'MIDI 设备',
                  onPressed: onOpenMidiDevices,
                  icon: connectedCount > 0
                      ? Icons.usb_rounded
                      : Icons.usb_off_rounded,
                  foregroundColor:
                      connectedCount > 0 ? scheme.primary : null,
                ),
                if (!compact) ...[
                  const VerticalDivider(
                    width: 1,
                    indent: 11,
                    endIndent: 11,
                  ),
                  const SizedBox(width: 9),
                  Icon(instrument.icon, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    instrument.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
                const Spacer(),
                _BarButton(
                  tooltip: '回到开头 · CC115',
                  onPressed: onGoToBeginning,
                  icon: Icons.skip_previous_rounded,
                ),
                _BarButton(
                  tooltip: '停止 · CC112',
                  onPressed: onStop,
                  icon: Icons.stop_rounded,
                ),
                _BarButton(
                  tooltip: '播放 · CC111',
                  onPressed: onPlay,
                  icon: Icons.play_arrow_rounded,
                ),
                _BarButton(
                  tooltip: '录制 · CC110',
                  onPressed: onRecord,
                  icon: Icons.fiber_manual_record_rounded,
                  foregroundColor: scheme.error,
                ),
                if (!compact)
                  _BarButton(
                    tooltip: '节拍器 · CC114',
                    onPressed: onMetronome,
                    icon: Icons.timer_outlined,
                  ),
                const Spacer(),
                _BarButton(
                  tooltip: '轨道控制',
                  onPressed: onControls,
                  icon: Icons.tune_rounded,
                ),
                _BarButton(
                  tooltip: '紧急停止 / 关闭全部音符',
                  onPressed: onPanic,
                  icon: Icons.warning_amber_rounded,
                ),
                const SizedBox(width: 2),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.foregroundColor,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        maximumSize: const Size(42, 42),
        padding: const EdgeInsets.all(8),
        foregroundColor: foregroundColor,
      ),
      icon: Icon(icon, size: 21),
    );
  }
}

class _InstrumentBrowserTile extends StatelessWidget {
  const _InstrumentBrowserTile({
    required this.instrument,
    required this.selected,
    required this.onTap,
  });

  final _TouchInstrument instrument;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(instrument.icon, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  instrument.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (selected) const Icon(Icons.check_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeasureRuler extends StatelessWidget {
  const _MeasureRuler();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF191919),
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          for (int bar = 1; bar <= 8; bar++) ...[
            Expanded(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: 1,
                      height: bar.isOdd ? 11 : 7,
                      color: scheme.onSurface.withValues(alpha: 0.28),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    top: 4,
                    child: Text(
                      '$bar',
                      style: TextStyle(
                        fontSize: 9,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _InstrumentStatusBar extends StatelessWidget {
  const _InstrumentStatusBar({
    required this.channel,
    required this.velocity,
    required this.scale,
    required this.scaleRoot,
    required this.scaleLock,
    required this.tempo,
  });

  final int channel;
  final int velocity;
  final FlScale scale;
  final int scaleRoot;
  final bool scaleLock;
  final int tempo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final root = MidiUtils.getNoteName(
      scaleRoot + 60,
      showOctaveIndex: false,
    );
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B1B),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Text(
            '通道 ${channel + 1}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 12),
          Text(
            '力度 $velocity',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 12),
          Text(
            'BPM $tempo',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Spacer(),
          Icon(
            scaleLock ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 13,
            color: scaleLock ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            '$root · ${scale.label}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _KeyboardInstrumentView extends StatelessWidget {
  const _KeyboardInstrumentView({
    required this.baseNote,
    required this.velocity,
    required this.scale,
    required this.scaleRoot,
    required this.scaleLock,
    required this.touchDynamics,
    required this.sustain,
    required this.onSustainChanged,
    required this.onNoteOn,
    required this.onNoteOff,
    required this.onOctaveDown,
    required this.onOctaveUp,
  });

  final int baseNote;
  final int velocity;
  final FlScale scale;
  final int scaleRoot;
  final bool scaleLock;
  final bool touchDynamics;
  final bool sustain;
  final ValueChanged<bool> onSustainChanged;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;
  final VoidCallback onOctaveDown;
  final VoidCallback onOctaveUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '降低八度',
                  onPressed: onOctaveDown,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(MidiUtils.getNoteName(baseNote)),
                ),
                IconButton(
                  tooltip: '升高八度',
                  onPressed: onOctaveUp,
                  icon: const Icon(Icons.add_rounded),
                ),
                const Spacer(),
                FilterChip(
                  label: const Text('延音'),
                  avatar: const Icon(Icons.pedal_bike_rounded, size: 14),
                  selected: sustain,
                  onSelected: onSustainChanged,
                ),
                const SizedBox(width: 8),
                if (scaleLock)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.lock_rounded, size: 14),
                    label: Text(scale.label),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _PianoKeyboard(
                baseNote: baseNote,
                noteCount: 37,
                velocity: velocity,
                scale: scale,
                scaleRoot: scaleRoot,
                scaleLock: scaleLock,
                touchDynamics: touchDynamics,
                onNoteOn: onNoteOn,
                onNoteOff: onNoteOff,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrumsInstrumentView extends StatelessWidget {
  const _DrumsInstrumentView({
    required this.baseNote,
    required this.velocity,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
    required this.onBankDown,
    required this.onBankUp,
  });

  final int baseNote;
  final int velocity;
  final bool touchDynamics;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;
  final VoidCallback onBankDown;
  final VoidCallback onBankUp;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '鼓组',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '上一组鼓垫',
                  onPressed: onBankDown,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('$baseNote–${baseNote + 15}'),
                IconButton(
                  tooltip: '下一组鼓垫',
                  onPressed: onBankUp,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _FpcGrid(
                baseNote: baseNote,
                velocity: velocity,
                touchDynamics: touchDynamics,
                onNoteOn: onNoteOn,
                onNoteOff: onNoteOff,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartChordsView extends StatelessWidget {
  const _SmartChordsView({
    required this.scale,
    required this.scaleRoot,
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final FlScale scale;
  final int scaleRoot;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  List<int> _intervals() {
    if (scale == FlScale.chromatic) {
      return const <int>[0, 2, 4, 5, 7, 9, 11];
    }
    return scale.intervals;
  }

  List<int> _chordForDegree(int degree) {
    final intervals = _intervals();
    final notes = <int>[];
    for (final offset in const <int>[0, 2, 4]) {
      final rawIndex = degree + offset;
      final wrapped = rawIndex % intervals.length;
      final octave = rawIndex ~/ intervals.length;
      notes.add(48 + scaleRoot + intervals[wrapped] + octave * 12);
    }
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    final intervals = _intervals();
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '智能和弦',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Text(
              scale == FlScale.chromatic
                  ? '默认使用大调和弦；可在“轨道控制”中切换音阶与调式'
                  : '和弦条跟随 ${scale.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal =
                      constraints.maxWidth > constraints.maxHeight * 1.25;
                  final count = horizontal ? intervals.length : 2;
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: intervals.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: horizontal ? 0.72 : 2.6,
                    ),
                    itemBuilder: (context, degree) {
                      final chord = _chordForDegree(degree);
                      final root = MidiUtils.getNoteName(
                        chord.first,
                        showOctaveIndex: false,
                      );
                      return _ChordPad(
                        label: root,
                        degree: degree + 1,
                        notes: chord,
                        velocity: velocity,
                        onNoteOn: onNoteOn,
                        onNoteOff: onNoteOff,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChordPad extends StatefulWidget {
  const _ChordPad({
    required this.label,
    required this.degree,
    required this.notes,
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final String label;
  final int degree;
  final List<int> notes;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_ChordPad> createState() => _ChordPadState();
}

class _ChordPadState extends State<_ChordPad> {
  bool _active = false;

  void _down(PointerDownEvent event) {
    if (_active) return;
    HapticFeedback.selectionClick();
    for (final note in widget.notes) {
      widget.onNoteOn(note, velocity: widget.velocity);
    }
    setState(() => _active = true);
  }

  void _up() {
    if (!_active) return;
    for (final note in widget.notes) {
      widget.onNoteOff(note);
    }
    if (mounted) setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 55),
        decoration: BoxDecoration(
          color:
              _active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _active ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              '第 ${widget.degree} 级',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}



class _ArpeggiatorView extends StatefulWidget {
  const _ArpeggiatorView({
    required this.tempo,
    required this.scale,
    required this.scaleRoot,
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int tempo;
  final FlScale scale;
  final int scaleRoot;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_ArpeggiatorView> createState() => _ArpeggiatorViewState();
}

class _ArpeggiatorViewState extends State<_ArpeggiatorView> {
  Timer? _timer;
  int _degree = 0;
  int _rate = 16;
  int _octaves = 2;
  int _index = 0;
  bool _running = false;
  String _order = '上行';
  final math.Random _random = math.Random();

  List<int> get _scaleIntervals => widget.scale == FlScale.chromatic
      ? const <int>[0, 2, 4, 5, 7, 9, 11]
      : widget.scale.intervals;

  List<int> _sequence() {
    final intervals = _scaleIntervals;
    final triad = <int>[];
    for (final offset in const <int>[0, 2, 4]) {
      final raw = _degree + offset;
      final wrapped = raw % intervals.length;
      final octave = raw ~/ intervals.length;
      triad.add(48 + widget.scaleRoot + intervals[wrapped] + octave * 12);
    }
    final result = <int>[];
    for (int octave = 0; octave < _octaves; octave++) {
      result.addAll(triad.map((note) => note + octave * 12));
    }
    if (_order == '下行') return result.reversed.toList();
    if (_order == '上下行' && result.length > 2) {
      return <int>[
        ...result,
        ...result.sublist(1, result.length - 1).reversed,
      ];
    }
    return result;
  }

  Duration _stepDuration() {
    final ms = (60000 / widget.tempo * (4 / _rate)).round();
    return Duration(milliseconds: ms.clamp(35, 1500));
  }

  void _restart() {
    _timer?.cancel();
    if (!_running) return;
    final duration = _stepDuration();
    _timer = Timer.periodic(duration, (_) => _tick(duration));
  }

  void _tick(Duration duration) {
    final sequence = _sequence();
    if (sequence.isEmpty) return;
    final note = _order == '随机'
        ? sequence[_random.nextInt(sequence.length)]
        : sequence[_index % sequence.length];
    _index = (_index + 1) % sequence.length;
    widget.onNoteOn(note, velocity: widget.velocity);
    Future<void>.delayed(
      Duration(milliseconds: (duration.inMilliseconds * 0.72).round()),
      () => widget.onNoteOff(note),
    );
  }

  void _selectDegree(int degree) {
    setState(() {
      _degree = degree;
      _index = 0;
      _running = true;
    });
    _restart();
  }

  @override
  void didUpdateWidget(covariant _ArpeggiatorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_running && oldWidget.tempo != widget.tempo) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final intervals = _scaleIntervals;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('琶音器', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 10),
                Chip(label: Text('${widget.tempo} BPM')),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: _running ? '停止琶音' : '继续琶音',
                  onPressed: () {
                    setState(() => _running = !_running);
                    _restart();
                  },
                  icon: Icon(
                    _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '点击音级后锁定并持续演奏；再次选择音级可实时转调。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in <int>[8, 16, 32])
                  ChoiceChip(
                    label: Text('1/$value'),
                    selected: _rate == value,
                    onSelected: (_) {
                      setState(() => _rate = value);
                      _restart();
                    },
                  ),
                for (final value in <String>['上行', '下行', '上下行', '随机'])
                  ChoiceChip(
                    label: Text(value),
                    selected: _order == value,
                    onSelected: (_) {
                      setState(() {
                        _order = value;
                        _index = 0;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('八度范围'),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 4,
                    divisions: 3,
                    value: _octaves.toDouble(),
                    label: '$_octaves',
                    onChanged: (value) {
                      setState(() {
                        _octaves = value.round();
                        _index = 0;
                      });
                    },
                  ),
                ),
                Text('$_octaves'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: intervals.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: math.min(intervals.length, 7),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (context, degree) {
                  final midi = 60 + widget.scaleRoot + intervals[degree];
                  final name = MidiUtils.getNoteName(
                    midi,
                    showOctaveIndex: false,
                  );
                  return FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: degree == _degree && _running
                          ? scheme.primaryContainer
                          : null,
                    ),
                    onPressed: () => _selectDegree(degree),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text('第 ${degree + 1} 级'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartDrumsView extends StatefulWidget {
  const _SmartDrumsView({
    required this.tempo,
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int tempo;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_SmartDrumsView> createState() => _SmartDrumsViewState();
}

class _SmartDrumsViewState extends State<_SmartDrumsView> {
  static const List<int> _notes = <int>[36, 38, 42, 39];
  static const List<String> _labels = <String>['底鼓', '军鼓', '踩镲', '拍手'];
  static const List<IconData> _icons = <IconData>[
    Icons.album_rounded,
    Icons.circle_outlined,
    Icons.change_history_rounded,
    Icons.front_hand_rounded,
  ];

  Timer? _timer;
  bool _running = false;
  int _step = 0;
  List<Offset> _positions = <Offset>[
    const Offset(0.28, 0.58),
    const Offset(0.46, 0.42),
    const Offset(0.68, 0.26),
    const Offset(0.58, 0.64),
  ];
  final math.Random _random = math.Random();

  Duration get _stepDuration => Duration(
        milliseconds: (60000 / widget.tempo / 4).round().clamp(35, 1500),
      );

  void _restart() {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer.periodic(_stepDuration, (_) => _tick());
  }

  bool _shouldHit(int index, Offset pos) {
    final complexity = (pos.dx * 3).round().clamp(0, 3);
    final patterns = <List<int>>[
      <int>[0, 8],
      <int>[0, 4, 8, 12],
      <int>[0, 3, 4, 7, 8, 11, 12, 15],
      List<int>.generate(16, (i) => i),
    ];
    final step = (_step + <int>[0, 4, 0, 12][index]) % 16;
    return patterns[complexity].contains(step);
  }

  void _tick() {
    for (int i = 0; i < _positions.length; i++) {
      final pos = _positions[i];
      if (!_shouldHit(i, pos)) continue;
      final intensity = (1 - pos.dy).clamp(0.0, 1.0);
      final velocity =
          (28 + intensity * 99).round().clamp(1, 127).toInt();
      final note = _notes[i];
      widget.onNoteOn(note, velocity: velocity);
      Future<void>.delayed(
        const Duration(milliseconds: 48),
        () => widget.onNoteOff(note),
      );
    }
    if (mounted) setState(() => _step = (_step + 1) % 16);
  }

  void _randomize() {
    setState(() {
      _positions = List<Offset>.generate(
        4,
        (_) => Offset(
          0.12 + _random.nextDouble() * 0.78,
          0.10 + _random.nextDouble() * 0.78,
        ),
      );
    });
  }

  @override
  void didUpdateWidget(covariant _SmartDrumsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_running && oldWidget.tempo != widget.tempo) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text('智能鼓机', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Chip(label: Text('${widget.tempo} BPM')),
                const Spacer(),
                IconButton(
                  tooltip: '随机生成',
                  onPressed: _randomize,
                  icon: const Icon(Icons.casino_rounded),
                ),
                IconButton(
                  tooltip: '重置',
                  onPressed: () => setState(() {
                    _positions = <Offset>[
                      const Offset(0.28, 0.58),
                      const Offset(0.46, 0.42),
                      const Offset(0.68, 0.26),
                      const Offset(0.58, 0.64),
                    ];
                  }),
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
                IconButton.filled(
                  tooltip: _running ? '停止' : '播放',
                  onPressed: () {
                    setState(() => _running = !_running);
                    _restart();
                  },
                  icon: Icon(
                    _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Stack(
                      children: [
                        for (int i = 1; i < 4; i++) ...[
                          Positioned(
                            left: size.width * i / 4,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 1,
                              color: scheme.outlineVariant,
                            ),
                          ),
                          Positioned(
                            top: size.height * i / 4,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1,
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ],
                        const Positioned(
                          left: 10,
                          top: 8,
                          child: Text('更响 ↑'),
                        ),
                        const Positioned(
                          right: 10,
                          bottom: 8,
                          child: Text('更复杂 →'),
                        ),
                        for (int i = 0; i < _positions.length; i++)
                          Positioned(
                            left: _positions[i].dx * (size.width - 58),
                            top: _positions[i].dy * (size.height - 58),
                            child: GestureDetector(
                              onTap: () {
                                final note = _notes[i];
                                widget.onNoteOn(
                                  note,
                                  velocity: widget.velocity,
                                );
                                Future<void>.delayed(
                                  const Duration(milliseconds: 70),
                                  () => widget.onNoteOff(note),
                                );
                              },
                              onPanUpdate: (details) {
                                setState(() {
                                  final current = _positions[i];
                                  _positions[i] = Offset(
                                    (current.dx +
                                            details.delta.dx /
                                                math.max(1, size.width - 58))
                                        .clamp(0.0, 1.0),
                                    (current.dy +
                                            details.delta.dy /
                                                math.max(1, size.height - 58))
                                        .clamp(0.0, 1.0),
                                  );
                                });
                              },
                              child: Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: scheme.primary),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_icons[i], size: 20),
                                    const SizedBox(height: 2),
                                    Text(
                                      _labels[i],
                                      style:
                                          Theme.of(context).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatSequencerView extends StatefulWidget {
  const _BeatSequencerView({
    required this.tempo,
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int tempo;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_BeatSequencerView> createState() => _BeatSequencerViewState();
}

class _BeatSequencerViewState extends State<_BeatSequencerView> {
  static const List<int> _notes = <int>[36, 38, 42, 39];
  static const List<String> _labels = <String>['底鼓', '军鼓', '踩镲', '拍手'];
  Timer? _timer;
  bool _running = false;
  int _step = 0;
  late List<List<bool>> _grid;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _grid = List<List<bool>>.generate(
      4,
      (row) => List<bool>.generate(16, (step) {
        if (row == 0) return step % 4 == 0;
        if (row == 1) return step == 4 || step == 12;
        if (row == 2) return step.isEven;
        return step == 12;
      }),
    );
  }

  Duration get _stepDuration => Duration(
        milliseconds: (60000 / widget.tempo / 4).round().clamp(35, 1500),
      );

  void _restart() {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer.periodic(_stepDuration, (_) => _tick());
  }

  void _tick() {
    for (int row = 0; row < _grid.length; row++) {
      if (!_grid[row][_step]) continue;
      final note = _notes[row];
      widget.onNoteOn(note, velocity: widget.velocity);
      Future<void>.delayed(
        const Duration(milliseconds: 45),
        () => widget.onNoteOff(note),
      );
    }
    if (mounted) setState(() => _step = (_step + 1) % 16);
  }

  @override
  void didUpdateWidget(covariant _BeatSequencerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_running && oldWidget.tempo != widget.tempo) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _randomize() {
    setState(() {
      for (int row = 0; row < _grid.length; row++) {
        final probability = <double>[0.28, 0.18, 0.48, 0.16][row];
        for (int step = 0; step < 16; step++) {
          _grid[row][step] = _random.nextDouble() < probability;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text('节拍音序器', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Chip(label: Text('${widget.tempo} BPM · 1/16')),
                const Spacer(),
                IconButton(
                  tooltip: '随机生成',
                  onPressed: _randomize,
                  icon: const Icon(Icons.casino_rounded),
                ),
                IconButton(
                  tooltip: '清空',
                  onPressed: () => setState(() {
                    _grid = List<List<bool>>.generate(
                      4,
                      (_) => List<bool>.filled(16, false),
                    );
                  }),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton.filled(
                  tooltip: _running ? '停止' : '播放',
                  onPressed: () {
                    setState(() => _running = !_running);
                    _restart();
                  },
                  icon: Icon(
                    _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 720,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 64),
                          for (int step = 0; step < 16; step++)
                            SizedBox(
                              width: 40,
                              child: Center(
                                child: Text(
                                  '${step + 1}',
                                  style:
                                      Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (int row = 0; row < 4; row++) ...[
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  _labels[row],
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                              for (int step = 0; step < 16; step++)
                                SizedBox(
                                  width: 40,
                                  height: double.infinity,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      onTap: () {
                                        setState(() =>
                                            _grid[row][step] =
                                                !_grid[row][step]);
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 55),
                                        decoration: BoxDecoration(
                                          color: _grid[row][step]
                                              ? step == _step && _running
                                                  ? scheme.primary
                                                  : scheme.primaryContainer
                                              : step == _step && _running
                                                  ? scheme
                                                      .surfaceContainerHighest
                                                  : scheme.surfaceContainerLow,
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          border: Border.all(
                                            color: step % 4 == 0
                                                ? scheme.outline
                                                : scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLoopsView extends StatefulWidget {
  const _LiveLoopsView({
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_LiveLoopsView> createState() => _LiveLoopsViewState();
}

class _LiveLoopsViewState extends State<_LiveLoopsView> {
  static const int _rows = 4;
  static const int _columns = 5;
  late List<List<bool>> _active;

  @override
  void initState() {
    super.initState();
    _active = List<List<bool>>.generate(
      _rows,
      (_) => List<bool>.filled(_columns, false),
    );
  }

  int _noteFor(int row, int column) => 60 + row * _columns + column;

  void _trigger(int row, int column) {
    final note = _noteFor(row, column);
    widget.onNoteOn(note, velocity: widget.velocity);
    Future<void>.delayed(
      const Duration(milliseconds: 70),
      () => widget.onNoteOff(note),
    );
    setState(() {
      for (int c = 0; c < _columns; c++) {
        _active[row][c] = c == column;
      }
    });
  }

  void _launchScene(int column) {
    HapticFeedback.mediumImpact();
    for (int row = 0; row < _rows; row++) {
      _trigger(row, column);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('现场循环', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              'MIDI 触发矩阵：可将每个格子的音符映射到 FL Studio Performance Mode、Clip 或场景。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 62),
                      for (int column = 0;
                          column < _columns;
                          column++)
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 3),
                            child: FilledButton.tonal(
                              onPressed: () => _launchScene(column),
                              child: Text('场景 ${column + 1}'),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (int row = 0; row < _rows; row++)
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 62,
                            child: Text(
                              '轨道 ${row + 1}',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          for (int column = 0;
                              column < _columns;
                              column++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(11),
                                  onTap: () => _trigger(row, column),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 90),
                                    decoration: BoxDecoration(
                                      color: _active[row][column]
                                          ? scheme.primaryContainer
                                          : scheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: _active[row][column]
                                            ? scheme.primary
                                            : scheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _active[row][column]
                                              ? Icons.play_arrow_rounded
                                              : Icons
                                                  .play_circle_outline_rounded,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'N${_noteFor(row, column)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlArea extends ConsumerWidget {
  const _ControlArea({
    required this.pitch,
    required this.mod,
    required this.sustain,
    required this.channel,
    required this.velocity,
    required this.onPitchChanged,
    required this.onPitchEnd,
    required this.onModChanged,
    required this.onSustainChanged,
    required this.onCc,
    required this.onPanic,
  });

  final double pitch;
  final double mod;
  final bool sustain;
  final int channel;
  final int velocity;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onPitchEnd;
  final ValueChanged<double> onModChanged;
  final ValueChanged<bool> onSustainChanged;
  final void Function(int controller, int value) onCc;
  final VoidCallback onPanic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tempo = ref.watch(flTempoProvider);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        _SectionCard(
          title: '轨道',
          child: Row(
            children: [
              Expanded(child: _Metric(label: '通道', value: '${channel + 1}')),
              const SizedBox(width: 8),
              Expanded(child: _Metric(label: '力度', value: '$velocity')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '乐曲设置',
          subtitle: '供琶音器、智能鼓机与节拍音序器使用。',
          child: Row(
            children: [
              const SizedBox(width: 46, child: Text('速度')),
              Expanded(
                child: Slider(
                  min: 40,
                  max: 240,
                  divisions: 200,
                  value: tempo.toDouble(),
                  onChanged: (value) {
                    ref
                        .read(flTempoProvider.notifier)
                        .setAndSave(value.round());
                  },
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '$tempo BPM',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StudioProfiles(),
        const SizedBox(height: 10),
        _SmartAssistCard(),
        const SizedBox(height: 10),
        _SectionCard(
          title: '混音效果',
          subtitle: '双轴连续控制；默认 X=CC74、Y=CC71。',
          child: _XyControlPad(
            onCc: onCc,
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '插件控制',
          subtitle: '4 个可重新指定的 CC 宏，可用于 FL Studio“链接到控制器”。',
          child: _MacroDeck(
            onCc: onCc,
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '键盘控制',
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 52, child: Text('弯音')),
                  Expanded(
                    child: Slider(
                      min: -1,
                      max: 1,
                      value: pitch,
                      onChanged: onPitchChanged,
                      onChangeEnd: (_) => onPitchEnd(),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text('${(pitch * 100).round()}%', textAlign: TextAlign.end),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 52, child: Text('调制')),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 127,
                      value: mod,
                      onChanged: onModChanged,
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text('${mod.round()}', textAlign: TextAlign.end),
                  ),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('延音 · CC64'),
                value: sustain,
                onChanged: onSustainChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            foregroundColor: scheme.error,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: onPanic,
          icon: const Icon(Icons.warning_amber_rounded),
          label: const Text('紧急停止 · 关闭全部音符'),
        ),
      ],
      ),
    );
  }
}


class _StudioProfiles extends ConsumerWidget {
  const _StudioProfiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(presetNotifierProvider);

    return _SectionCard(
      title: '场景',
      subtitle: '5 个持久化场景；MIDI 与通道设置会跟随当前场景。',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (int i = 1; i <= PresetNotfier.numberOfPresets; i++)
            ChoiceChip(
              label: Text('P$i'),
              selected: current == i,
              showCheckmark: false,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                ref.read(presetNotifierProvider.notifier).setAndSave(i);
              },
            ),
        ],
      ),
    );
  }
}

class _SmartAssistCard extends ConsumerWidget {
  const _SmartAssistCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(flScaleProvider);
    final root = ref.watch(flScaleRootProvider);
    final scaleLock = ref.watch(flScaleLockProvider);
    final touchDynamics = ref.watch(flTouchDynamicsProvider);

    return _SectionCard(
      title: '智能控制',
      subtitle: '演奏辅助全部在本机处理，不额外增加 MIDI 缓冲层。',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<FlScale>(
                  value: scale,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '音阶',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final item in FlScale.values)
                      DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    HapticFeedback.selectionClick();
                    ref.read(flScaleProvider.notifier).setAndSave(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 94,
                child: DropdownButtonFormField<int>(
                  value: root,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '根音',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (int note = 0; note < 12; note++)
                      DropdownMenuItem(
                        value: note,
                        child: Text(
                          MidiUtils.getNoteName(
                            note + 60,
                            showOctaveIndex: false,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    HapticFeedback.selectionClick();
                    ref.read(flScaleRootProvider.notifier).setAndSave(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('音阶锁定'),
            subtitle: const Text('关闭所选音阶之外的琴键。'),
            value: scaleLock,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              ref.read(flScaleLockProvider.notifier).setAndSave(value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('触控力度'),
            subtitle: const Text(
              '屏幕支持压力时映射为力度；不支持时自动使用固定力度。',
            ),
            value: touchDynamics,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              ref.read(flTouchDynamicsProvider.notifier).setAndSave(value);
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _showCcEditor(
  BuildContext context, {
  required String label,
  required int current,
  required ValueChanged<int> onSave,
}) async {
  final controller = TextEditingController(text: '$current');
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('$label · MIDI CC'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: const InputDecoration(
            labelText: '控制器编号',
            helperText: '范围 0–127',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (text) {
            final value = int.tryParse(text);
            if (value != null && value >= 0 && value <= 127) {
              Navigator.pop(dialogContext, value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 0 && value <= 127) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
  controller.dispose();

  if (result != null) {
    HapticFeedback.selectionClick();
    onSave(result);
  }
}

class _XyControlPad extends ConsumerStatefulWidget {
  const _XyControlPad({
    required this.onCc,
  });

  final void Function(int controller, int value) onCc;

  @override
  ConsumerState<_XyControlPad> createState() => _XyControlPadState();
}

class _XyControlPadState extends ConsumerState<_XyControlPad> {
  Offset _position = const Offset(0.5, 0.5);

  void _update(Offset local, Size size, int xCc, int yCc) {
    final x = (local.dx / size.width).clamp(0.0, 1.0).toDouble();
    final y = (1 - local.dy / size.height).clamp(0.0, 1.0).toDouble();
    setState(() => _position = Offset(x, y));
    widget.onCc(xCc, (x * 127).round());
    widget.onCc(yCc, (y * 127).round());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final xCc = ref.watch(flXyXCcProvider);
    final yCc = ref.watch(flXyYCcProvider);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CcBadge(
                axis: 'X',
                controller: xCc,
                value: (_position.dx * 127).round(),
                onTap: () => _showCcEditor(
                  context,
                  label: 'XY 横轴',
                  current: xCc,
                  onSave: (value) =>
                      ref.read(flXyXCcProvider.notifier).setAndSave(value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CcBadge(
                axis: 'Y',
                controller: yCc,
                value: (_position.dy * 127).round(),
                onTap: () => _showCcEditor(
                  context,
                  label: 'XY 纵轴',
                  current: yCc,
                  onSave: (value) =>
                      ref.read(flXyYCcProvider.notifier).setAndSave(value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 142);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _update(details.localPosition, size, xCc, yCc),
              onPanDown: (details) =>
                  _update(details.localPosition, size, xCc, yCc),
              onPanUpdate: (details) =>
                  _update(details.localPosition, size, xCc, yCc),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [
                        scheme.surfaceContainerHighest,
                        scheme.primaryContainer,
                      ],
                    ),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          height: 1,
                          color: scheme.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 1,
                          color: scheme.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      Positioned(
                        left: _position.dx * (size.width - 30),
                        top: (1 - _position.dy) * (size.height - 30),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary,
                            border: Border.all(
                              color: scheme.onPrimary,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CcBadge extends StatelessWidget {
  const _CcBadge({
    required this.axis,
    required this.controller,
    required this.value,
    required this.onTap,
  });

  final String axis;
  final int controller;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(
              axis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            Text('CC$controller · $value'),
            const SizedBox(width: 4),
            const Icon(Icons.tune, size: 15),
          ],
        ),
      ),
    );
  }
}

class _MacroDeck extends ConsumerWidget {
  const _MacroDeck({
    required this.onCc,
  });

  final void Function(int controller, int value) onCc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllers = <int>[
      ref.watch(flMacro1CcProvider),
      ref.watch(flMacro2CcProvider),
      ref.watch(flMacro3CcProvider),
      ref.watch(flMacro4CcProvider),
    ];
    final providers = <NotifierProvider<SettingIntNotifier, int>>[
      flMacro1CcProvider,
      flMacro2CcProvider,
      flMacro3CcProvider,
      flMacro4CcProvider,
    ];

    return Column(
      children: [
        for (int i = 0; i < controllers.length; i++) ...[
          _MacroSlider(
            label: 'M${i + 1}',
            controller: controllers[i],
            onChanged: (value) => onCc(controllers[i], value),
            onEdit: () => _showCcEditor(
              context,
              label: '宏 ${i + 1}',
              current: controllers[i],
              onSave: (value) =>
                  ref.read(providers[i].notifier).setAndSave(value),
            ),
          ),
          if (i != controllers.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _MacroSlider extends StatefulWidget {
  const _MacroSlider({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onEdit,
  });

  final String label;
  final int controller;
  final ValueChanged<int> onChanged;
  final VoidCallback onEdit;

  @override
  State<_MacroSlider> createState() => _MacroSliderState();
}

class _MacroSliderState extends State<_MacroSlider> {
  double _value = 64;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 127,
            value: _value,
            onChanged: (value) {
              setState(() => _value = value);
              widget.onChanged(value.round());
            },
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${_value.round()}',
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 6),
        ActionChip(
          visualDensity: VisualDensity.compact,
          label: Text('CC${widget.controller}'),
          avatar: const Icon(Icons.tune, size: 15),
          onPressed: widget.onEdit,
        ),
      ],
    );
  }
}

int _velocityFromTouch(
  PointerDownEvent event,
  int fallback,
  bool enabled,
) {
  if (!enabled) return fallback;

  final range = event.pressureMax - event.pressureMin;
  if (range > 0.0001) {
    final normalized =
        ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
    // Many Android panels report a constant 1.0 when pressure is unavailable.
    // In that case keep the user's configured velocity instead of forcing 127.
    if (normalized > 0.01 && normalized < 0.99) {
      return (24 + normalized * 103).round().clamp(1, 127).toInt();
    }
  }
  return fallback;
}


class _PianoKeyboard extends StatelessWidget {
  const _PianoKeyboard({
    required this.baseNote,
    required this.noteCount,
    required this.velocity,
    required this.scale,
    required this.scaleRoot,
    required this.scaleLock,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int baseNote;
  final int noteCount;
  final int velocity;
  final FlScale scale;
  final int scaleRoot;
  final bool scaleLock;
  final bool touchDynamics;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  static const Set<int> _blackPitchClasses = <int>{1, 3, 6, 8, 10};

  bool _isBlack(int note) => _blackPitchClasses.contains(note % 12);

  @override
  Widget build(BuildContext context) {
    final notes = <int>[
      for (int i = 0; i < noteCount; i++)
        (baseNote + i).clamp(0, 127).toInt(),
    ];
    final whiteNotes = notes.where((note) => !_isBlack(note)).toList();
    const whiteWidth = 52.0;
    const blackWidth = 32.0;
    final totalWidth = whiteNotes.length * whiteWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        final blackHeight = constraints.maxHeight * 0.62;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: totalWidth,
            height: constraints.maxHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < whiteNotes.length; i++)
                  Positioned(
                    left: i * whiteWidth,
                    top: 0,
                    bottom: 0,
                    width: whiteWidth,
                    child: _PianoKey(
                      note: whiteNotes[i],
                      velocity: velocity,
                      isBlack: false,
                      enabled:
                          !scaleLock ||
                          scale.containsNote(whiteNotes[i], scaleRoot),
                      inScale: scale.containsNote(
                        whiteNotes[i],
                        scaleRoot,
                      ),
                      touchDynamics: touchDynamics,
                      onNoteOn: onNoteOn,
                      onNoteOff: onNoteOff,
                    ),
                  ),
                for (final note in notes.where(_isBlack))
                  Positioned(
                    left:
                        notes
                                .takeWhile((candidate) => candidate < note)
                                .where((candidate) => !_isBlack(candidate))
                                .length *
                            whiteWidth -
                        blackWidth / 2,
                    top: 0,
                    width: blackWidth,
                    height: blackHeight,
                    child: _PianoKey(
                      note: note,
                      velocity: velocity,
                      isBlack: true,
                      enabled:
                          !scaleLock || scale.containsNote(note, scaleRoot),
                      inScale: scale.containsNote(note, scaleRoot),
                      touchDynamics: touchDynamics,
                      onNoteOn: onNoteOn,
                      onNoteOff: onNoteOff,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PianoKey extends StatefulWidget {
  const _PianoKey({
    required this.note,
    required this.velocity,
    required this.isBlack,
    required this.enabled,
    required this.inScale,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int note;
  final int velocity;
  final bool isBlack;
  final bool enabled;
  final bool inScale;
  final bool touchDynamics;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_PianoKey> createState() => _PianoKeyState();
}

class _PianoKeyState extends State<_PianoKey> {
  final Set<int> _pointers = <int>{};

  bool get _active => _pointers.isNotEmpty;

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (_pointers.isEmpty) {
      widget.onNoteOn(
        widget.note,
        velocity: _velocityFromTouch(
          event,
          widget.velocity,
          widget.touchDynamics,
        ),
      );
    }
    _pointers.add(event.pointer);
    if (mounted) setState(() {});
  }

  void _up(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) widget.onNoteOff(widget.note);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = widget.isBlack
        ? const Color(0xFF242424)
        : const Color(0xFFB9B9B9);
    final base = widget.isBlack
        ? const Color(0xFF242424)
        : const Color(0xFFF1F1F1);
    final scaleTint = widget.isBlack
        ? Color.lerp(const Color(0xFF242424), scheme.primary, 0.28)!
        : Color.lerp(const Color(0xFFF1F1F1), scheme.primary, 0.16)!;
    final active = widget.isBlack
        ? Color.lerp(const Color(0xFF242424), scheme.primary, 0.58)!
        : scheme.primaryContainer;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 42),
        margin: EdgeInsets.fromLTRB(
          widget.isBlack ? 1.5 : 0.7,
          0,
          widget.isBlack ? 1.5 : 0.7,
          widget.isBlack ? 4 : 1,
        ),
        decoration: BoxDecoration(
          color: !widget.enabled
              ? disabled.withValues(alpha: 0.52)
              : _active
                  ? active
                  : widget.inScale
                      ? scaleTint
                      : base,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(widget.isBlack ? 5 : 7),
            bottomRight: Radius.circular(widget.isBlack ? 5 : 7),
          ),
          border: Border.all(
            color: widget.isBlack
                ? Colors.black
                : const Color(0xFF888888),
            width: widget.isBlack ? 1.5 : 0.7,
          ),
          boxShadow: widget.isBlack
              ? const [
                  BoxShadow(
                    blurRadius: 4,
                    offset: Offset(0, 3),
                    color: Colors.black54,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.bottomCenter,
        padding: EdgeInsets.only(bottom: widget.isBlack ? 7 : 10),
        child: Text(
          MidiUtils.getNoteName(widget.note),
          style: TextStyle(
            fontSize: 9,
            color: widget.isBlack ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _FpcGrid extends StatelessWidget {
  const _FpcGrid({
    required this.baseNote,
    required this.velocity,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int baseNote;
  final int velocity;
  final bool touchDynamics;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  static const List<String> _labels = [
    'KICK', 'SNARE', 'CLAP', 'HAT C',
    'HAT O', 'TOM L', 'TOM M', 'TOM H',
    'CRASH', 'RIDE', 'PERC 1', 'PERC 2',
    'PAD 13', 'PAD 14', 'PAD 15', 'PAD 16',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape =
            constraints.maxWidth > constraints.maxHeight * 1.35;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 16,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: landscape ? 8 : 4,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: landscape ? 1.18 : 1,
          ),
          itemBuilder: (context, index) {
            final note = (baseNote + index).clamp(0, 127).toInt();
            return _DrumPad(
              label: _labels[index],
              note: note,
              velocity: velocity,
              touchDynamics: touchDynamics,
              onNoteOn: onNoteOn,
              onNoteOff: onNoteOff,
            );
          },
        );
      },
    );
  }
}

class _DrumPad extends StatefulWidget {
  const _DrumPad({
    required this.label,
    required this.note,
    required this.velocity,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final String label;
  final int note;
  final int velocity;
  final bool touchDynamics;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_DrumPad> createState() => _DrumPadState();
}

class _DrumPadState extends State<_DrumPad> {
  final Set<int> _pointers = <int>{};

  void _down(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      widget.onNoteOn(
        widget.note,
        velocity: _velocityFromTouch(
          event,
          widget.velocity,
          widget.touchDynamics,
        ),
      );
    }
    _pointers.add(event.pointer);
    setState(() {});
  }

  void _up(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) widget.onNoteOff(widget.note);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _pointers.isNotEmpty;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 45),
        decoration: BoxDecoration(
          color: active ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, style: Theme.of(context).textTheme.labelSmall),
            Text(
              '${widget.note}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
