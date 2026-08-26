import 'dart:convert';
import 'dart:typed_data';

/// Hand-decode of `sushi.v1.Assignment` (proto/sushi/v1/bind.proto).
///
/// ```
/// string api_bot_username = 1;
/// repeated string pool = 2;
/// int32 provider_id = 3;
/// bytes binding_token = 4;
/// uint32 epoch = 5;
/// ```
class SushiAssignmentPb {
  const SushiAssignmentPb({
    required this.apiBotUsername,
    required this.pool,
    required this.providerId,
    required this.bindingToken,
    required this.epoch,
  });

  final String apiBotUsername;
  final List<String> pool;
  final int providerId;
  final Uint8List bindingToken;
  final int epoch;

  /// Base64url (no pad) of [bindingToken] for prefs / JSON.
  String get bindingTokenBase64Url =>
      base64Url.encode(bindingToken).replaceAll('=', '');

  /// Decode protobuf payload bytes (envelope payload only, after flags).
  static SushiAssignmentPb decode(Uint8List bytes) {
    var apiBotUsername = '';
    final pool = <String>[];
    var providerId = 0;
    var bindingToken = Uint8List(0);
    var epoch = 0;

    var i = 0;
    while (i < bytes.length) {
      final tagR = _readVarint(bytes, i);
      i = tagR.next;
      final tag = tagR.value;
      final field = tag >> 3;
      final wire = tag & 0x7;

      switch (field) {
        case 1: // api_bot_username
          if (wire != 2) throw FormatException('field 1 wire $wire');
          final lenR = _readVarint(bytes, i);
          i = lenR.next;
          apiBotUsername = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2: // pool (repeated)
          if (wire != 2) throw FormatException('field 2 wire $wire');
          final lenR = _readVarint(bytes, i);
          i = lenR.next;
          pool.add(utf8.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 3: // provider_id
          if (wire != 0) throw FormatException('field 3 wire $wire');
          final v = _readVarint(bytes, i);
          i = v.next;
          providerId = v.value;
        case 4: // binding_token
          if (wire != 2) throw FormatException('field 4 wire $wire');
          final lenR = _readVarint(bytes, i);
          i = lenR.next;
          bindingToken = Uint8List.fromList(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5: // epoch
          if (wire != 0) throw FormatException('field 5 wire $wire');
          final v = _readVarint(bytes, i);
          i = v.next;
          epoch = v.value;
        default:
          i = _skipField(bytes, i, wire);
      }
    }

    return SushiAssignmentPb(
      apiBotUsername: apiBotUsername,
      pool: List.unmodifiable(pool),
      providerId: providerId,
      bindingToken: bindingToken,
      epoch: epoch,
    );
  }

  /// Encode for tests (proto3 wire).
  static Uint8List encode({
    required String apiBotUsername,
    List<String> pool = const [],
    int providerId = 0,
    List<int> bindingToken = const [],
    int epoch = 0,
  }) {
    final out = BytesBuilder();
    void writeTag(int field, int wire) => out.add(_uvarint((field << 3) | wire));
    void writeBytes(List<int> b) {
      out.add(_uvarint(b.length));
      out.add(b);
    }

    if (apiBotUsername.isNotEmpty) {
      writeTag(1, 2);
      writeBytes(utf8.encode(apiBotUsername));
    }
    for (final p in pool) {
      writeTag(2, 2);
      writeBytes(utf8.encode(p));
    }
    if (providerId != 0) {
      writeTag(3, 0);
      out.add(_uvarint(providerId));
    }
    if (bindingToken.isNotEmpty) {
      writeTag(4, 2);
      writeBytes(bindingToken);
    }
    if (epoch != 0) {
      writeTag(5, 0);
      out.add(_uvarint(epoch));
    }
    return out.toBytes();
  }
}

List<int> _uvarint(int n) {
  final out = <int>[];
  var x = n;
  while (x >= 0x80) {
    out.add((x & 0x7f) | 0x80);
    x >>= 7;
  }
  out.add(x);
  return out;
}

({int value, int next}) _readVarint(Uint8List bytes, int offset) {
  var result = 0;
  var shift = 0;
  var i = offset;
  while (i < bytes.length) {
    final b = bytes[i++];
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) {
      return (value: result, next: i);
    }
    shift += 7;
    if (shift > 63) {
      throw FormatException('varint too long');
    }
  }
  throw FormatException('truncated varint');
}

int _skipField(Uint8List bytes, int i, int wire) {
  switch (wire) {
    case 0:
      return _readVarint(bytes, i).next;
    case 1:
      return i + 8;
    case 2:
      final lenR = _readVarint(bytes, i);
      return lenR.next + lenR.value;
    case 5:
      return i + 4;
    default:
      throw FormatException('unsupported wire type $wire');
  }
}
