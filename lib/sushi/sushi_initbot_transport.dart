import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/sushi/sushi_assignment_pb.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Assignment from init-bot (docs/02 §1, docs/03, proto `sushi.v1.Assignment`).
class SushiAssignment {
  const SushiAssignment({
    required this.apiBotUsername,
    required this.pool,
    required this.providerId,
    required this.bindingToken,
    required this.epoch,
    this.deliveryBots = const [],
    this.pending = false,
    this.msgType = 0,
    this.corr = 0,
    this.rawReply = '',
    this.payloadBase64 = '',
    this.isError = false,
  });

  /// Proto field 1 `api_bot_username`.
  final String apiBotUsername;

  /// Proto field 2 `pool`.
  final List<String> pool;

  /// Proto field 3 `provider_id` (int32).
  final int providerId;

  /// Proto field 4 `binding_token` as base64url (no pad).
  final String bindingToken;

  /// Proto field 5 `epoch` (uint32).
  final int epoch;

  /// Proto field 6 `delivery_bots` — the pool deliveryd round-robins across (docs/05 §6),
  /// pre-started alongside the API bot so a first play doesn't fail `400 chat not found`.
  final List<String> deliveryBots;

  /// True when `/initbot` could not complete (bridge missing / timeout / ERR / bad payload).
  final bool pending;

  /// Envelope `type` varint (15 = ASSIGNMENT, 14 = ERR).
  final int msgType;
  final int corr;
  final String rawReply;

  /// Raw protobuf payload (debug / round-trip). Optional.
  final String payloadBase64;
  final bool isError;

  static const int msgTypeErr = 14;
  static const int msgTypeAssignment = 15;
  static const int flagCompressed = 1 << 0;

  Map<String, dynamic> toJson() => {
        'apiBotUsername': apiBotUsername,
        'pool': pool,
        'providerId': providerId,
        'bindingToken': bindingToken,
        'epoch': epoch,
        'deliveryBots': deliveryBots,
        'pending': pending,
        'msgType': msgType,
        'corr': corr,
        'rawReply': rawReply,
        'payloadBase64': payloadBase64,
        'isError': isError,
      };

  factory SushiAssignment.fromJson(Map<String, dynamic> json) {
    final rawProvider = json['providerId'];
    final providerId = rawProvider is int
        ? rawProvider
        : int.tryParse('$rawProvider') ?? 0;
    return SushiAssignment(
      apiBotUsername: (json['apiBotUsername'] as String?) ?? '',
      pool: (json['pool'] as List?)?.map((e) => '$e').toList() ?? const [],
      providerId: providerId,
      bindingToken: (json['bindingToken'] as String?) ?? '',
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
      deliveryBots: (json['deliveryBots'] as List?)?.map((e) => '$e').toList() ?? const [],
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
        providerId: 0,
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
/// decodes Assignment protobuf when type=15, persists result. Also clicks through main-bot's
/// onboarding first, since /initbot never creates a binding itself (docs/02 §1) — for a session
/// account, only that conversation does. Use this at login time; a bound session refreshing its
/// already-current Assignment should call [sushiRefreshInitbot] instead, which skips onboarding.
Future<SushiAssignment> sushiRunInitbotAfterTdlibReady() async {
  assert(SushiConfig.isEnabled);

  // Click through main-bot's onboarding now (no-op for a bot-token login) so a fresh identity has
  // something for /initbot to read, instead of asking the person to go find and message main-bot
  // by hand in Telegram.
  try {
    await sushiEnsureMainBotOnboarded(
      username: SushiConfig.mainBotUsername,
      timeoutMs: 90000,
    );
  } catch (e) {
    debugPrint('[sushi] main-bot onboarding failed (continuing to /initbot anyway): $e');
  }

  return sushiRefreshInitbot();
}

/// Re-runs `/initbot` for an already-bound session, without touching main-bot: /initbot is
/// idempotent (docs/02 §1), so this just re-syncs the Assignment — the API bot pool and delivery
/// bot list it carries can both change server-side after the client last asked (docs/02 §7, docs/10
/// Q3). Called once per cold start and whenever a bound API bot stops answering (docs/02 §6-7), so
/// it deliberately never touches the human-visible main-bot chat the way a fresh login does.
Future<SushiAssignment> sushiRefreshInitbot() async {
  assert(SushiConfig.isEnabled);
  final corr = sushiNewCorrBase36();
  final cmd = '/initbot $corr';
  final bot = SushiConfig.initBotUsername;

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: bot,
      text: cmd,
      timeoutMs: 30000,
    );
    final assignment = sushiParseInitbotReply(reply, expectedCorrBase36: corr);
    await SushiAssignmentStore.save(assignment);
    debugPrint(
      '[sushi] initbot ok pending=${assignment.pending} type=${assignment.msgType} '
      'apiBot=${assignment.apiBotUsername} epoch=${assignment.epoch} '
      'pool=${assignment.pool.length}',
    );

    // Keep every Sushi bot except main-bot out of the visible chat list — same start+mute+archive
    // treatment oxplayer already gives its delivery senders (OxplayerProviderBotsBootstrap).
    // main-bot is deliberately excluded: it's the one bot a person may actually want to open.
    //
    // Delivery bots ride along here too (docs/05 §6, docs/10 Q3): an API bot is sticky per user
    // and this warms it once for good, but deliveryd picks a delivery bot per copy — without this,
    // whichever one it happens to pick has never seen this chat, and the very first play fails
    // `400 chat not found`.
    if (!assignment.pending && assignment.apiBotUsername.isNotEmpty) {
      unawaited(sushiEnsureProviderBotsReady([
        OxTdlibProviderBot(id: 0, username: SushiConfig.initBotUsername),
        OxTdlibProviderBot(id: 0, username: assignment.apiBotUsername),
        for (final username in assignment.deliveryBots) OxTdlibProviderBot(id: 0, username: username),
      ]));
    }

    return assignment;
  } catch (e, st) {
    debugPrint('[sushi] initbot failed: $e\n$st');
    final pending = SushiAssignment.stubPending(reason: e.toString());
    await SushiAssignmentStore.save(pending);
    return pending;
  }
}

bool _sushiColdStartInitbotDone = false;

/// Fire-and-forget refresh, once per process: paints whatever is already cached immediately, then
/// quietly re-syncs in the background (docs/02 §7's cold-start half of bot rotation). Also arms the
/// reactive half here, once: after enough consecutive failures talking to the assigned API bot,
/// the bridge queue calls back into [sushiRefreshInitbot] on its own (docs/02 §6-7 — a bound bot
/// that has stopped answering).
void sushiRefreshInitbotOnColdStart() {
  if (_sushiColdStartInitbotDone) return;
  _sushiColdStartInitbotDone = true;
  onRepeatedSendFailure = () {
    debugPrint('[sushi] repeated send failures — refreshing /initbot');
    unawaited(sushiRefreshInitbot());
  };
  unawaited(sushiRefreshInitbot());
}

/// Parse `!` + base64url(envelope); decode Assignment protobuf when type == 15.
SushiAssignment sushiParseInitbotReply(String reply, {String? expectedCorrBase36}) {
  final SushiEnvelope env;
  try {
    env = SushiEnvelope.decode(reply);
  } catch (e) {
    return SushiAssignment.stubPending(reason: 'envelope decode failed: $e');
  }

  final isErr = env.type == SushiEnvelope.msgTypeErr;
  final isAssign = env.type == SushiEnvelope.msgTypeAssignment;
  final payloadB64 = base64Url.encode(env.payload);

  if (!isAssign) {
    return SushiAssignment(
      apiBotUsername: '',
      pool: const [],
      providerId: 0,
      bindingToken: '',
      epoch: 0,
      pending: true,
      msgType: env.type,
      corr: env.corr,
      rawReply: reply.trim(),
      payloadBase64: payloadB64,
      isError: isErr,
    );
  }

  try {
    final pb = SushiAssignmentPb.decode(env.payload);
    return SushiAssignment(
      apiBotUsername: pb.apiBotUsername,
      pool: pb.pool,
      providerId: pb.providerId,
      bindingToken: pb.bindingTokenBase64Url,
      epoch: pb.epoch,
      deliveryBots: pb.deliveryBots,
      pending: pb.apiBotUsername.isEmpty,
      msgType: env.type,
      corr: env.corr,
      rawReply: reply.trim(),
      payloadBase64: payloadB64,
      isError: false,
    );
  } catch (e) {
    return SushiAssignment(
      apiBotUsername: '',
      pool: const [],
      providerId: 0,
      bindingToken: '',
      epoch: 0,
      pending: true,
      msgType: env.type,
      corr: env.corr,
      rawReply: 'Assignment protobuf decode failed: $e',
      payloadBase64: payloadB64,
      isError: false,
    );
  }
}
