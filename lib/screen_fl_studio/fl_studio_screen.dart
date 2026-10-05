import 'dart:async';
import 'dart:math' as math;

import 'package:beat_pads/screen_midi_devices/_drawer_devices.dart';
import 'package:beat_pads/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _StudioWorkspace {
  instrument('乐器', Icons.piano_rounded),
  tracks('轨道', Icons.view_timeline_rounded),
  mixer('混音', Icons.tune_rounded),
  browser('浏览器', Icons.library_music_rounded);

  const _StudioWorkspace(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _KeyboardSwipeMode {
  glissando('滑奏', Icons.swipe_rounded),
  scroll('滚动', Icons.swap_horiz_rounded),
  pitch('弯音', Icons.multiline_chart_rounded);

  const _KeyboardSwipeMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _TouchInstrument {
  keyboard('键盘', Icons.piano),
  guitar('吉他', Icons.music_note_rounded),
  bass('贝斯', Icons.multitrack_audio_rounded),
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

_TouchInstrument? _instrumentFromId(String id) {
  for (final instrument in _TouchInstrument.values) {
    if (instrument.name == id) return instrument;
  }
  return null;
}


class FlStudioScreen extends ConsumerStatefulWidget {
  const FlStudioScreen({super.key});

  @override
  ConsumerState<FlStudioScreen> createState() => _FlStudioScreenState();
}

class _FlStudioScreenState extends ConsumerState<FlStudioScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _StudioWorkspace _workspace = _StudioWorkspace.instrument;
  _TouchInstrument _instrument = _TouchInstrument.keyboard;
  late final StudioSession _session;
  late final LocalMetronome _metronome;
  int _keyboardBaseNote = 48;
  _KeyboardSwipeMode _keyboardSwipeMode = _KeyboardSwipeMode.glissando;
  int _fpcBaseNote = 36;
  double _pitch = 0;
  double _mod = 0;
  bool _sustain = false;
  late final PerformanceRouter _performance;

  bool get _percussiveInstrument =>
      _instrument == _TouchInstrument.drums ||
      _instrument == _TouchInstrument.smartDrums ||
      _instrument == _TouchInstrument.beatSequencer;

  @override
  void initState() {
    super.initState();
    _session = StudioSession(
      storage: ref.read(sharedPrefProvider).sharedPrefs,
    );
    _metronome = LocalMetronome();
    _session.addListener(_onSessionChanged);
    ref.read(flTempoProvider.notifier).set(_session.project.tempo);
    _performance = PerformanceRouter(
      channel: () => ref.read(channelUsableProv),
      velocity: () => ref.read(velocityProv),
      localAudioEnabled: () => ref.read(flLocalAudioEnabledProvider),
      percussive: () => _percussiveInstrument,
      eventTap: _session.ingest,
    );
    unawaited(LocalSynth.instance.ensureReady());
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMetronome() async {
    if (_metronome.running) {
      _metronome.stop();
    } else {
      _metronome.start(ref.read(flTempoProvider));
    }
    if (mounted) setState(() {});
    await _sendMomentaryCc(114);
  }

  @override
  void dispose() {
    _metronome.dispose();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _performance.sustain(false);
    _performance.pitch(0);
    _performance.panic();
    super.dispose();
  }

  void _noteOn(int note, {int? velocity}) {
    _performance.noteOn(note, velocity: velocity);
  }

  void _pointerNoteOn(
    int note, {
    int? velocity,
    int pointerId = -1,
  }) {
    _performance.noteOn(
      note,
      velocity: velocity,
      pointerId: pointerId,
    );
  }

  void _noteOff(int note) {
    _performance.noteOff(note);
  }

  void _pointerNoteOff(int note, {int pointerId = -1}) {
    _performance.noteOff(note, pointerId: pointerId);
  }

  void _setPitch(double value) {
    setState(() => _pitch = value);
    _performance.pitch(value);
  }

  void _resetPitch() {
    setState(() => _pitch = 0);
    _performance.pitch(0);
  }

  void _setMod(double value) {
    setState(() => _mod = value);
    _performance.control(1, value.round());
  }

  void _setSustain(bool enabled) {
    setState(() => _sustain = enabled);
    _performance.sustain(enabled);
  }

  Future<void> _sendMomentaryCc(int controller) {
    return _performance.transport(controller);
  }
  Future<void> _toggleRecord() async {
    if (_session.recording) {
      _session.stopRecording();
    } else {
      _session.setTempo(ref.read(flTempoProvider));
      _session.startRecording(instrumentId: _instrument.name);
      setState(() => _workspace = _StudioWorkspace.instrument);
    }
    await _sendMomentaryCc(110);
  }

  Future<void> _playSession() async {
    if (_session.playing) {
      await _stopSession();
      return;
    }
    _session.playProject(
      noteOn: (track, note, velocity, voiceId) {
        final percussive = track.instrumentId == 'drums' ||
            track.instrumentId == 'smartDrums' ||
            track.instrumentId == 'beatSequencer';
        _performance.noteOn(
          note,
          velocity: velocity,
          pointerId: voiceId,
          percussive: percussive,
        );
      },
      noteOff: (_, note, voiceId) => _performance.noteOff(
        note,
        pointerId: voiceId,
      ),
    );
    await _sendMomentaryCc(111);
  }

  Future<void> _stopSession() async {
    _session.stopPlayback();
    if (_session.recording) _session.stopRecording();
    _panic();
    await _sendMomentaryCc(112);
  }


  void _panic() {
    HapticFeedback.mediumImpact();
    setState(() {
      _sustain = false;
      _pitch = 0;
    });
    _performance.sustain(false);
    _performance.pitch(0);
    _performance.panic();
  }

  void _sendCc(int controller, int value) {
    _performance.control(controller, value);
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
    ref.listen<int>(flTempoProvider, (_, next) {
      if (_session.project.tempo != next) _session.setTempo(next);
      _metronome.setTempo(next);
    });
    final localAudioEnabled = ref.watch(flLocalAudioEnabledProvider);
    final localAudioVolume = ref.watch(flLocalAudioVolumeProvider);
    final localTone = ref.watch(flLocalToneProvider);

    unawaited(
      LocalSynth.instance.configure(
        enabled: localAudioEnabled,
        volume: localAudioVolume,
        tone: localTone,
      ),
    );

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
        useSafeArea: false,
        backgroundColor: scheme.surface,
        showDragHandle: true,
        builder: (sheetContext) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            minChildSize: 0.34,
            maxChildSize: 0.96,
            builder: (context, scrollController) {
              return SafeArea(
                top: false,
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [controls],
                ),
              );
            },
          );
        },
      );
    }

    void showInstrumentBrowser() {
      setState(() => _workspace = _StudioWorkspace.browser);
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
            swipeMode: _keyboardSwipeMode,
            onSwipeModeChanged: (mode) {
              setState(() => _keyboardSwipeMode = mode);
              _resetPitch();
            },
            onPointerNoteOn: _pointerNoteOn,
            onPointerNoteOff: _pointerNoteOff,
            onPitchGesture: _setPitch,
            onPitchGestureEnd: _resetPitch,
            onBaseNoteChanged: (note) {
              setState(() => _keyboardBaseNote = note.clamp(0, 114).toInt());
            },
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
        case _TouchInstrument.guitar:
          return _FretboardView(
            title: '吉他',
            tuning: const <int>[40, 45, 50, 55, 59, 64],
            stringNames: const <String>['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
            frets: 12,
            velocity: velocity,
            touchDynamics: touchDynamics,
            onNoteOn: _pointerNoteOn,
            onNoteOff: _pointerNoteOff,
          );
        case _TouchInstrument.bass:
          return _FretboardView(
            title: '贝斯',
            tuning: const <int>[28, 33, 38, 43],
            stringNames: const <String>['E1', 'A1', 'D2', 'G2'],
            frets: 12,
            velocity: velocity,
            touchDynamics: touchDynamics,
            onNoteOn: _pointerNoteOn,
            onNoteOff: _pointerNoteOff,
          );
        case _TouchInstrument.drums:
          return _DrumsInstrumentView(
            baseNote: _fpcBaseNote,
            velocity: velocity,
            touchDynamics: touchDynamics,
            onNoteOn: _pointerNoteOn,
            onNoteOff: _pointerNoteOff,
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
            onNoteOn: _pointerNoteOn,
            onNoteOff: _pointerNoteOff,
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

    Widget workspaceView() {
      switch (_workspace) {
        case _StudioWorkspace.instrument:
          return instrumentView();
        case _StudioWorkspace.tracks:
          return _TracksWorkspace(
            session: _session,
            instrument: _instrument,
            onPlay: _playSession,
            onStop: _stopSession,
            onRecord: _toggleRecord,
          );
        case _StudioWorkspace.mixer:
          return _MixerWorkspace(
            session: _session,
            controls: controls,
            localAudioEnabled: localAudioEnabled,
            localAudioVolume: localAudioVolume,
            localTone: localTone,
          );
        case _StudioWorkspace.browser:
          return _BrowserWorkspace(
            selected: _instrument,
            onSelect: (instrument) {
              HapticFeedback.selectionClick();
              setState(() {
                _instrument = instrument;
                _workspace = _StudioWorkspace.instrument;
              });
              final track = _session.selectedTrack;
              if (track != null) {
                _session.setTrackInstrument(track.id, instrument.name);
              }
            },
          );
      }
    }

    return Theme(
      data: theme,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const Drawer(child: MidiConfig()),
        body: ColoredBox(
          color: const Color(0xFF111111),
          child: Builder(
            builder: (context) {
              final insets = MediaQuery.viewPaddingOf(context);
              final landscape =
                  MediaQuery.orientationOf(context) == Orientation.landscape;
              final contentInsets = EdgeInsets.only(
                left: math.max(insets.left, landscape ? 6.0 : 0.0),
                right: math.max(insets.right, landscape ? 6.0 : 0.0),
                top: insets.top,
                bottom: insets.bottom,
              );

              return Padding(
                padding: contentInsets,
                child: Column(
                  children: [
                    _GarageControlBar(
                      instrument: _instrument,
                      connectedCount: connected.length,
                      localAudioEnabled: localAudioEnabled,
                      onOpenInstrumentBrowser: showInstrumentBrowser,
                      onOpenMidiDevices: () =>
                          _scaffoldKey.currentState?.openDrawer(),
                      onToggleLocalAudio: () {
                        final next = !localAudioEnabled;
                        ref
                            .read(flLocalAudioEnabledProvider.notifier)
                            .setAndSave(next);
                        if (!next) LocalSynth.instance.panic();
                      },
                      onGoToBeginning: () => _sendMomentaryCc(115),
                      onPlay: _playSession,
                      onStop: _stopSession,
                      onRecord: _toggleRecord,
                      metronomeEnabled: _metronome.running,
                      onMetronome: _toggleMetronome,
                      onControls: showControls,
                      onPanic: _panic,
                    ),
                    if (_workspace == _StudioWorkspace.tracks)
                      const _MeasureRuler(),
                    Expanded(
                      child: landscape
                          ? Row(
                              children: [
                                _WorkspaceRail(
                                  selected: _workspace,
                                  recording: _session.recording,
                                  onSelected: (workspace) {
                                    setState(() => _workspace = workspace);
                                  },
                                ),
                                const VerticalDivider(
                                  width: 1,
                                  color: Colors.white10,
                                ),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    child: KeyedSubtree(
                                      key: ValueKey(
                                        '${_workspace.name}:${_instrument.name}',
                                      ),
                                      child: workspaceView(),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: KeyedSubtree(
                                key: ValueKey(
                                  '${_workspace.name}:${_instrument.name}',
                                ),
                                child: workspaceView(),
                              ),
                            ),
                    ),
                    if (!landscape)
                      _WorkspaceNavigation(
                        selected: _workspace,
                        recording: _session.recording,
                        onSelected: (workspace) {
                          setState(() => _workspace = workspace);
                        },
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
              );
            },
          ),
        ),
      ),
    );
  }
}


class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({
    required this.selected,
    required this.recording,
    required this.onSelected,
  });

  final _StudioWorkspace selected;
  final bool recording;
  final ValueChanged<_StudioWorkspace> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 58,
      child: ColoredBox(
        color: const Color(0xFF181818),
        child: Column(
          children: [
            const SizedBox(height: 6),
            for (final workspace in _StudioWorkspace.values)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 5,
                ),
                child: Tooltip(
                  message: workspace.label,
                  child: IconButton(
                    onPressed: () => onSelected(workspace),
                    style: IconButton.styleFrom(
                      backgroundColor: selected == workspace
                          ? scheme.primaryContainer.withValues(alpha: 0.58)
                          : Colors.transparent,
                      foregroundColor: selected == workspace
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(workspace.icon, size: 21),
                        if (workspace == _StudioWorkspace.tracks &&
                            recording)
                          const Positioned(
                            right: -5,
                            top: -4,
                            child: CircleAvatar(
                              radius: 3,
                              backgroundColor: Colors.redAccent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  const _WorkspaceNavigation({
    required this.selected,
    required this.recording,
    required this.onSelected,
  });

  final _StudioWorkspace selected;
  final bool recording;
  final ValueChanged<_StudioWorkspace> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          for (final workspace in _StudioWorkspace.values)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(workspace),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: selected == workspace
                        ? scheme.primaryContainer.withValues(alpha: 0.45)
                        : Colors.transparent,
                    border: Border(
                      top: BorderSide(
                        color: selected == workspace
                            ? scheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            workspace.icon,
                            size: 18,
                            color: selected == workspace
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          if (workspace == _StudioWorkspace.tracks &&
                              recording)
                            const Positioned(
                              right: -4,
                              top: -3,
                              child: CircleAvatar(
                                radius: 3,
                                backgroundColor: Colors.redAccent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        workspace.label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TracksWorkspace extends StatefulWidget {
  const _TracksWorkspace({
    required this.session,
    required this.instrument,
    required this.onPlay,
    required this.onStop,
    required this.onRecord,
  });

  final StudioSession session;
  final _TouchInstrument instrument;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;
  final Future<void> Function() onRecord;

  @override
  State<_TracksWorkspace> createState() => _TracksWorkspaceState();
}

class _TracksWorkspaceState extends State<_TracksWorkspace> {
  bool _pianoRoll = false;

  StudioSession get session => widget.session;

  void _addTrack() {
    session.addTrack(
      instrumentId: widget.instrument.name,
      name: '${widget.instrument.label} ${session.project.tracks.length + 1}',
    );
  }
  Future<String?> _askProjectName(
    String title, {
    String? initialValue,
  }) async {
    final controller = TextEditingController(
      text: initialValue ?? session.project.name,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 48,
            decoration: const InputDecoration(
              labelText: '工程名称',
              hintText: '例如：夜间草稿',
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.pop(dialogContext, trimmed);
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _saveProject() async {
    final name = await _askProjectName(
      '保存工程',
      initialValue: session.activeLibraryName ?? session.project.name,
    );
    if (name == null) return;
    session.saveProjectAs(name);
  }

  Future<void> _newProject() async {
    final name = await _askProjectName(
      '新建工程',
      initialValue: '新工程',
    );
    if (name == null) return;
    session.newProject(
      name: name,
      tempo: session.project.tempo,
    );
    session.saveProjectAs(name);
  }

  Future<void> _renameProject() async {
    final name = await _askProjectName(
      '重命名工程',
      initialValue: session.project.name,
    );
    if (name == null) return;
    session.renameProject(name);
  }

  Future<void> _showProjectLibrary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final names = session.savedProjectNames;
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          '工程库',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '新建工程',
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _newProject();
                          },
                          icon: const Icon(Icons.note_add_rounded),
                        ),
                        IconButton(
                          tooltip: '保存当前工程',
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _saveProject();
                          },
                          icon: const Icon(Icons.save_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (names.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('还没有保存过工程。'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: names.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final name = names[index];
                          final active = session.activeLibraryName == name;
                          return ListTile(
                            selected: active,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              active
                                  ? Icons.folder_open_rounded
                                  : Icons.folder_rounded,
                            ),
                            title: Text(name),
                            subtitle: active
                                ? const Text('当前工程 · 自动保存中')
                                : const Text('已保存工程'),
                            onTap: () {
                              final loaded = session.loadProject(name);
                              if (loaded) Navigator.pop(sheetContext);
                            },
                            trailing: IconButton(
                              tooltip: '删除已保存工程',
                              onPressed: () {
                                session.deleteSavedProject(name);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedTrack = session.selectedTrack;
    final selectedClip = session.selectedClip;

    return ColoredBox(
      color: const Color(0xFF101010),
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(
              color: Color(0xFF1B1B1B),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Icon(
                  _pianoRoll
                      ? Icons.edit_note_rounded
                      : Icons.view_timeline_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${session.project.name} · ${selectedTrack?.name ?? "无轨道"}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_timeline_rounded, size: 16),
                      label: Text('编排'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.edit_note_rounded, size: 16),
                      label: Text('钢琴卷帘'),
                    ),
                  ],
                  selected: <bool>{_pianoRoll},
                  onSelectionChanged: (value) {
                    setState(() => _pianoRoll = value.first);
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: '工程库',
                  onPressed: _showProjectLibrary,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
                IconButton(
                  tooltip: '保存工程',
                  onPressed: _saveProject,
                  icon: const Icon(Icons.save_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: '工程操作',
                  onSelected: (value) {
                    if (value == 'new') _newProject();
                    if (value == 'rename') _renameProject();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'new',
                      child: ListTile(
                        leading: Icon(Icons.note_add_rounded),
                        title: Text('新建工程'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline_rounded),
                        title: Text('重命名工程'),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: '撤销',
                  onPressed: session.canUndo ? session.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: '重做',
                  onPressed: session.canRedo ? session.redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                IconButton(
                  tooltip: '添加轨道',
                  onPressed: _addTrack,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: '播放工程',
                  onPressed: session.project.tracks.isEmpty
                      ? null
                      : widget.onPlay,
                  icon: Icon(
                    session.playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: session.recording ? '结束录制' : '录制到所选轨道',
                  onPressed: widget.onRecord,
                  color: session.recording ? scheme.error : null,
                  icon: Icon(
                    session.recording
                        ? Icons.stop_circle_rounded
                        : Icons.fiber_manual_record_rounded,
                  ),
                ),
                IconButton(
                  tooltip: '停止',
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.stop_rounded),
                ),
              ],
            ),
          ),
          if (selectedClip != null)
            _ClipEditToolbar(session: session),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final trackList = _ProjectTrackList(
                  session: session,
                  onAddTrack: _addTrack,
                );
                final editor = _pianoRoll
                    ? _PianoRollEditor(session: session)
                    : _ProjectTimeline(session: session);

                if (wide) {
                  return Row(
                    children: [
                      SizedBox(width: 238, child: trackList),
                      const VerticalDivider(width: 1, color: Colors.white10),
                      Expanded(child: editor),
                    ],
                  );
                }

                return Column(
                  children: [
                    SizedBox(height: 118, child: trackList),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(child: editor),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectTrackList extends StatelessWidget {
  const _ProjectTrackList({
    required this.session,
    required this.onAddTrack,
  });

  final StudioSession session;
  final VoidCallback onAddTrack;

  @override
  Widget build(BuildContext context) {
    final tracks = session.project.tracks;
    if (tracks.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: onAddTrack,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加第一条轨道'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      scrollDirection: MediaQuery.sizeOf(context).width < 760
          ? Axis.horizontal
          : Axis.vertical,
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6, height: 6),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final selected = session.selectedTrack?.id == track.id;
        final instrument = _instrumentFromId(track.instrumentId);
        return SizedBox(
          width: MediaQuery.sizeOf(context).width < 760 ? 210 : null,
          child: Material(
            color: selected
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.38)
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => session.selectTrack(track.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Row(
                  children: [
                    Icon(instrument?.icon ?? Icons.audiotrack_rounded, size: 18),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '${instrument?.label ?? track.instrumentId} · ${track.clips.length} 个片段',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    _TinyToggle(
                      label: 'M',
                      selected: track.muted,
                      onTap: () => session.setTrackMute(
                        track.id,
                        !track.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _TinyToggle(
                      label: 'S',
                      selected: track.solo,
                      onTap: () => session.setTrackSolo(
                        track.id,
                        !track.solo,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '轨道操作',
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      onSelected: (value) async {
                        if (value == 'delete') {
                          session.deleteTrack(track.id);
                          return;
                        }
                        if (value == 'rename') {
                          final controller = TextEditingController(
                            text: track.name,
                          );
                          final name = await showDialog<String>(
                            context: context,
                            builder: (dialogContext) {
                              return AlertDialog(
                                title: const Text('重命名轨道'),
                                content: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  maxLength: 36,
                                  onSubmitted: (value) {
                                    final trimmed = value.trim();
                                    if (trimmed.isNotEmpty) {
                                      Navigator.pop(
                                        dialogContext,
                                        trimmed,
                                      );
                                    }
                                  },
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      final trimmed =
                                          controller.text.trim();
                                      if (trimmed.isNotEmpty) {
                                        Navigator.pop(
                                          dialogContext,
                                          trimmed,
                                        );
                                      }
                                    },
                                    child: const Text('确定'),
                                  ),
                                ],
                              );
                            },
                          );
                          controller.dispose();
                          if (name != null) {
                            session.renameTrack(track.id, name);
                          }
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('重命名'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除轨道'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TinyToggle extends StatelessWidget {
  const _TinyToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _ClipEditToolbar extends StatelessWidget {
  const _ClipEditToolbar({required this.session});

  final StudioSession session;

  @override
  Widget build(BuildContext context) {
    final clip = session.selectedClip;
    if (clip == null) return const SizedBox.shrink();

    final beatMicros = (60000000 / session.project.tempo).round();
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        children: [
          _EditorAction(
            label: 'Q 1/16',
            icon: Icons.grid_4x4_rounded,
            onTap: () => session.quantizeSelectedClip(division: 16),
          ),
          _EditorAction(
            label: '-12',
            icon: Icons.keyboard_double_arrow_down_rounded,
            onTap: () => session.transposeSelectedClip(-12),
          ),
          _EditorAction(
            label: '-1',
            icon: Icons.remove_rounded,
            onTap: () => session.transposeSelectedClip(-1),
          ),
          _EditorAction(
            label: '+1',
            icon: Icons.add_rounded,
            onTap: () => session.transposeSelectedClip(1),
          ),
          _EditorAction(
            label: '+12',
            icon: Icons.keyboard_double_arrow_up_rounded,
            onTap: () => session.transposeSelectedClip(12),
          ),
          _EditorAction(
            label: '力度 -10',
            icon: Icons.volume_down_rounded,
            onTap: () => session.changeSelectedVelocity(-10),
          ),
          _EditorAction(
            label: '力度 +10',
            icon: Icons.volume_up_rounded,
            onTap: () => session.changeSelectedVelocity(10),
          ),
          _EditorAction(
            label: '左移',
            icon: Icons.arrow_back_rounded,
            onTap: () => session.moveSelectedClip(-beatMicros),
          ),
          _EditorAction(
            label: '右移',
            icon: Icons.arrow_forward_rounded,
            onTap: () => session.moveSelectedClip(beatMicros),
          ),
          _EditorAction(
            label: clip.loop ? '取消循环' : '循环',
            icon: Icons.loop_rounded,
            selected: clip.loop,
            onTap: () => session.setSelectedClipLoop(!clip.loop),
          ),
          _EditorAction(
            label: '复制',
            icon: Icons.content_copy_rounded,
            onTap: session.duplicateSelectedClip,
          ),
          _EditorAction(
            label: '删除',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onTap: session.deleteSelectedClip,
          ),
        ],
      ),
    );
  }
}

class _EditorAction extends StatelessWidget {
  const _EditorAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(
          icon,
          size: 16,
          color: destructive
              ? scheme.error
              : selected
                  ? scheme.primary
                  : null,
        ),
        label: Text(label),
        onPressed: onTap,
        backgroundColor:
            selected ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      ),
    );
  }
}

class _ProjectTimeline extends StatelessWidget {
  const _ProjectTimeline({required this.session});

  final StudioSession session;

  @override
  Widget build(BuildContext context) {
    final tracks = session.project.tracks;
    if (tracks.isEmpty) {
      return const Center(
        child: Text('先添加轨道，然后开始录制或进入钢琴卷帘写入音符。'),
      );
    }

    final projectLength = math.max(
      session.projectLengthMicros,
      (60000000 / session.project.tempo * 16).round(),
    );

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (context, trackIndex) {
        final track = tracks[trackIndex];
        return SizedBox(
          height: 66,
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  track.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          for (int bar = 1; bar < 8; bar++)
                            Positioned(
                              left: constraints.maxWidth * bar / 8,
                              top: 0,
                              bottom: 0,
                              child: const VerticalDivider(
                                width: 1,
                                color: Colors.white10,
                              ),
                            ),
                          for (final clip in track.clips)
                            Positioned(
                              left: constraints.maxWidth *
                                  clip.startMicros /
                                  projectLength,
                              top: 7,
                              bottom: 7,
                              width: math.max(
                                34.0,
                                constraints.maxWidth *
                                    math.max(1, clip.lengthMicros) /
                                    projectLength,
                              ),
                              child: _TimelineClip(
                                clip: clip,
                                selected:
                                    session.selectedClip?.id == clip.id,
                                onTap: () {
                                  session.selectTrack(track.id);
                                  session.selectClip(clip.id);
                                },
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
        );
      },
    );
  }
}

class _TimelineClip extends StatelessWidget {
  const _TimelineClip({
    required this.clip,
    required this.selected,
    required this.onTap,
  });

  final StudioClip clip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              if (clip.loop) ...[
                const Icon(Icons.loop_rounded, size: 13),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  clip.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected
                            ? scheme.onPrimary
                            : scheme.onPrimaryContainer,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PianoRollEditor extends StatelessWidget {
  const _PianoRollEditor({required this.session});

  final StudioSession session;

  @override
  Widget build(BuildContext context) {
    final clip = session.selectedClip;
    if (session.selectedTrack == null) {
      return const Center(child: Text('先选择或新建一条轨道。'));
    }
    if (clip == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () {
            final step =
                (60000000 / session.project.tempo * 4 / 16).round();
            session.addNoteToSelectedClip(
              note: 60,
              startMicros: 0,
              durationMicros: step,
            );
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('创建空片段并写入 C4'),
        ),
      );
    }

    final stepMicros =
        math.max(1000, (60000000 / session.project.tempo * 4 / 16).round());
    final visibleSteps =
        math.max(16, (clip.lengthMicros / stepMicros).ceil() + 2);
    final highest = clip.notes.isEmpty
        ? 71
        : clip.notes.map((note) => note.note).reduce(math.max) + 2;
    final topNote = highest.clamp(23, 127).toInt();
    final bottomNote = math.max(0, topNote - 23);
    const cellWidth = 48.0;
    const cellHeight = 27.0;

    return ClipRect(
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.7,
        maxScale: 2.4,
        boundaryMargin: const EdgeInsets.all(80),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final step = (details.localPosition.dx / cellWidth)
                .floor()
                .clamp(0, visibleSteps - 1)
                .toInt();
            final row = (details.localPosition.dy / cellHeight)
                .floor()
                .clamp(0, 23)
                .toInt();
            final note = (topNote - row).clamp(bottomNote, topNote).toInt();
            final start = step * stepMicros;

            final index = clip.notes.indexWhere((item) {
              final quantized = (item.startMicros / stepMicros).round();
              return item.note == note && quantized == step;
            });
            if (index >= 0) {
              session.removeNoteFromSelectedClip(index);
            } else {
              session.addNoteToSelectedClip(
                note: note,
                startMicros: start,
                durationMicros: stepMicros,
                velocity: 100,
              );
            }
          },
          child: CustomPaint(
            size: Size(
              visibleSteps * cellWidth,
              24 * cellHeight,
            ),
            painter: _PianoRollPainter(
              notes: clip.notes,
              topNote: topNote,
              bottomNote: bottomNote,
              stepMicros: stepMicros,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        ),
      ),
    );
  }
}

class _PianoRollPainter extends CustomPainter {
  const _PianoRollPainter({
    required this.notes,
    required this.topNote,
    required this.bottomNote,
    required this.stepMicros,
    required this.cellWidth,
    required this.cellHeight,
    required this.colorScheme,
  });

  final List<RecordedNote> notes;
  final int topNote;
  final int bottomNote;
  final int stepMicros;
  final double cellWidth;
  final double cellHeight;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = colorScheme.surfaceContainerLowest;
    canvas.drawRect(Offset.zero & size, background);

    final minor = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.30)
      ..strokeWidth = 0.7;
    final major = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.42)
      ..strokeWidth = 1.1;

    final columns = (size.width / cellWidth).ceil();
    for (int column = 0; column <= columns; column++) {
      final x = column * cellWidth;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        column % 4 == 0 ? major : minor,
      );
    }

    const rows = 24;
    for (int row = 0; row <= rows; row++) {
      final y = row * cellHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        row % 12 == 0 ? major : minor,
      );
    }

    final notePaint = Paint()..color = colorScheme.primary;
    final outline = Paint()
      ..color = colorScheme.onPrimary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final note in notes) {
      if (note.note < bottomNote || note.note > topNote) continue;
      final row = topNote - note.note;
      final x = note.startMicros / stepMicros * cellWidth;
      final width = math.max(
        8.0,
        note.durationMicros / stepMicros * cellWidth - 2,
      );
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x + 1,
          row * cellHeight + 2,
          width,
          cellHeight - 4,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, notePaint);
      canvas.drawRRect(rect, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _PianoRollPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.topNote != topNote ||
        oldDelegate.stepMicros != stepMicros ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _MixerWorkspace extends StatelessWidget {
  const _MixerWorkspace({
    required this.session,
    required this.controls,
    required this.localAudioEnabled,
    required this.localAudioVolume,
    required this.localTone,
  });

  final StudioSession session;
  final Widget controls;
  final bool localAudioEnabled;
  final int localAudioVolume;
  final FlLocalTone localTone;

  @override
  Widget build(BuildContext context) {
    final tracks = session.project.tracks;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.speaker_group_rounded),
            title: const Text('主输出'),
            subtitle: Text(
              localAudioEnabled
                  ? '本地监听 · $localAudioVolume% · ${localTone.label}'
                  : '本地监听已关闭',
            ),
          ),
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '轨道混音',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final track in tracks)
              _MixerTrackStrip(
                track: track,
                selected: session.selectedTrack?.id == track.id,
                onSelect: () => session.selectTrack(track.id),
                onMute: (value) => session.setTrackMute(track.id, value),
                onSolo: (value) => session.setTrackSolo(track.id, value),
                onVolume: (value) => session.setTrackVolume(track.id, value),
              ),
          ],
          const Divider(height: 26),
          controls,
        ],
      ),
    );
  }
}

class _MixerTrackStrip extends StatelessWidget {
  const _MixerTrackStrip({
    required this.track,
    required this.selected,
    required this.onSelect,
    required this.onMute,
    required this.onSolo,
    required this.onVolume,
  });

  final StudioTrack track;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<bool> onMute;
  final ValueChanged<bool> onSolo;
  final ValueChanged<double> onVolume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final instrument = _instrumentFromId(track.instrumentId);

    return Card(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.28)
          : scheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 9),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(instrument?.icon ?? Icons.audiotrack_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      track.name,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  FilterChip(
                    label: const Text('M'),
                    selected: track.muted,
                    onSelected: onMute,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 5),
                  FilterChip(
                    label: const Text('S'),
                    selected: track.solo,
                    onSelected: onSolo,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 36, child: Text('音量')),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 1.5,
                      value: track.volume.clamp(0.0, 1.5).toDouble(),
                      onChanged: onVolume,
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${(track.volume * 100).round()}%',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserWorkspace extends StatelessWidget {
  const _BrowserWorkspace({
    required this.selected,
    required this.onSelect,
  });

  final _TouchInstrument selected;
  final ValueChanged<_TouchInstrument> onSelect;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF101010),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 600
                  ? 3
                  : 2;
          return GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.65,
            ),
            itemCount: _TouchInstrument.values.length,
            itemBuilder: (context, index) {
              final instrument = _TouchInstrument.values[index];
              return _InstrumentBrowserTile(
                instrument: instrument,
                selected: selected == instrument,
                onTap: () => onSelect(instrument),
              );
            },
          );
        },
      ),
    );
  }
}

class _GarageControlBar extends StatelessWidget {
  const _GarageControlBar({
    required this.instrument,
    required this.connectedCount,
    required this.localAudioEnabled,
    required this.onOpenInstrumentBrowser,
    required this.onOpenMidiDevices,
    required this.onToggleLocalAudio,
    required this.onGoToBeginning,
    required this.onPlay,
    required this.onStop,
    required this.onRecord,
    required this.metronomeEnabled,
    required this.onMetronome,
    required this.onControls,
    required this.onPanic,
  });

  final _TouchInstrument instrument;
  final int connectedCount;
  final bool localAudioEnabled;
  final VoidCallback onOpenInstrumentBrowser;
  final VoidCallback onOpenMidiDevices;
  final VoidCallback onToggleLocalAudio;
  final VoidCallback onGoToBeginning;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRecord;
  final bool metronomeEnabled;
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
                  tooltip: '触控乐器',
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
                _BarButton(
                  tooltip: localAudioEnabled ? '关闭本地监听' : '开启本地监听',
                  onPressed: onToggleLocalAudio,
                  icon: localAudioEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  foregroundColor:
                      localAudioEnabled ? scheme.tertiary : null,
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
                if (!compact)
                  _BarButton(
                    tooltip: '回到开头 · CC115',
                    onPressed: onGoToBeginning,
                    icon: Icons.skip_previous_rounded,
                  )
                else
                  _BarButton(
                    tooltip: metronomeEnabled ? '关闭本地节拍器' : '开启本地节拍器',
                    onPressed: onMetronome,
                    icon: Icons.timer_outlined,
                    foregroundColor:
                        metronomeEnabled ? scheme.primary : null,
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
                    tooltip: metronomeEnabled ? '关闭本地节拍器 · CC114' : '开启本地节拍器 · CC114',
                    onPressed: onMetronome,
                    icon: Icons.timer_outlined,
                    foregroundColor:
                        metronomeEnabled ? scheme.primary : null,
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
    required this.swipeMode,
    required this.onSwipeModeChanged,
    required this.onPointerNoteOn,
    required this.onPointerNoteOff,
    required this.onPitchGesture,
    required this.onPitchGestureEnd,
    required this.onBaseNoteChanged,
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
  final _KeyboardSwipeMode swipeMode;
  final ValueChanged<_KeyboardSwipeMode> onSwipeModeChanged;
  final PointerNoteOn onPointerNoteOn;
  final PointerNoteOff onPointerNoteOff;
  final ValueChanged<double> onPitchGesture;
  final VoidCallback onPitchGestureEnd;
  final ValueChanged<int> onBaseNoteChanged;
  final VoidCallback onOctaveDown;
  final VoidCallback onOctaveUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: LayoutBuilder(
          builder: (context, outerConstraints) {
            final landscape = outerConstraints.maxWidth > outerConstraints.maxHeight;
            return Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '降低八度',
                      onPressed: onOctaveDown,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(MidiUtils.getNoteName(baseNote)),
                    ),
                    IconButton(
                      tooltip: '升高八度',
                      onPressed: onOctaveUp,
                      icon: const Icon(Icons.add_rounded),
                    ),
                    if (landscape) ...[
                      const SizedBox(width: 8),
                      SegmentedButton<_KeyboardSwipeMode>(
                        showSelectedIcon: false,
                        segments: [
                          for (final mode in _KeyboardSwipeMode.values)
                            ButtonSegment(
                              value: mode,
                              icon: Icon(mode.icon, size: 16),
                              label: Text(mode.label),
                            ),
                        ],
                        selected: <_KeyboardSwipeMode>{swipeMode},
                        onSelectionChanged: (selection) {
                          onSwipeModeChanged(selection.first);
                        },
                      ),
                    ],
                    const Spacer(),
                    FilterChip(
                      label: const Text('延音'),
                      avatar: const Icon(Icons.pedal_bike_rounded, size: 14),
                      selected: sustain,
                      onSelected: onSustainChanged,
                    ),
                    if (scaleLock) ...[
                      const SizedBox(width: 8),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.lock_rounded, size: 14),
                        label: Text(scale.label),
                      ),
                    ],
                  ],
                ),
                if (landscape) ...[
                  const SizedBox(height: 4),
                  _PianoRangeStrip(
                    baseNote: baseNote,
                    onChanged: onBaseNoteChanged,
                  ),
                ],
                const SizedBox(height: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final noteCount = TouchViewportPolicy.pianoNoteCount(size);
                      return _PianoKeyboard(
                        baseNote: baseNote,
                        noteCount: noteCount,
                        velocity: velocity,
                        scale: scale,
                        scaleRoot: scaleRoot,
                        scaleLock: scaleLock,
                        touchDynamics: touchDynamics,
                        swipeMode:
                            landscape ? swipeMode : _KeyboardSwipeMode.glissando,
                        onScrollNotes: (delta) {
                          onBaseNoteChanged(baseNote + delta);
                        },
                        onPitchGesture: onPitchGesture,
                        onPitchGestureEnd: onPitchGestureEnd,
                        onNoteOn: onPointerNoteOn,
                        onNoteOff: onPointerNoteOff,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PianoRangeStrip extends StatelessWidget {
  const _PianoRangeStrip({
    required this.baseNote,
    required this.onChanged,
  });

  final int baseNote;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Text(
            '全音域',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
              ),
              child: Slider(
                min: 0,
                max: 114,
                divisions: 114,
                value: baseNote.clamp(0, 114).toDouble(),
                activeColor: scheme.primary,
                label: MidiUtils.getNoteName(baseNote),
                onChanged: (value) => onChanged(value.round()),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              MidiUtils.getNoteName(baseNote),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _FretboardView extends StatefulWidget {
  const _FretboardView({
    required this.title,
    required this.tuning,
    required this.stringNames,
    required this.frets,
    required this.velocity,
    required this.touchDynamics,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final String title;
  final List<int> tuning;
  final List<String> stringNames;
  final int frets;
  final int velocity;
  final bool touchDynamics;
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;

  @override
  State<_FretboardView> createState() => _FretboardViewState();
}

class _FretHit {
  const _FretHit({
    required this.stringIndex,
    required this.fret,
    required this.note,
  });

  final int stringIndex;
  final int fret;
  final int note;
}

class _FretboardViewState extends State<_FretboardView> {
  int _firstFret = 0;
  final Map<int, _FretHit> _pointerHits = <int, _FretHit>{};

  late final MultiTouchNoteRouter _touches = MultiTouchNoteRouter(
    onNoteOn: (
      int note, {
      int? velocity,
      required int pointerId,
    }) {
      widget.onNoteOn(
        note,
        velocity: velocity,
        pointerId: pointerId,
      );
    },
    onNoteOff: (int note, {required int pointerId}) {
      widget.onNoteOff(note, pointerId: pointerId);
    },
  );

  _FretHit? _hitAt(Offset position, FretboardGeometry geometry) {
    final displayRow = geometry.stringAt(position);
    final fret = geometry.fretAt(position);
    if (displayRow == null || fret == null || fret > widget.frets) {
      return null;
    }

    final stringIndex = widget.tuning.length - 1 - displayRow;
    return _FretHit(
      stringIndex: stringIndex,
      fret: fret,
      note: widget.tuning[stringIndex] + fret,
    );
  }

  int _touchVelocity(PointerEvent event) {
    return _velocityFromTouch(
      event,
      widget.velocity,
      widget.touchDynamics,
    );
  }

  void _down(PointerDownEvent event, FretboardGeometry geometry) {
    final hit = _hitAt(event.localPosition, geometry);
    if (hit == null) return;

    _pointerHits[event.pointer] = hit;
    _touches.down(
      event.pointer,
      hit.note,
      velocity: _touchVelocity(event),
    );
    setState(() {});
  }

  void _move(PointerMoveEvent event, FretboardGeometry geometry) {
    final hit = _hitAt(event.localPosition, geometry);
    final previous = _pointerHits[event.pointer];

    if (hit == null) {
      _pointerHits.remove(event.pointer);
      _touches.move(event.pointer, null);
    } else {
      _pointerHits[event.pointer] = hit;
      if (previous?.stringIndex != hit.stringIndex ||
          previous?.fret != hit.fret) {
        _touches.move(
          event.pointer,
          hit.note,
          velocity: _touchVelocity(event),
        );
      }
    }
    setState(() {});
  }

  void _up(int pointer) {
    _pointerHits.remove(pointer);
    _touches.up(pointer);
    if (mounted) setState(() {});
  }

  bool _cellActive(int stringIndex, int fret) {
    return _pointerHits.values.any(
      (hit) => hit.stringIndex == stringIndex && hit.fret == fret,
    );
  }

  void _page(int delta, int visibleFretCount) {
    final page = math.max(1, visibleFretCount - 1);
    final maxFirst = math.max(0, widget.frets + 1 - visibleFretCount);
    final next = (_firstFret + delta * page).clamp(0, maxFirst).toInt();
    if (next == _firstFret) return;

    _touches.cancelAll();
    _pointerHits.clear();
    setState(() => _firstFret = next);
  }

  @override
  void didUpdateWidget(covariant _FretboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tuning != widget.tuning ||
        oldWidget.frets != widget.frets) {
      _touches.cancelAll();
      _pointerHits.clear();
      _firstFret = 0;
    }
  }

  @override
  void dispose() {
    _touches.cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: const Color(0xFF101010),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visibleFretCount = TouchViewportPolicy.visibleFretCount(
              Size(constraints.maxWidth, constraints.maxHeight),
              widget.frets,
            );
            final maxFirst =
                math.max(0, widget.frets + 1 - visibleFretCount);
            final firstFret = _firstFret.clamp(0, maxFirst).toInt();
            if (firstFret != _firstFret) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _firstFret = firstFret);
              });
            }
            final lastFret = math.min(
              widget.frets,
              firstFret + visibleFretCount - 1,
            );

            return Column(
              children: [
                Row(
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '标准定弦 · ${widget.frets} 品',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '上一段品位',
                      onPressed: firstFret == 0
                          ? null
                          : () => _page(-1, visibleFretCount),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text(
                      '$firstFret–$lastFret',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    IconButton(
                      tooltip: '下一段品位',
                      onPressed: lastFret >= widget.frets
                          ? null
                          : () => _page(1, visibleFretCount),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      const SizedBox(width: 58),
                      for (int column = 0;
                          column < visibleFretCount;
                          column++)
                        Expanded(
                          child: Center(
                            child: Text(
                              firstFret + column == 0
                                  ? '空'
                                  : '${firstFret + column}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, boardConstraints) {
                      final size = Size(
                        boardConstraints.maxWidth,
                        boardConstraints.maxHeight,
                      );
                      final geometry = FretboardGeometry(
                        size: size,
                        stringCount: widget.tuning.length,
                        firstFret: firstFret,
                        visibleFretCount: visibleFretCount,
                      );

                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => _down(event, geometry),
                        onPointerMove: (event) => _move(event, geometry),
                        onPointerUp: (event) => _up(event.pointer),
                        onPointerCancel: (event) => _up(event.pointer),
                        child: Row(
                          children: [
                            SizedBox(
                              width: geometry.labelWidth,
                              child: Column(
                                children: [
                                  for (int row = 0;
                                      row < widget.tuning.length;
                                      row++)
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          widget.stringNames[
                                              widget.tuning.length - 1 - row],
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  for (int row = 0;
                                      row < widget.tuning.length;
                                      row++)
                                    Expanded(
                                      child: Row(
                                        children: [
                                          for (int column = 0;
                                              column < visibleFretCount;
                                              column++)
                                            Expanded(
                                              child: _FretCellVisual(
                                                fret: firstFret + column,
                                                active: _cellActive(
                                                  widget.tuning.length -
                                                      1 -
                                                      row,
                                                  firstFret + column,
                                                ),
                                                marker:
                                                    <int>{3, 5, 7, 9, 12}
                                                        .contains(
                                                  firstFret + column,
                                                ),
                                                scheme: scheme,
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
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FretCellVisual extends StatelessWidget {
  const _FretCellVisual({
    required this.fret,
    required this.active,
    required this.marker,
    required this.scheme,
  });

  final int fret;
  final bool active;
  final bool marker;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 34),
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer
            : fret.isEven
                ? const Color(0xFF24201D)
                : const Color(0xFF2B2622),
        border: Border(
          right: BorderSide(
            color: fret == 0
                ? const Color(0xFFE4E0D6)
                : const Color(0xFF8B8178),
            width: fret == 0 ? 3 : 1.2,
          ),
          bottom: const BorderSide(color: Colors.white10),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 2,
            color: const Color(0xFFB9B1A8),
          ),
          if (marker)
            Container(
              width: fret == 12 ? 11 : 8,
              height: fret == 12 ? 11 : 8,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.34),
                shape: BoxShape.circle,
              ),
            ),
        ],
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
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;
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
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;

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
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;

  @override
  State<_ChordPad> createState() => _ChordPadState();
}

class _ChordPadState extends State<_ChordPad> {
  final Set<int> _pointers = <int>{};

  bool get _active => _pointers.isNotEmpty;

  void _down(PointerDownEvent event) {
    if (_pointers.contains(event.pointer)) return;
    HapticFeedback.selectionClick();
    _pointers.add(event.pointer);
    for (final note in widget.notes) {
      widget.onNoteOn(
        note,
        velocity: widget.velocity,
        pointerId: event.pointer,
      );
    }
    setState(() {});
  }

  void _up(int pointerId) {
    if (!_pointers.remove(pointerId)) return;
    for (final note in widget.notes) {
      widget.onNoteOff(note, pointerId: pointerId);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
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
    return Duration(milliseconds: ms.clamp(35, 1500).toInt());
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
        milliseconds: (60000 / widget.tempo / 4).round().clamp(35, 1500).toInt(),
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
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                                    (current.dy +
                                            details.delta.dy /
                                                math.max(1, size.height - 58))
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
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
        milliseconds: (60000 / widget.tempo / 4).round().clamp(35, 1500).toInt(),
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
        const _LocalMonitorCard(),
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


class _LocalMonitorCard extends ConsumerWidget {
  const _LocalMonitorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(flLocalAudioEnabledProvider);
    final volume = ref.watch(flLocalAudioVolumeProvider);
    final tone = ref.watch(flLocalToneProvider);

    return _SectionCard(
      title: '本地监听',
      subtitle: '不连接 FL Studio 也会直接从手机扬声器/耳机出声；MIDI 仍会同时发送。',
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('本机发声'),
            subtitle: const Text('独立于 USB、蓝牙和 FL Studio 连接状态。'),
            value: enabled,
            onChanged: (value) {
              ref
                  .read(flLocalAudioEnabledProvider.notifier)
                  .setAndSave(value);
              if (!value) LocalSynth.instance.panic();
            },
          ),
          if (enabled) ...[
            Row(
              children: [
                const SizedBox(width: 52, child: Text('音量')),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 100,
                    divisions: 100,
                    value: volume.toDouble(),
                    onChanged: (value) => ref
                        .read(flLocalAudioVolumeProvider.notifier)
                        .setAndSave(value.round()),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$volume%',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<FlLocalTone>(
              initialValue: tone,
              isExpanded: true,
              menuMaxHeight: 280,
              decoration: const InputDecoration(
                labelText: '本地音色',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final item in FlLocalTone.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(item.label),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref.read(flLocalToneProvider.notifier).setAndSave(value);
              },
            ),
          ],
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
                  initialValue: scale,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '音阶',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  menuMaxHeight: 360,
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
                  initialValue: root,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '根音',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  menuMaxHeight: 360,
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
  PointerEvent event,
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


class _PianoKeyboard extends StatefulWidget {
  const _PianoKeyboard({
    required this.baseNote,
    required this.noteCount,
    required this.velocity,
    required this.scale,
    required this.scaleRoot,
    required this.scaleLock,
    required this.touchDynamics,
    required this.swipeMode,
    required this.onScrollNotes,
    required this.onPitchGesture,
    required this.onPitchGestureEnd,
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
  final _KeyboardSwipeMode swipeMode;
  final ValueChanged<int> onScrollNotes;
  final ValueChanged<double> onPitchGesture;
  final VoidCallback onPitchGestureEnd;
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;

  @override
  State<_PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<_PianoKeyboard> {
  static const Set<int> _blackPitchClasses = <int>{1, 3, 6, 8, 10};

  final Map<int, double> _gestureOriginX = <int, double>{};
  final Map<int, double> _scrollRemainder = <int, double>{};

  late final MultiTouchNoteRouter _touches = MultiTouchNoteRouter(
    onNoteOn: (
      int note, {
      int? velocity,
      int pointerId = -1,
    }) {
      widget.onNoteOn(
        note,
        velocity: velocity,
        pointerId: pointerId,
      );
    },
    onNoteOff: (int note, {int pointerId = -1}) {
      widget.onNoteOff(note, pointerId: pointerId);
    },
  );

  bool _isBlack(int note) => _blackPitchClasses.contains(note % 12);

  List<int> get _notes => <int>[
        for (int i = 0; i < widget.noteCount; i++)
          (widget.baseNote + i).clamp(0, 127).toInt(),
      ];

  bool _enabled(int note) =>
      !widget.scaleLock || widget.scale.containsNote(note, widget.scaleRoot);

  int? _noteAt(
    Offset position,
    Size size,
    List<int> notes,
    List<int> whiteNotes,
  ) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= size.width ||
        position.dy >= size.height) {
      return null;
    }

    final whiteWidth = size.width / whiteNotes.length;
    final blackWidth = whiteWidth * 0.58;
    final blackHeight = math.min(
      size.height * 0.55,
      size.width * 0.62,
    );

    if (position.dy <= blackHeight) {
      for (final note in notes.where(_isBlack)) {
        final whitesBefore = notes
            .takeWhile((candidate) => candidate < note)
            .where((candidate) => !_isBlack(candidate))
            .length;
        final left = whitesBefore * whiteWidth - blackWidth / 2;
        if (position.dx >= left && position.dx < left + blackWidth) {
          return _enabled(note) ? note : null;
        }
      }
    }

    final whiteIndex =
        (position.dx / whiteWidth).floor().clamp(0, whiteNotes.length - 1);
    final note = whiteNotes[whiteIndex];
    return _enabled(note) ? note : null;
  }

  void _down(
    PointerDownEvent event,
    Size size,
    List<int> notes,
    List<int> whiteNotes,
  ) {
    _gestureOriginX[event.pointer] = event.localPosition.dx;
    _scrollRemainder[event.pointer] = 0;

    if (widget.swipeMode == _KeyboardSwipeMode.scroll) return;

    final note = _noteAt(event.localPosition, size, notes, whiteNotes);
    if (note == null) return;
    _touches.down(
      event.pointer,
      note,
      velocity: _velocityFromTouch(
        event,
        widget.velocity,
        widget.touchDynamics,
      ),
    );
    setState(() {});
  }

  void _move(
    PointerMoveEvent event,
    Size size,
    List<int> notes,
    List<int> whiteNotes,
  ) {
    if (widget.swipeMode == _KeyboardSwipeMode.scroll) {
      final whiteWidth = size.width / whiteNotes.length;
      final accumulated =
          (_scrollRemainder[event.pointer] ?? 0) + event.delta.dx;
      final threshold = math.max(14.0, whiteWidth * 0.72);
      if (accumulated.abs() >= threshold) {
        final steps = (accumulated / threshold).truncate();
        widget.onScrollNotes((-steps).toInt());
        _scrollRemainder[event.pointer] =
            accumulated - steps * threshold;
      } else {
        _scrollRemainder[event.pointer] = accumulated;
      }
      return;
    }

    if (widget.swipeMode == _KeyboardSwipeMode.pitch) {
      final origin = _gestureOriginX[event.pointer] ?? event.localPosition.dx;
      final bend =
          ((event.localPosition.dx - origin) / math.max(80.0, size.width * 0.22))
              .clamp(-1.0, 1.0)
              .toDouble();
      widget.onPitchGesture(bend);
      return;
    }

    final note = _noteAt(event.localPosition, size, notes, whiteNotes);
    _touches.move(
      event.pointer,
      note,
      velocity: _velocityFromTouch(
        event,
        widget.velocity,
        widget.touchDynamics,
      ),
    );
    setState(() {});
  }

  void _up(int pointer) {
    _gestureOriginX.remove(pointer);
    _scrollRemainder.remove(pointer);

    if (widget.swipeMode != _KeyboardSwipeMode.scroll) {
      _touches.up(pointer);
    }
    if (widget.swipeMode == _KeyboardSwipeMode.pitch) {
      widget.onPitchGestureEnd();
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PianoKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseNote != widget.baseNote ||
        oldWidget.scale != widget.scale ||
        oldWidget.scaleRoot != widget.scaleRoot ||
        oldWidget.scaleLock != widget.scaleLock ||
        oldWidget.swipeMode != widget.swipeMode) {
      _touches.cancelAll();
    }
  }

  @override
  void dispose() {
    _touches.cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    final whiteNotes = notes.where((note) => !_isBlack(note)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final whiteWidth = size.width / whiteNotes.length;
        final blackWidth = whiteWidth * 0.58;
        final blackHeight = math.min(
      size.height * 0.55,
      size.width * 0.62,
    );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _down(event, size, notes, whiteNotes),
          onPointerMove: (event) => _move(event, size, notes, whiteNotes),
          onPointerUp: (event) => _up(event.pointer),
          onPointerCancel: (event) => _up(event.pointer),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (int i = 0; i < whiteNotes.length; i++)
                Positioned(
                  left: i * whiteWidth,
                  top: 0,
                  bottom: 0,
                  width: whiteWidth,
                  child: _PianoKeyVisual(
                    note: whiteNotes[i],
                    isBlack: false,
                    enabled: _enabled(whiteNotes[i]),
                    inScale: widget.scale.containsNote(
                      whiteNotes[i],
                      widget.scaleRoot,
                    ),
                    active: _touches.activeNotes.contains(whiteNotes[i]),
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
                  child: _PianoKeyVisual(
                    note: note,
                    isBlack: true,
                    enabled: _enabled(note),
                    inScale:
                        widget.scale.containsNote(note, widget.scaleRoot),
                    active: _touches.activeNotes.contains(note),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PianoKeyVisual extends StatelessWidget {
  const _PianoKeyVisual({
    required this.note,
    required this.isBlack,
    required this.enabled,
    required this.inScale,
    required this.active,
  });

  final int note;
  final bool isBlack;
  final bool enabled;
  final bool inScale;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled =
        isBlack ? const Color(0xFF242424) : const Color(0xFFB9B9B9);
    final base =
        isBlack ? const Color(0xFF242424) : const Color(0xFFF1F1F1);
    final scaleTint = isBlack
        ? Color.lerp(const Color(0xFF242424), scheme.primary, 0.28)!
        : Color.lerp(const Color(0xFFF1F1F1), scheme.primary, 0.16)!;
    final pressed = isBlack
        ? Color.lerp(const Color(0xFF242424), scheme.primary, 0.65)!
        : scheme.primaryContainer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 34),
      margin: EdgeInsets.fromLTRB(
        isBlack ? 1.2 : 0.6,
        0,
        isBlack ? 1.2 : 0.6,
        isBlack ? 4 : 1,
      ),
      decoration: BoxDecoration(
        color: !enabled
            ? disabled.withValues(alpha: 0.52)
            : active
                ? pressed
                : inScale
                    ? scaleTint
                    : base,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(isBlack ? 5 : 7),
          bottomRight: Radius.circular(isBlack ? 5 : 7),
        ),
        border: Border.all(
          color: isBlack ? Colors.black : const Color(0xFF888888),
          width: isBlack ? 1.5 : 0.7,
        ),
        boxShadow: isBlack
            ? const <BoxShadow>[
                BoxShadow(
                  blurRadius: 4,
                  offset: Offset(0, 3),
                  color: Colors.black54,
                ),
              ]
            : null,
      ),
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.only(bottom: isBlack ? 7 : 10),
      child: !isBlack && note % 12 == 0
          ? Text(
              MidiUtils.getNoteName(note),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black54,
              ),
            )
          : null,
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
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;

  static const List<String> _labels = [
    '底鼓', '军鼓', '拍手', '闭镲',
    '开镲', '低嗵', '中嗵', '高嗵',
    '碎音镲', '叮叮镲', '打击 1', '打击 2',
    '鼓垫 13', '鼓垫 14', '鼓垫 15', '鼓垫 16',
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
  final PointerNoteOn onNoteOn;
  final PointerNoteOff onNoteOff;

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
        pointerId: event.pointer,
      );
    }
    _pointers.add(event.pointer);
    setState(() {});
  }

  void _up(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) widget.onNoteOff(widget.note, pointerId: pointer);
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
