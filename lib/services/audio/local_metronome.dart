import 'dart:async';

import 'package:beat_pads/services/audio/local_synth.dart';

/// Lightweight standalone metronome for the workstation.
///
/// This clock is intentionally independent from external MIDI transport. It
/// drives the local synth so the app remains useful with no DAW connected.
final class LocalMetronome {
  Timer? _timer;
  int _tempo = 120;
  int _beat = 0;
  int _voiceSequence = -1000000;

  bool get running => _timer != null;
  int get tempo => _tempo;

  void start(int tempo) {
    _tempo = tempo.clamp(40, 240).toInt();
    stop();
    _beat = 0;
    _tick();
    _timer = Timer.periodic(_period, (_) => _tick());
  }

  void setTempo(int tempo) {
    final next = tempo.clamp(40, 240).toInt();
    if (_tempo == next) return;
    _tempo = next;
    if (running) {
      final beat = _beat;
      _timer?.cancel();
      _beat = beat;
      _timer = Timer.periodic(_period, (_) => _tick());
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Duration get _period => Duration(
        microseconds: (60000000 / _tempo).round(),
      );

  void _tick() {
    final accent = _beat % 4 == 0;
    unawaited(
      LocalSynth.instance.noteOn(
        accent ? 84 : 76,
        accent ? 118 : 88,
        percussive: true,
        voiceId: _voiceSequence--,
      ),
    );
    _beat++;
  }

  void dispose() => stop();
}
