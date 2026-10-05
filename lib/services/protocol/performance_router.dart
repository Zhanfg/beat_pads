import 'dart:async';

import 'package:beat_pads/services/audio/local_synth.dart';
import 'package:beat_pads/services/protocol/axyp_event.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';

typedef IntReader = int Function();
typedef BoolReader = bool Function();
typedef VoidEventTap = void Function(AxypEvent event);

/// One routing core for every performance event.
///
/// UI surfaces publish AXYP events here. MIDI, local audio and future network
/// bridges subscribe at this boundary instead of reimplementing note logic.
final class PerformanceRouter {
  PerformanceRouter({
    required IntReader channel,
    required IntReader velocity,
    required BoolReader localAudioEnabled,
    required BoolReader percussive,
    this.eventTap,
  })  : _channel = channel,
        _velocity = velocity,
        _localAudioEnabled = localAudioEnabled,
        _percussive = percussive;

  final IntReader _channel;
  final IntReader _velocity;
  final BoolReader _localAudioEnabled;
  final BoolReader _percussive;
  final VoidEventTap? eventTap;

  int _sequence = 0;

  int _nextSequence() => (_sequence = (_sequence + 1) & 0xFFFFFFFF);
  int _now() => DateTime.now().microsecondsSinceEpoch;

  void noteOn(
    int note, {
    int? velocity,
    int pointerId = -1,
    bool? percussive,
  }) {
    final event = AxypNoteOn(
      sequence: _nextSequence(),
      timestampMicros: _now(),
      channel: _channel(),
      pointerId: pointerId,
      note: note.clamp(0, 127).toInt(),
      velocity: (velocity ?? _velocity()).clamp(1, 127).toInt(),
      percussive: percussive ?? _percussive(),
    );
    _dispatch(event);
  }

  void noteOff(int note, {int pointerId = -1}) {
    _dispatch(
      AxypNoteOff(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
        pointerId: pointerId,
        note: note.clamp(0, 127).toInt(),
      ),
    );
  }

  void control(int controller, int value) {
    _dispatch(
      AxypControl(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
        controller: controller.clamp(0, 127).toInt(),
        value: value.clamp(0, 127).toInt(),
      ),
    );
  }

  void pitch(double value) {
    _dispatch(
      AxypPitch(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
        value: value.clamp(-1.0, 1.0),
      ),
    );
  }

  void sustain(bool enabled) {
    _dispatch(
      AxypSustain(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
        enabled: enabled,
      ),
    );
  }

  Future<void> transport(int controller) async {
    _dispatch(
      AxypTransport(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
        controller: controller,
        pressed: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 24));
    _dispatch(
      AxypTransport(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
        controller: controller,
        pressed: false,
      ),
    );
  }

  void panic() {
    _dispatch(
      AxypPanic(
        sequence: _nextSequence(),
        timestampMicros: _now(),
        channel: _channel(),
      ),
    );
  }

  void _dispatch(AxypEvent event) {
    eventTap?.call(event);

    switch (event) {
      case AxypNoteOn e:
        NoteOnMessage(
          channel: e.channel,
          note: e.note,
          velocity: e.velocity,
        ).send();
        if (_localAudioEnabled()) {
          unawaited(
            LocalSynth.instance.noteOn(
              e.note,
              e.velocity,
              percussive: e.percussive,
              voiceId: e.pointerId,
            ),
          );
        }
        break;
      case AxypNoteOff e:
        NoteOffMessage(channel: e.channel, note: e.note).send();
        LocalSynth.instance.noteOff(e.note, voiceId: e.pointerId);
        break;
      case AxypControl e:
        CCMessage(
          channel: e.channel,
          controller: e.controller,
          value: e.value,
        ).send();
        break;
      case AxypPitch e:
        PitchBendMessage(channel: e.channel, bend: e.value).send();
        LocalSynth.instance.setPitchBend(e.value);
        break;
      case AxypSustain e:
        CCMessage(
          channel: e.channel,
          controller: 64,
          value: e.enabled ? 127 : 0,
        ).send();
        LocalSynth.instance.setSustain(e.enabled);
        break;
      case AxypTransport e:
        CCMessage(
          channel: e.channel,
          controller: e.controller,
          value: e.pressed ? 127 : 0,
        ).send();
        break;
      case AxypPanic e:
        CCMessage(channel: e.channel, controller: 123).send();
        LocalSynth.instance.panic();
        break;
    }
  }
}
