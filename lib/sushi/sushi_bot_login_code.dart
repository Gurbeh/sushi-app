import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Copy-paste blob from main-bot (ADR 0008). `s1.` + base64url of protobuf field 1 (token string).
const kSushiBotLoginCodePrefix = 's1.';

final _tokenShape = RegExp(r'^\d{6,}:[A-Za-z0-9_-]{20,}$');

bool sushiLooksLikeBotToken(String text) => _tokenShape.hasMatch(text.trim());

/// Encodes a BotFather token the same way main-bot does. Used in tests.
String sushiEncodeBotLoginCode(String token) {
  final t = token.trim();
  if (!sushiLooksLikeBotToken(t)) {
    throw FormatException('not a bot token');
  }
  final utf = utf8.encode(t);
  final payload = Uint8List.fromList([0x0a, ...sushiUvarint(utf.length), ...utf]);
  return kSushiBotLoginCodePrefix + base64Url.encode(payload).replaceAll('=', '');
}

/// Returns the token if [raw] is a well-formed app code; otherwise null.
String? sushiTryParseBotLoginCode(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith(kSushiBotLoginCodePrefix)) return null;
  final b64 = trimmed.substring(kSushiBotLoginCodePrefix.length);
  if (b64.isEmpty) return null;
  try {
    final payload = base64Url.decode(sushiPadBase64Url(b64));
    if (payload.isEmpty || payload[0] != 0x0a) return null;
    final lenR = sushiReadVarint(payload, 1);
    final start = lenR.next;
    final end = start + lenR.value;
    if (end > payload.length) return null;
    final token = utf8.decode(payload.sublist(start, end));
    if (!sushiLooksLikeBotToken(token)) return null;
    return token;
  } catch (_) {
    return null;
  }
}
