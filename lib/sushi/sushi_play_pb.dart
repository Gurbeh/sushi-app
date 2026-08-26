import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand-decode/encode of `sushi.v1.PlayReq`/`PlayRes`/`Delivered`/`Pending`/`AckReq`/`AckRes`
/// (proto/sushi/v1/play.proto) — media delivery (docs/05). Same style as sushi_item_pb.dart.

/// Mirrors `sushi.v1.Mode`.
const sushiModeUnspecified = 0;
const sushiModeStream = 1;
const sushiModeDownload = 2;

/// A row that already exists: nothing to copy, hand back where it landed.
class SushiDelivered {
  const SushiDelivered({required this.botId, required this.messageId, required this.locator});

  final int botId;
  final int messageId;
  final String locator;

  static SushiDelivered decode(Uint8List bytes) {
    var botId = 0;
    var messageId = 0;
    var locator = '';
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          botId = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          messageId = v.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          locator = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiDelivered(botId: botId, messageId: messageId, locator: locator);
  }
}

/// The copy has been queued; deliveryd performs it out of band (docs/05 §4).
class SushiPending {
  const SushiPending({required this.locator});

  final String locator;

  static SushiPending decode(Uint8List bytes) {
    var locator = '';
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      if (field == 1) {
        final lenR = sushiReadVarint(bytes, i);
        i = lenR.next;
        locator = utf8.decode(bytes.sublist(i, i + lenR.value));
        i += lenR.value;
      } else {
        i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPending(locator: locator);
  }
}

/// Decoded `sushi.v1.PlayRes` — exactly one of [delivered]/[pending] is non-null.
class SushiPlayRes {
  const SushiPlayRes({this.delivered, this.pending});

  final SushiDelivered? delivered;
  final SushiPending? pending;

  static SushiPlayRes decode(Uint8List bytes) {
    SushiDelivered? delivered;
    SushiPending? pending;
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          delivered = SushiDelivered.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          pending = SushiPending.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPlayRes(delivered: delivered, pending: pending);
  }
}

/// Encodes a `sushi.v1.PlayReq`: field 1 `file_id` (varint), field 2 `force` (varint bool),
/// field 3 `mode` (varint enum).
Uint8List sushiEncodePlayReq({required int fileId, bool force = false, int mode = sushiModeStream}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (fileId != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(fileId));
  }
  if (force) {
    writeTag(2, 0);
    out.add(sushiUvarint(1));
  }
  if (mode != 0) {
    writeTag(3, 0);
    out.add(sushiUvarint(mode));
  }
  return out.toBytes();
}

/// Encodes a `sushi.v1.AckReq`: field 1 `file_id` (varint), field 2 `message_id` (varint).
Uint8List sushiEncodeAckReq({required int fileId, required int messageId}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (fileId != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(fileId));
  }
  if (messageId != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(messageId));
  }
  return out.toBytes();
}
