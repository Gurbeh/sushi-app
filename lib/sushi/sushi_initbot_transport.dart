import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/sushi/sushi_config.dart';

/// Assignment envelope from init-bot (docs/02 §1). Stub-friendly until MTProto send lands.
class SushiAssignment {
  const SushiAssignment({
    required this.apiBotUsername,
    required this.pool,
    required this.providerId,
    required this.bindingToken,
    required this.epoch,
    this.pending = false,
  });

  final String apiBotUsername;
  final List<String> pool;
  final String providerId;
  final String bindingToken;
  final int epoch;

  /// True when `/initbot` could not be sent (bridge missing sendMessage).
  final bool pending;

  Map<String, dynamic> toJson() => {
        'apiBotUsername': apiBotUsername,
        'pool': pool,
        'providerId': providerId,
        'bindingToken': bindingToken,
        'epoch': epoch,
        'pending': pending,
      };

  factory SushiAssignment.fromJson(Map<String, dynamic> json) {
    return SushiAssignment(
      apiBotUsername: (json['apiBotUsername'] as String?) ?? '',
      pool: (json['pool'] as List?)?.cast<String>() ?? const [],
      providerId: (json['providerId'] as String?) ?? '',
      bindingToken: (json['bindingToken'] as String?) ?? '',
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
      pending: json['pending'] == true,
    );
  }

  /// Placeholder until pigeon/Go `sendTextMessage` exists.
  factory SushiAssignment.stubPending() => const SushiAssignment(
        apiBotUsername: '',
        pool: [],
        providerId: '',
        bindingToken: '',
        epoch: 0,
        pending: true,
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
/// Desired path: DM `@[SushiConfig.initBotUsername]` with `/initbot <corr>`, parse `!` Assignment
/// envelope, persist via [SushiAssignmentStore].
///
/// **Blocker:** [OxTdlibBridgeApi] has no `sendMessage` / `sendTextMessage`. Go has
/// `MessagesStartBot` for provider bots but no general text send. Wire
/// `go/oxtelegram` `SendTextToUsername` + pigeon before this becomes real.
///
/// Until then: persist a pending stub assignment so the rest of the shell can boot.
Future<SushiAssignment> sushiRunInitbotAfterTdlibReady() async {
  assert(SushiConfig.isEnabled);
  // ignore: avoid_print
  print(
    '[sushi] initbot stub — sendMessage missing on OxTdlibBridgeApi; '
    'target=@${SushiConfig.initBotUsername} cmd=/initbot',
  );
  final assignment = SushiAssignment.stubPending();
  await SushiAssignmentStore.save(assignment);
  return assignment;
}
