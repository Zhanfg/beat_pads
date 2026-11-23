/// Orders note release against asynchronous audio engine startup.
///
/// Pending tonal starts are grouped by voice so releasing a key cancels all
/// of its pending requests without affecting a different key or a retrigger.
final class LocalSynthStartup {
  Object _generation = Object();
  final Map<(int, int), Set<Object>> _pending = {};
  final Set<(int, int)> _sustainedVoices = {};

  bool _sustain = false;

  Future<void> start(
    (int, int) voice, {
    required bool percussive,
    required Future<void> Function() ready,
    required void Function((int, int)) release,
    required void Function() play,
  }) async {
    final generation = _generation;
    final request = Object();

    if (!percussive) {
      // A retrigger replaces the prior released key, even if that key was
      // still waiting for audio startup when the pedal caught its release.
      if (_sustainedVoices.remove(voice)) _release(voice, release);
      _pending.putIfAbsent(voice, () => <Object>{}).add(request);
    }

    try {
      await ready();
      if (!identical(generation, _generation)) return;
      if (!percussive && !(_pending[voice]?.contains(request) ?? false)) {
        return;
      }
      // Keep this synchronous: release must not interleave between checking
      // the request and registering the actual sound handle.
      play();
    } finally {
      if (!percussive) {
        final requests = _pending[voice];
        if (requests != null && requests.remove(request) && requests.isEmpty) {
          _pending.remove(voice);
        }
      }
    }
  }

  void noteOff((int, int) voice, void Function((int, int)) release) {
    if (_sustain) {
      _sustainedVoices.add(voice);
      return;
    }
    _release(voice, release);
  }

  void setSustain(bool enabled, void Function((int, int)) release) {
    _sustain = enabled;
    if (!enabled) {
      final voices = _sustainedVoices.toList(growable: false);
      _sustainedVoices.clear();
      for (final voice in voices) {
        _release(voice, release);
      }
    }
  }

  void _release((int, int) voice, void Function((int, int)) release) {
    _pending.remove(voice);
    release(voice);
  }

  void panic() {
    _generation = Object();
    _pending.clear();
    _sustainedVoices.clear();
  }
}
