import 'dart:async';
import 'dart:math' as math;

import 'package:beat_pads/services/audio/local_synth.dart';
import 'package:beat_pads/services/input/multi_touch_note_router.dart';
import 'package:beat_pads/services/protocol/axyp_event.dart';
import 'package:beat_pads/services/protocol/performance_router.dart';
import 'package:beat_pads/services/state/settings_fl_studio.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _DelayedEngine engine;
  late LocalSynth synth;
  late PerformanceRouter router;
  late MultiTouchNoteRouter pointers;
  late List<AxypEvent> midi;
  late bool midiConnected;
  late bool localEnabled;

  setUp(() {
    engine = _DelayedEngine();
    synth = LocalSynth.withEngine(engine);
    midi = [];
    midiConnected = true;
    localEnabled = true;
    router = PerformanceRouter(
      channel: () => 2,
      velocity: () => 96,
      localAudioEnabled: () => localEnabled,
      percussive: () => false,
      localSynth: synth,
      midiOutput: (event) {
        if (midiConnected) midi.add(event);
      },
    );
    pointers = MultiTouchNoteRouter(
      onNoteOn: router.noteOn,
      onNoteOff: router.noteOff,
    );
  });

  Future<void> openDevice() async {
    await engine.startEntered.future;
    expect(engine.played, isEmpty);
    engine.completeStartup();
    // Drain the startup microtasks without sleeping for native audio.
    await Future<void>.delayed(Duration.zero);
  }

  test('a released finger cannot start after another remains held', () async {
    pointers.down(11, 60);
    pointers.down(22, 64);
    await engine.startEntered.future;
    pointers.up(11);

    await openDevice();

    expect(engine.startCalls, 1);
    expect(engine.played, hasLength(1));
    final sound = engine.played.single;
    expect(sound.looping, isTrue);
    expect(sound.scale, closeTo(math.pow(2, (64 - 69) / 12), 1e-10));
    expect(engine.stops, isEmpty);
    pointers.up(22);
    expect(engine.stops, [sound.handle]);
  });

  test('shared pitch keeps its original voice until final pointer up', () async {
    pointers.down(11, 60, velocity: 87);
    pointers.down(22, 60, velocity: 105);
    await engine.startEntered.future;
    pointers.up(11);

    expect(pointers.activeNotes, {60});
    expect(midi.whereType<AxypNoteOff>(), isEmpty);
    await openDevice();
    expect(engine.played, hasLength(1));
    expect(engine.stops, isEmpty);
    final on = midi.whereType<AxypNoteOn>().single;
    expect((on.pointerId, on.note, on.velocity, on.channel), (11, 60, 87, 2));

    pointers.up(22);
    final off = midi.whereType<AxypNoteOff>().single;
    expect((off.pointerId, off.note, off.channel), (11, 60, 2));
    expect(engine.stops, [engine.played.single.handle]);
  });

  test('independent surfaces share one MIDI voice, not one local voice', () async {
    final secondSurface = MultiTouchNoteRouter(
      onNoteOn: router.noteOn,
      onNoteOff: router.noteOff,
    );
    pointers.down(11, 60);
    secondSurface.down(22, 60);

    await openDevice();

    expect(engine.played, hasLength(2));
    expect(midi.whereType<AxypNoteOn>(), hasLength(1));
    pointers.up(11);
    expect(engine.stops, hasLength(1));
    expect(midi.whereType<AxypNoteOff>(), isEmpty);

    secondSurface.up(22);
    expect(engine.stops.toSet(), engine.played.map((p) => p.handle).toSet());
    expect(midi.whereType<AxypNoteOff>(), hasLength(1));
  });

  test('cancelAll drops a pending shared tone and emits one MIDI off', () async {
    pointers.down(11, 60);
    pointers.down(22, 60);
    await engine.startEntered.future;
    pointers.cancelAll();

    await openDevice();

    expect(pointers.activeNotes, isEmpty);
    expect(midi.whereType<AxypNoteOn>(), hasLength(1));
    expect(midi.whereType<AxypNoteOff>(), hasLength(1));
    expect(engine.played, isEmpty);
  });

  test('no connected MIDI sink is needed for local audio', () async {
    midiConnected = false;

    pointers.down(11, 60);
    await openDevice();

    expect(midi, isEmpty);
    expect(engine.played, hasLength(1));
    pointers.up(11);
    expect(engine.stops, [engine.played.single.handle]);
  });

  test('panic invalidates native startup and allows a fresh press', () async {
    pointers.down(11, 60);
    await engine.startEntered.future;
    router.panic();
    pointers.cancelAll();

    await openDevice();
    expect(engine.stopAllCalls, 1);
    expect(engine.played, isEmpty);
    expect(midi.whereType<AxypPanic>(), hasLength(1));
    // Panic emptied the MIDI gate, so cancelAll emits no redundant MIDI off.
    expect(midi.whereType<AxypNoteOff>(), isEmpty);

    pointers.down(11, 60);
    await Future<void>.delayed(Duration.zero);
    expect(engine.played, hasLength(1));
    expect(midi.whereType<AxypNoteOn>(), hasLength(2));
    pointers.up(11);
    expect(engine.stops, [engine.played.single.handle]);
  });

  test('disabling the local monitor suppresses an in-flight note', () async {
    pointers.down(11, 60);
    await engine.startEntered.future;
    localEnabled = false;
    await synth.configure(enabled: false, volume: 68, tone: FlLocalTone.warm);

    await openDevice();

    expect(engine.stopAllCalls, 1);
    expect(engine.stopDeviceCalls, 1);
    expect(engine.played, isEmpty);
    pointers.up(11);
    expect(midi.whereType<AxypNoteOff>(), hasLength(1));
  });
}

final class _StubWaveform implements AudioSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DelayedEngine implements SoLoud {
  final startEntered = Completer<void>();
  final _startup = Completer<void>();
  final played = <({SoundHandle handle, bool looping, double scale})>[];
  final stops = <SoundHandle>[];
  var _initialized = false;
  var _state = AudioDeviceState.uninitialized;
  var _nextHandle = 0;
  var startCalls = 0;
  var stopAllCalls = 0;
  var stopDeviceCalls = 0;

  void completeStartup() => _startup.complete();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #isInitialized:
        return _initialized;
      case #init:
        _initialized = true;
        _state = AudioDeviceState.stopped;
        return Future<void>.value();
      case #getAudioDeviceState:
        return _state;
      case #loadWaveform:
        return Future<AudioSource>.value(_StubWaveform());
      case #startAudioDevice:
        startCalls++;
        _state = AudioDeviceState.starting;
        startEntered.complete();
        return _startup.future.then<void>((_) {
          _state = AudioDeviceState.started;
        });
      case #stopAudioDevice:
        stopDeviceCalls++;
        _state = AudioDeviceState.stopped;
        return Future<void>.value();
      case #play:
        // The fake owns its handle IDs; no native FFI is invoked.
        // ignore: invalid_use_of_internal_member
        final handle = SoundHandle(++_nextHandle);
        played.add((
          handle: handle,
          looping: invocation.namedArguments[#looping] as bool,
          scale: invocation.namedArguments[#scale] as double,
        ));
        return handle;
      case #getIsValidVoiceHandle:
        return played.any(
          (play) => play.handle == invocation.positionalArguments.first,
        );
      case #scheduleStop:
        stops.add(invocation.positionalArguments.first as SoundHandle);
        return null;
      case #stopAll:
        stopAllCalls++;
        return null;
      case #fadeVolume:
      case #setWaveformFreq:
      case #setAudioDeviceIdleTimeout:
        return null;
      default:
        return super.noSuchMethod(invocation);
    }
  }
}
