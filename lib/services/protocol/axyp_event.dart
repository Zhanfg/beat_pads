import 'dart:typed_data';

enum AxypEventType {
  noteOn(1),
  noteOff(2),
  control(3),
  pitch(4),
  sustain(5),
  transport(6),
  panic(7);

  const AxypEventType(this.code);
  final int code;

  static AxypEventType fromCode(int code) =>
      values.firstWhere((value) => value.code == code);
}

/// AXYP/1 = Axymorrsen eXtensible Performance Protocol.
///
/// Typed events are used in-process; [AxypCodec] is the stable binary wire
/// representation for future desktop, USB and network bridges.
sealed class AxypEvent {
  const AxypEvent({
    required this.type,
    required this.sequence,
    required this.timestampMicros,
    required this.channel,
    this.pointerId = -1,
  });

  final AxypEventType type;
  final int sequence;
  final int timestampMicros;
  final int channel;
  final int pointerId;
}

final class AxypNoteOn extends AxypEvent {
  const AxypNoteOn({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
    required super.pointerId,
    required this.note,
    required this.velocity,
    this.percussive = false,
  }) : super(type: AxypEventType.noteOn);

  final int note;
  final int velocity;
  final bool percussive;
}

final class AxypNoteOff extends AxypEvent {
  const AxypNoteOff({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
    required super.pointerId,
    required this.note,
  }) : super(type: AxypEventType.noteOff);

  final int note;
}

final class AxypControl extends AxypEvent {
  const AxypControl({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
    required this.controller,
    required this.value,
  }) : super(type: AxypEventType.control);

  final int controller;
  final int value;
}

final class AxypPitch extends AxypEvent {
  const AxypPitch({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
    required this.value,
  }) : super(type: AxypEventType.pitch);

  final double value;
}

final class AxypSustain extends AxypEvent {
  const AxypSustain({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
    required this.enabled,
  }) : super(type: AxypEventType.sustain);

  final bool enabled;
}

final class AxypTransport extends AxypEvent {
  const AxypTransport({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
    required this.controller,
    required this.pressed,
  }) : super(type: AxypEventType.transport);

  final int controller;
  final bool pressed;
}

final class AxypPanic extends AxypEvent {
  const AxypPanic({
    required super.sequence,
    required super.timestampMicros,
    required super.channel,
  }) : super(type: AxypEventType.panic);
}

abstract final class AxypCodec {
  static const List<int> _magic = <int>[0x41, 0x58, 0x59, 0x50]; // AXYP
  static const int version = 1;
  static const int headerLength = 26;

  /// Frame:
  /// magic[4], version[1], type[1], channel[1], flags[1],
  /// sequence[4], timestampMicros[8], pointerId[4], payloadLength[2], payload[n].
  static Uint8List encode(AxypEvent event) {
    final payload = switch (event) {
      AxypNoteOn e => <int>[
          e.note & 0x7F,
          e.velocity & 0x7F,
          e.percussive ? 1 : 0,
        ],
      AxypNoteOff e => <int>[e.note & 0x7F],
      AxypControl e => <int>[e.controller & 0x7F, e.value & 0x7F],
      AxypPitch e => _i16((e.value.clamp(-1.0, 1.0) * 32767).round()),
      AxypSustain e => <int>[e.enabled ? 1 : 0],
      AxypTransport e => <int>[e.controller & 0x7F, e.pressed ? 1 : 0],
      AxypPanic _ => const <int>[],
    };

    final data = ByteData(headerLength + payload.length);
    for (int i = 0; i < _magic.length; i++) {
      data.setUint8(i, _magic[i]);
    }
    data
      ..setUint8(4, version)
      ..setUint8(5, event.type.code)
      ..setUint8(6, event.channel & 0x0F)
      ..setUint8(7, 0)
      ..setUint32(8, event.sequence, Endian.big)
      ..setUint64(12, event.timestampMicros, Endian.big)
      ..setInt32(20, event.pointerId, Endian.big)
      ..setUint16(24, payload.length, Endian.big);

    for (int i = 0; i < payload.length; i++) {
      data.setUint8(headerLength + i, payload[i]);
    }
    return data.buffer.asUint8List();
  }

  static AxypEvent decode(Uint8List frame) {
    if (frame.length < headerLength) {
      throw const FormatException('AXYP frame is shorter than its header');
    }
    for (int i = 0; i < _magic.length; i++) {
      if (frame[i] != _magic[i]) {
        throw const FormatException('AXYP magic mismatch');
      }
    }

    final data = ByteData.sublistView(frame);
    final frameVersion = data.getUint8(4);
    if (frameVersion != version) {
      throw FormatException('Unsupported AXYP version: $frameVersion');
    }

    final type = AxypEventType.fromCode(data.getUint8(5));
    final channel = data.getUint8(6);
    final sequence = data.getUint32(8, Endian.big);
    final timestampMicros = data.getUint64(12, Endian.big);
    final pointerId = data.getInt32(20, Endian.big);
    final payloadLength = data.getUint16(24, Endian.big);
    if (frame.length != headerLength + payloadLength) {
      throw const FormatException('AXYP payload length mismatch');
    }

    int byte(int offset) => data.getUint8(headerLength + offset);

    return switch (type) {
      AxypEventType.noteOn when payloadLength == 3 => AxypNoteOn(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
          pointerId: pointerId,
          note: byte(0),
          velocity: byte(1),
          percussive: byte(2) != 0,
        ),
      AxypEventType.noteOff when payloadLength == 1 => AxypNoteOff(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
          pointerId: pointerId,
          note: byte(0),
        ),
      AxypEventType.control when payloadLength == 2 => AxypControl(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
          controller: byte(0),
          value: byte(1),
        ),
      AxypEventType.pitch when payloadLength == 2 => AxypPitch(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
          value: data.getInt16(headerLength, Endian.big) / 32767,
        ),
      AxypEventType.sustain when payloadLength == 1 => AxypSustain(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
          enabled: byte(0) != 0,
        ),
      AxypEventType.transport when payloadLength == 2 => AxypTransport(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
          controller: byte(0),
          pressed: byte(1) != 0,
        ),
      AxypEventType.panic when payloadLength == 0 => AxypPanic(
          sequence: sequence,
          timestampMicros: timestampMicros,
          channel: channel,
        ),
      _ => throw FormatException(
          'Invalid AXYP payload length $payloadLength for ${type.name}',
        ),
    };
  }

  static List<int> _i16(int value) {
    final data = ByteData(2)..setInt16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}
