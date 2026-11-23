import 'dart:async';

import 'package:beat_pads/services/audio/local_synth_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = (11, 60);
  const b = (22, 64);
  late LocalSynthStartup startup;
  late List<String> played;
  late List<(int, int)> released;

  setUp(() {
    startup = LocalSynthStartup();
    played = [];
    released = [];
  });

  Future<void> start(
    (int, int) voice,
    Completer<void> gate,
    String id, {
    bool percussive = false,
  }) => startup.start(
    voice,
    percussive: percussive,
    ready: () => gate.future,
    release: released.add,
    play: () => played.add(id),
  );

  test('cold start plays only the finger still held', () async {
    final gate = Completer<void>();
    final first = start(a, gate, 'released');
    final second = start(b, gate, 'held');
    startup.noteOff(a, released.add);
    gate.complete();

    await Future.wait([first, second]);
    expect(played, ['held']);
    expect(released, [a]);
  });

  test('release and retrigger keeps only the newer request', () async {
    final gate = Completer<void>();
    final old = start(a, gate, 'old');
    startup.noteOff(a, released.add);
    final fresh = start(a, gate, 'fresh');
    gate.complete();

    await Future.wait([old, fresh]);
    expect(played, ['fresh']);
  });

  test('sustain permits a released tone until the pedal comes up', () async {
    final gate = Completer<void>();
    final started = start(a, gate, 'sustained');
    startup.setSustain(true, released.add);
    startup.noteOff(a, released.add);
    gate.complete();

    await started;
    expect(played, ['sustained']);
    expect(released, isEmpty);
    startup.setSustain(false, released.add);
    expect(released, [a]);
  });

  test('pedal up cancels released tones before startup finishes', () async {
    final gate = Completer<void>();
    final started = start(a, gate, 'released');
    startup.setSustain(true, released.add);
    startup.noteOff(a, released.add);
    startup.setSustain(false, released.add);
    gate.complete();

    await started;
    expect(played, isEmpty);
    expect(released, [a]);
  });

  test('held retrigger replaces a pending sustained tone', () async {
    final gate = Completer<void>();
    final first = start(a, gate, 'first');
    startup.setSustain(true, released.add);
    startup.noteOff(a, released.add);
    final held = start(a, gate, 'held');
    startup.setSustain(false, released.add);
    gate.complete();

    await Future.wait([first, held]);
    expect(played, ['held']);
    expect(released, [a]);
  });

  test('release does not suppress a pending drum one-shot', () async {
    final gate = Completer<void>();
    final drum = start(a, gate, 'drum', percussive: true);
    startup.noteOff(a, released.add);
    gate.complete();

    await drum;
    expect(played, ['drum']);
  });

  test('panic cancels both types without affecting a new tone', () async {
    final gate = Completer<void>();
    final tone = start(a, gate, 'old tone');
    final drum = start(b, gate, 'old drum', percussive: true);
    startup.panic();
    final fresh = start(a, gate, 'fresh');
    gate.complete();

    await Future.wait([tone, drum, fresh]);
    expect(played, ['fresh']);
  });

  test('failed readiness does not clear a newer request', () async {
    final failing = Completer<void>();
    final successful = Completer<void>();
    final old = start(a, failing, 'old');
    final failure = expectLater(old, throwsStateError);
    startup.panic();
    final fresh = start(a, successful, 'fresh');
    failing.completeError(StateError('device start failed'));
    await failure;
    successful.complete();

    await fresh;
    expect(played, ['fresh']);
  });
}
