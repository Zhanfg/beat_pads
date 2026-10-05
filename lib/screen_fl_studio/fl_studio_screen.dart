import 'package:beat_pads/screen_midi_devices/_drawer_devices.dart';
import 'package:beat_pads/services/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FlStudioScreen extends ConsumerStatefulWidget {
  const FlStudioScreen({super.key});

  @override
  ConsumerState<FlStudioScreen> createState() => _FlStudioScreenState();
}

class _FlStudioScreenState extends ConsumerState<FlStudioScreen> {
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
    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.cadetBlue,
      brightness: Brightness.dark,
    );
    final modernTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.14),
      ),
    );

    return Theme(
      data: modernTheme,
      child: Scaffold(
      drawer: const Drawer(child: MidiConfig()),
      appBar: AppBar(
        titleSpacing: 8,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FL Studio Controller'),
            Text(
              'USB MIDI / Generic Controller',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          _ConnectionPill(count: connected.length),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Panic / All notes off',
            onPressed: _panic,
            icon: const Icon(Icons.warning_amber_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape = constraints.maxWidth > constraints.maxHeight;
            final performance = _PerformanceArea(
              keyboardBaseNote: _keyboardBaseNote,
              fpcBaseNote: _fpcBaseNote,
              velocity: velocity,
              scale: scale,
              scaleRoot: scaleRoot,
              scaleLock: scaleLock,
              touchDynamics: touchDynamics,
              onNoteOn: _noteOn,
              onNoteOff: _noteOff,
              onOctaveDown: () {
                setState(() {
                  _keyboardBaseNote = (_keyboardBaseNote - 12).clamp(0, 96).toInt();
                });
              },
              onOctaveUp: () {
                setState(() {
                  _keyboardBaseNote = (_keyboardBaseNote + 12).clamp(0, 96).toInt();
                });
              },
              onFpcBankDown: () {
                setState(() {
                  _fpcBaseNote = (_fpcBaseNote - 16).clamp(0, 111).toInt();
                });
              },
              onFpcBankUp: () {
                setState(() {
                  _fpcBaseNote = (_fpcBaseNote + 16).clamp(0, 111).toInt();
                });
              },
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
              onTransportCc: _sendMomentaryCc,
              onCc: _sendCc,
              onPanic: _panic,
            );

            if (landscape) {
              return ColoredBox(
                color: scheme.surface,
                child: Row(
                  children: [
                    Expanded(flex: 7, child: performance),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 300,
                      child: SingleChildScrollView(child: controls),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(height: 570, child: performance),
                const Divider(height: 1),
                controls,
              ],
            );
          },
        ),
      ),
    ),
  );
  }
}

class _PerformanceArea extends StatelessWidget {
  const _PerformanceArea({
    required this.keyboardBaseNote,
    required this.fpcBaseNote,
    required this.velocity,
    required this.scale,
    required this.scaleRoot,
    required this.scaleLock,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
    required this.onOctaveDown,
    required this.onOctaveUp,
    required this.onFpcBankDown,
    required this.onFpcBankUp,
  });

  final int keyboardBaseNote;
  final int fpcBaseNote;
  final int velocity;
  final FlScale scale;
  final int scaleRoot;
  final bool scaleLock;
  final bool touchDynamics;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;
  final VoidCallback onOctaveDown;
  final VoidCallback onOctaveUp;
  final VoidCallback onFpcBankDown;
  final VoidCallback onFpcBankUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text('KEYS', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Octave down',
                onPressed: onOctaveDown,
                icon: const Icon(Icons.remove),
              ),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(MidiUtils.getNoteName(keyboardBaseNote)),
              ),
              IconButton(
                tooltip: 'Octave up',
                onPressed: onOctaveUp,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(
            height: 178,
            child: _ChromaticKeyboard(
              baseNote: keyboardBaseNote,
              noteCount: 25,
              velocity: velocity,
              scale: scale,
              scaleRoot: scaleRoot,
              scaleLock: scaleLock,
              touchDynamics: touchDynamics,
              onNoteOn: onNoteOn,
              onNoteOff: onNoteOff,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('FPC / DRUM PADS', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Previous bank',
                onPressed: onFpcBankDown,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$fpcBaseNote–${fpcBaseNote + 15}'),
              IconButton(
                tooltip: 'Next bank',
                onPressed: onFpcBankUp,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Expanded(
            child: _FpcGrid(
              baseNote: fpcBaseNote,
              velocity: velocity,
              touchDynamics: touchDynamics,
              onNoteOn: onNoteOn,
              onNoteOff: onNoteOff,
            ),
          ),
        ],
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
    required this.onTransportCc,
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
  final Future<void> Function(int controller) onTransportCc;
  final void Function(int controller, int value) onCc;
  final VoidCallback onPanic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        _SectionCard(
          title: 'MIDI',
          child: Row(
            children: [
              Expanded(child: _Metric(label: 'CHANNEL', value: '${channel + 1}')),
              const SizedBox(width: 8),
              Expanded(child: _Metric(label: 'VELOCITY', value: '$velocity')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StudioProfiles(),
        const SizedBox(height: 10),
        _SmartAssistCard(),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'XY CONTROL',
          subtitle: 'Two-axis continuous control. Defaults: X=CC74, Y=CC71.',
          child: _XyControlPad(
            channel: channel,
            onCc: onCc,
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'SMART MACROS',
          subtitle: 'Four assignable CC macros for FL Studio Link to controller.',
          child: _MacroDeck(
            channel: channel,
            onCc: onCc,
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'PERFORMANCE',
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 52, child: Text('Pitch')),
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
                  const SizedBox(width: 52, child: Text('Mod')),
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
                title: const Text('Sustain · CC64'),
                value: sustain,
                onChanged: onSustainChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'FL TRANSPORT · LEARNABLE CC',
          subtitle: 'Map CC110–114 once in FL Studio.',
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _TransportButton(
                icon: Icons.fiber_manual_record,
                label: 'REC',
                onPressed: () => onTransportCc(110),
              ),
              _TransportButton(
                icon: Icons.play_arrow,
                label: 'PLAY',
                onPressed: () => onTransportCc(111),
              ),
              _TransportButton(
                icon: Icons.stop,
                label: 'STOP',
                onPressed: () => onTransportCc(112),
              ),
              _TransportButton(
                icon: Icons.repeat,
                label: 'LOOP',
                onPressed: () => onTransportCc(113),
              ),
              _TransportButton(
                icon: Icons.timer_outlined,
                label: 'METRO',
                onPressed: () => onTransportCc(114),
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
          label: const Text('PANIC · ALL NOTES OFF'),
        ),
      ],
      ),
    );
  }
}

class _ChromaticKeyboard extends StatelessWidget {
  const _ChromaticKeyboard({
    required this.baseNote,
    required this.noteCount,
    required this.velocity,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int baseNote;
  final int noteCount;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  static const Set<int> _black = {1, 3, 6, 8, 10};

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: noteCount,
      separatorBuilder: (_, __) => const SizedBox(width: 2),
      itemBuilder: (context, index) {
        final note = (baseNote + index).clamp(0, 127).toInt();
        final black = _black.contains(note % 12);
        return SizedBox(
          width: black ? 42 : 52,
          child: Padding(
            padding: EdgeInsets.only(bottom: black ? 42 : 0),
            child: _MidiKey(
              note: note,
              velocity: velocity,
              dark: black,
              onNoteOn: onNoteOn,
              onNoteOff: onNoteOff,
            ),
          ),
        );
      },
    );
  }
}

class _MidiKey extends StatefulWidget {
  const _MidiKey({
    required this.note,
    required this.velocity,
    required this.dark,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int note;
  final int velocity;
  final bool dark;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_MidiKey> createState() => _MidiKeyState();
}

class _MidiKeyState extends State<_MidiKey> {
  final Set<int> _pointers = <int>{};

  bool get _active => _pointers.isNotEmpty;

  void _down(PointerDownEvent event) {
    final wasInactive = _pointers.isEmpty;
    _pointers.add(event.pointer);
    if (wasInactive) widget.onNoteOn(widget.note, velocity: widget.velocity);
    setState(() {});
  }

  void _release(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) widget.onNoteOff(widget.note);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.dark ? scheme.inverseSurface : scheme.surfaceContainerHighest;
    final active = scheme.primaryContainer;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 45),
        decoration: BoxDecoration(
          color: _active ? active : base,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(
          MidiUtils.getNoteName(widget.note),
          style: TextStyle(
            fontSize: 11,
            color: widget.dark && !_active ? scheme.onInverseSurface : scheme.onSurface,
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
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int baseNote;
  final int velocity;
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
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 16,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (context, index) {
        final note = (baseNote + index).clamp(0, 127).toInt();
        return _DrumPad(
          label: _labels[index],
          note: note,
          velocity: velocity,
          onNoteOn: onNoteOn,
          onNoteOff: onNoteOff,
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
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final String label;
  final int note;
  final int velocity;
  final void Function(int note, {int? velocity}) onNoteOn;
  final ValueChanged<int> onNoteOff;

  @override
  State<_DrumPad> createState() => _DrumPadState();
}

class _DrumPadState extends State<_DrumPad> {
  final Set<int> _pointers = <int>{};

  void _down(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      widget.onNoteOn(widget.note, velocity: widget.velocity);
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

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = count > 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: connected ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Row(
        children: [
          Icon(connected ? Icons.usb : Icons.usb_off, size: 16),
          const SizedBox(width: 5),
          Text(connected ? '$count MIDI' : 'NO MIDI'),
        ],
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

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
