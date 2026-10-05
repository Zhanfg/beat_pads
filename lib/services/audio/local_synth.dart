import 'dart:async';
import 'dart:math' as math;

import 'package:beat_pads/services/state/settings_fl_studio.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Low-latency local monitor that is independent from MIDI connectivity.
///
/// The output-device lifecycle is explicit. Recent flutter_soloud versions may
/// stop an idle output device; on Android that can otherwise leave valid voices
/// queued behind a stopped/busy audio HAL.
final class LocalSynth {
  LocalSynth._();

  static final LocalSynth instance = LocalSynth._();

  final SoLoud _engine = SoLoud.instance;
  final Map<(int, int), List<SoundHandle>> _active =
      <(int, int), List<SoundHandle>>{};
  final Set<(int, int)> _sustainedVoices = <(int, int)>{};

  AudioSource? _tonalSource;
  AudioSource? _drumSource;
  Future<void>? _initializing;
  Future<void>? _deviceStarting;

  bool _enabled = true;
  bool _sustain = false;
  double _bend = 0;
  double _master = 0.68;
  FlLocalTone _tone = FlLocalTone.warm;

  bool get ready =>
      _engine.isInitialized && _tonalSource != null && _drumSource != null;

  AudioDeviceState get deviceState => _engine.getAudioDeviceState();

  Future<void> ensureReady() async {
    if (ready) return;

    final init = _initializing ??= _init();
    try {
      await init;
    } catch (_) {
      if (identical(_initializing, init)) _initializing = null;
      rethrow;
    }
  }

  Future<void> _init() async {
    if (!_engine.isInitialized) {
      await _engine.init(
        sampleRate: 48000,
        bufferSize: 256,
        channels: Channels.stereo,
        lowLatency: true,
      );
    }

    _tonalSource ??= await _engine.loadWaveform(
      _waveFor(_tone),
      false,
      1.0,
      0.0,
    );
    _engine.setWaveformFreq(_tonalSource!, 440);

    _drumSource ??= await _engine.loadWaveform(
      WaveForm.fSquare,
      false,
      1.0,
      0.0,
    );
    _engine.setWaveformFreq(_drumSource!, 110);

    // A performance instrument should not let the device fall asleep while its
    // local monitor is enabled. This avoids first-note loss on aggressive HALs.
    _engine.setAudioDeviceIdleTimeout(null);
    await _ensureDeviceStarted();
  }

  Future<void> _ensureDeviceStarted() async {
    if (!_engine.isInitialized) return;

    final state = _engine.getAudioDeviceState();
    if (state == AudioDeviceState.started) return;

    final existing = _deviceStarting;
    if (existing != null) {
      await existing;
      return;
    }

    if (state == AudioDeviceState.starting) return;

    final start = _engine.startAudioDevice();
    _deviceStarting = start;
    try {
      await start;
    } finally {
      if (identical(_deviceStarting, start)) _deviceStarting = null;
    }
  }

  WaveForm _waveFor(FlLocalTone tone) {
    return switch (tone) {
      FlLocalTone.warm => WaveForm.triangle,
      FlLocalTone.bright => WaveForm.fSaw,
      FlLocalTone.pulse => WaveForm.fSquare,
      FlLocalTone.pure => WaveForm.sin,
    };
  }

  Future<void> configure({
    required bool enabled,
    required int volume,
    required FlLocalTone tone,
  }) async {
    _master = (volume.clamp(0, 100) / 100).toDouble();

    if (!enabled) {
      _enabled = false;
      panic();
      if (_engine.isInitialized) {
        _engine.setAudioDeviceIdleTimeout(Duration.zero);
        try {
          await _engine.stopAudioDevice();
        } catch (_) {
          // The UI toggle must remain usable even if the HAL is already gone.
        }
      }
      return;
    }

    _enabled = true;
    await ensureReady();
    _engine.setAudioDeviceIdleTimeout(null);
    await _ensureDeviceStarted();

    if (_tone != tone && _tonalSource != null) {
      _tone = tone;
      _engine.setWaveform(_tonalSource!, _waveFor(tone));
    }
  }

  Future<void> noteOn(
    int midiNote,
    int velocity, {
    bool percussive = false,
    int voiceId = -1,
  }) async {
    if (!_enabled) return;

    await ensureReady();
    await _ensureDeviceStarted();

    final note = midiNote.clamp(0, 127).toInt();
    final vel = velocity.clamp(1, 127).toInt();
    final source = percussive ? _drumSource : _tonalSource;
    if (source == null) return;

    final baseScale = math.pow(2, (note - 69) / 12).toDouble();
    final bendScale = math.pow(2, (_bend * 2) / 12).toDouble();
    final targetVolume =
        (_master * (0.14 + (vel / 127) * 0.42)).clamp(0.0, 0.82).toDouble();

    final handle = _engine.play(
      source,
      volume: 0,
      looping: !percussive,
      scale: baseScale * bendScale,
    );

    if (!_engine.getIsValidVoiceHandle(handle)) return;

    final voice = (voiceId, note);
    _active.putIfAbsent(voice, () => <SoundHandle>[]).add(handle);
    _engine.fadeVolume(
      handle,
      targetVolume,
      const Duration(milliseconds: 7),
    );

    if (percussive) {
      _engine.fadeVolume(
        handle,
        0,
        const Duration(milliseconds: 145),
      );
      _engine.scheduleStop(handle, const Duration(milliseconds: 155));
      Timer(
        const Duration(milliseconds: 170),
        () => _forget(voice, handle),
      );
    }
  }

  void noteOff(int midiNote, {int voiceId = -1}) {
    final note = midiNote.clamp(0, 127).toInt();
    final voice = (voiceId, note);
    if (_sustain) {
      _sustainedVoices.add(voice);
      return;
    }
    _releaseVoice(voice);
  }

  void setSustain(bool enabled) {
    _sustain = enabled;
    if (!enabled) {
      final voices = _sustainedVoices.toList(growable: false);
      _sustainedVoices.clear();
      for (final voice in voices) {
        _releaseVoice(voice);
      }
    }
  }

  void setPitchBend(double bend) {
    _bend = bend.clamp(-1.0, 1.0);
    final bendScale = math.pow(2, (_bend * 2) / 12).toDouble();
    for (final entry in _active.entries) {
      final baseScale = math.pow(2, (entry.key.$2 - 69) / 12).toDouble();
      for (final handle in entry.value) {
        if (_engine.getIsValidVoiceHandle(handle)) {
          _engine.setRelativePlaySpeed(handle, baseScale * bendScale);
        }
      }
    }
  }

  void _releaseVoice((int, int) voice) {
    final handles = _active.remove(voice);
    if (handles == null) return;

    for (final handle in handles) {
      if (!_engine.getIsValidVoiceHandle(handle)) continue;
      _engine.fadeVolume(handle, 0, const Duration(milliseconds: 45));
      _engine.scheduleStop(handle, const Duration(milliseconds: 55));
    }
  }

  void _forget((int, int) voice, SoundHandle handle) {
    final handles = _active[voice];
    if (handles == null) return;
    handles.remove(handle);
    if (handles.isEmpty) _active.remove(voice);
  }

  void panic() {
    _sustainedVoices.clear();
    _active.clear();
    if (_engine.isInitialized) {
      _engine.stopAll();
    }
  }
}
