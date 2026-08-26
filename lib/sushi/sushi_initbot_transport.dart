import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_config.dart';

/// Assignment envelope from init-bot (docs/02 §1, docs/03).
class SushiAssignment {
  const SushiAssignment({
    required this.apiBotUsername,
    required this.pool,
    required this.providerId,
    required this.bindingToken,
    required this.epoch,
    this.pending = false,
    this.msgType = 0,
    this.corr = 0,
    this.rawReply = '',
    this.payloadBase64 = '',
    this.isError = false,
  });

  final String apiBotUsername;
  final List<String> pool;
  final String providerId;
  final String bindingToken;
  final int epoch;

  /// True when `/initbot` could not complete (bridge missing / timeout / ERR).
  final bool pending;

  /// Envelope `type` varint (15 = ASSIGNMENT, 14 = ERR).
  final int msgType;
  final int corr;
  final String rawReply;
  final String payloadBase64;
  final bool isError;

  static const int msgTypeErr = 14;
  static const int msgTypeAssignment = 15;

  Map<String, dynamic> toJson() => {
        'apiBotUsername': apiBotUsername,
        'pool': pool,
        'providerId': providerId,
        'bindingToken': bindingToken,
        'epoch': epoch,
        'pending': pending,
        'msgType': msgType,
        'corr': corr,
        'rawReply': rawReply,
        'payloadBase64': payloadBase64,
        'isError': isError,
      };

  factory SushiAssignment.fromJson(Map<String, dynamic> json) {
    return SushiAssignment(
      apiBotUsername: (json['apiBotUsername'] as String?) ?? '',
      pool: (json['pool'] as List?)?.cast<String>() ?? const [],
      providerId: (json['providerId'] as String?) ?? '',
      bindingToken: (json['bindingToken'] as String?) ?? '',
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
      pending: json['pending'] == true,
      msgType: (json['msgType'] as num?)?.toInt() ?? 0,
      corr: (json['corr'] as num?)?.toInt() ?? 0,
      rawReply: (json['rawReply'] as String?) ?? '',
      payloadBase64: (json['payloadBase64'] as String?) ?? '',
      isError: json['isError'] == true,
    );
  }

  factory SushiAssignment.stubPending({String reason = ''}) => SushiAssignment(
        apiBotUsername: '',
        pool: const [],
        providerId: '',
        bindingToken: '',
        epoch: 0,
        pending: true,
        rawReply: reason,
      );
}

abstract final class SushiAssignmentStore {
  static const _prefsKey = 'sushi.assignment.v1';

  static Future<void> save(SushiAssignment assignment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(assignment.toJson()));
  }

  static Future<SushiAssignment?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SushiAssignment.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

/// After TDLib Ready: do **not** POST `/auth/telegram`.
///
/// Sends `/initbot <corr>` to @[SushiConfig.initBotUsername], waits for `!` + base64url envelope,
/// classifies ASSIGNMENT (15) vs ERR (14), persists result.
Future<SushiAssignment> sushiRunInitbotAfterTdlibReady() async {
  assert(SushiConfig.isEnabled);
  final corr = _newCorrBase36();
  final cmd = '/initbot $corr';
  final bot = SushiConfig.initBotUsername;

  try {
    final controller = OxplayerTdlibBridgeController.instance();
    final reply = await controller.sendTextAndWaitReply(
      username: bot,
      text: cmd,
      timeoutMs: 30000,
    );
    final assignment = sushiParseInitbotReply(reply, expectedCorrBase36: corr);
    await SushiAssignmentStore.save(assignment);
    debugPrint(
      '[sushi] initbot ok pending=${assignment.pending} type=${assignment.msgType} '
      'err=${assignment.isError} payloadLen=${assignment.payloadBase64.length}',
    );
    return assignment;
  } catch (e, st) {
    debugPrint('[sushi] initbot failed: $e\n$st');
    final pending = SushiAssignment.stubPending(reason: e.toString());
    await SushiAssignmentStore.save(pending);
    return pending;
  }
}

/// Parse `!` + base64url(envelope). Stores raw payload for later protobuf decode.
SushiAssignment sushiParseInitbotReply(String reply, {String? expectedCorrBase36}) {
  final trimmed = reply.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('!')) {
    return SushiAssignment.stubPending(reason: 'reply missing ! marker');
  }
  final b64 = trimmed.substring(1);
  late final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Url.decode(_padBase64Url(b64)));
  } catch (e) {
    return SushiAssignment.stubPending(reason: 'base64url decode failed: $e');
  }
  if (bytes.isEmpty) {
    return SushiAssignment.stubPending(reason: 'empty envelope');
  }
  final ver = bytes[0];
  if (ver != 1) {
    return SushiAssignment.stubPending(reason: 'unsupported envelope version $ver');
  }
  var offset = 1;
  final corrR = _readVarint(bytes, offset);
  offset = corrR.next;
  final typeR = _readVarint(bytes, offset);
  offset = typeR.next;
  final flagsR = _readVarint(bytes, offset);
  offset = flagsR.next;
  final payload = bytes.sublist(offset);
  final msgType = typeR.value;
  final isErr = msgType == SushiAssignment.msgTypeErr;
  final isAssign = msgType == SushiAssignment.msgTypeAssignment;
  return SushiAssignment(
    apiBotUsername: '',
    pool: const [],
    providerId: '',
    bindingToken: '',
    epoch: 0,
    pending: !isAssign,
    msgType: msgType,
    corr: corrR.value,
    rawReply: trimmed,
    payloadBase64: base64Url.encode(payload),
    isError: isErr,
  );
}

String _newCorrBase36() {
  final n = Random.secure().nextInt(0x3fffffff) + 1;
  return n.toRadixString(36);
}

String _padBase64Url(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s.padRight(s.length + (4 - mod), '=');
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
