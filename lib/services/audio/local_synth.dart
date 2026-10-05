import 'dart:async';
import 'dart:math' as math;

import 'package:beat_pads/services/state/settings_fl_studio.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Low-latency local monitor that runs independently from any MIDI connection.
///
/// MIDI output and local audio are intentionally separate paths: losing the
/// FL Studio/USB connection must never make the touch instruments silent.
final class LocalSynth {
  LocalSynth._();

  static final LocalSynth instance = LocalSynth._();

  final SoLoud _engine = SoLoud.instance;
  final Map<int, List<SoundHandle>> _active = <int, List<SoundHandle>>{};
  final Set<int> _sustainedNotes = <int>{};

  AudioSource? _tonalSource;
  AudioSource? _drumSource;
  Future<void>? _initializing;
  bool _sustain = false;
  double _bend = 0;
  double _master = 0.68;
  FlLocalTone _tone = FlLocalTone.warm;

  bool get ready => _engine.isInitialized && _tonalSource != null;

  Future<void> ensureReady() => _initializing ??= _init();

  Future<void> _init() async {
    if (!_engine.isInitialized) {
      await _engine.init(
        sampleRate: 48000,
        bufferSize: 256,
        channels: Channels.stereo,
        lowLatency: true,
      );
      // Keep the device warm enough for musical input, but still allow it to
      // sleep after a longer idle period to avoid needless power drain.
      _engine.setAudioDeviceIdleTimeout(const Duration(seconds: 20));
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
      panic();
      return;
    }
    await ensureReady();
    if (_tone != tone && _tonalSource != null) {
      _tone = tone;
      _engine.setWaveform(_tonalSource!, _waveFor(tone));
    }
  }

  Future<void> noteOn(
    int midiNote,
    int velocity, {
    bool percussive = false,
  }) async {
    await ensureReady();

    final note = midiNote.clamp(0, 127);
    final vel = velocity.clamp(1, 127);
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

    _active.putIfAbsent(note, () => <SoundHandle>[]).add(handle);
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
      Timer(const Duration(milliseconds: 170), () => _forget(note, handle));
    }
  }

  void noteOff(int midiNote) {
    final note = midiNote.clamp(0, 127);
    if (_sustain) {
      _sustainedNotes.add(note);
      return;
    }
    _releaseNote(note);
  }

  void setSustain(bool enabled) {
    _sustain = enabled;
    if (!enabled) {
      final notes = _sustainedNotes.toList(growable: false);
      _sustainedNotes.clear();
      for (final note in notes) {
        _releaseNote(note);
      }
    }
  }

  void setPitchBend(double bend) {
    _bend = bend.clamp(-1.0, 1.0);
    final bendScale = math.pow(2, (_bend * 2) / 12).toDouble();
    for (final entry in _active.entries) {
      final baseScale = math.pow(2, (entry.key - 69) / 12).toDouble();
      for (final handle in entry.value) {
        if (_engine.getIsValidVoiceHandle(handle)) {
          _engine.setRelativePlaySpeed(handle, baseScale * bendScale);
        }
      }
    }
  }

  void _releaseNote(int note) {
    final handles = _active.remove(note);
    if (handles == null) return;

    for (final handle in handles) {
      if (!_engine.getIsValidVoiceHandle(handle)) continue;
      _engine.fadeVolume(handle, 0, const Duration(milliseconds: 55));
      _engine.scheduleStop(handle, const Duration(milliseconds: 65));
    }
  }

  void _forget(int note, SoundHandle handle) {
    final handles = _active[note];
    if (handles == null) return;
    handles.remove(handle);
    if (handles.isEmpty) _active.remove(note);
  }

  void panic() {
    _sustainedNotes.clear();
    _active.clear();
    if (_engine.isInitialized) {
      _engine.stopAll();
    }
  }
}
