import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Serializes every Sushi-initiated call into the native TDLib bridge (home, initbot, item, files,
/// main-bot onboarding, bot archiving, ...) behind one queue, so at most one is ever in flight at a
/// time.
///
/// This exists for two reasons at once: it's the "one message per second" outbound scheduler
/// docs/11 §4 already calls for (never built, but the constraint is real regardless), and — found
/// the hard way, live on a real phone — running two of these calls concurrently (e.g. a dashboard
/// home refresh overlapping a detail screen's item fetch) crashes the whole process with a native
/// Go runtime fault (`fatal error: bulkBarrierPreWrite: unaligned arguments`), reproduced on both
/// an x86_64 emulator and an arm64 device. gomobile's generated JNI bridge is not safe to enter from
/// two threads at once for this client, so nothing may call it without going through here.
Future<void> _chain = Future.value();

Future<T> _enqueue<T>(Future<T> Function() call) {
  final result = _chain.then((_) => call());
  _chain = result.then((_) {}, onError: (_) {});
  return result;
}

/// Set by sushi_initbot_transport.dart. Fired after enough consecutive [sushiSendTextAndWaitReply]
/// failures in a row that the API pool looks dead, not just having one bad moment (docs/02
/// §6-7) — the reactive half of bot rotation, whose cold-start half is
/// sushiRefreshInitbotOnColdStart. A queue with nobody listening (this field left null) just logs
/// failures and moves on, same as before this existed.
void Function()? onRepeatedSendFailure;

/// How many sendTextAndWaitReply calls in a row must fail before [onRepeatedSendFailure] fires.
/// Not 1: a single timeout is routine (docs/02 §6 already retries within one request), this is for
/// "the bot really has stopped answering".
const _repeatedFailureThreshold = 2;
int _consecutiveSendFailures = 0;

/// Total [sushiSendTextAndWaitReply] calls since launch (or the last [sushiResetRequestCounter]) —
/// every Sushi wire command funnels through this one function, so this is a single, reliable place
/// to catch "over-requesting our bots" regressions without adding logging at every call site. Read
/// by the Sushi e2e suite (integration_test/sushi_e2e_test.dart); harmless in production.
int sushiRequestCount = 0;

void sushiResetRequestCounter() => sushiRequestCount = 0;

Future<String> sushiSendTextAndWaitReply({
  required String username,
  required String text,
  required int timeoutMs,
}) async {
  final controller = OxplayerTdlibBridgeController.instance();
  sushiRequestCount++;
  try {
    final reply = await _enqueue(
      () => controller.sendTextAndWaitReply(
          username: username, text: text, timeoutMs: timeoutMs),
    );
    _consecutiveSendFailures = 0;
    return reply;
  } catch (e) {
    final msg = e.toString();
    // Bot-to-bot is a session-identity problem, not a dead API bot. Refreshing /initbot here
    // wiped a good assignment and left home empty.
    if (msg.contains('USER_IS_BOT')) {
      debugPrint(
          '[sushi] send failed USER_IS_BOT — session is a bot; need phone/QR user login');
      rethrow;
    }
    _consecutiveSendFailures++;
    if (_consecutiveSendFailures >= _repeatedFailureThreshold) {
      _consecutiveSendFailures = 0;
      onRepeatedSendFailure?.call();
    }
    rethrow;
  }
}

/// Sends [text] to [username] without waiting for a reply (Sushi `/ack`, future watch-progress
/// reports). Still routed through the same queue as every other Sushi call — the underlying native
/// call crosses into the same gomobile client, so it must stay serialized against them — but it
/// resolves as soon as the send completes, never blocking on a reply that is not coming. Counted in
/// [sushiRequestCount] like every other wire call.
Future<void> sushiSendTextFireAndForget(
    {required String username, required String text}) {
  final controller = OxplayerTdlibBridgeController.instance();
  sushiRequestCount++;
  return _enqueue(
      () => controller.sendTextFireAndForget(username: username, text: text));
}

Future<void> sushiEnsureMainBotOnboarded(
    {required String username, required int timeoutMs}) {
  final controller = OxplayerTdlibBridgeController.instance();
  return _enqueue(
    () => controller.ensureMainBotOnboarded(
        username: username, timeoutMs: timeoutMs),
  );
}

Future<bool> sushiEnsureProviderBotsReady(List<OxTdlibProviderBot> bots) {
  final controller = OxplayerTdlibBridgeController.instance();
  return _enqueue(() => controller.ensureProviderBotsReady(bots));
}

Future<void> sushiArmDeliveryWaiter(String locator) {
  final controller = OxplayerTdlibBridgeController.instance();
  return _enqueue(() => controller.armDeliveryWaiter(locator));
}

Future<String> sushiStartPlaybackSession(OxTdlibPlaybackSource source) {
  final controller = OxplayerTdlibBridgeController.instance();
  return _enqueue(() => controller.startPlaybackSession(source));
}

Future<void> sushiStopPlaybackSession(String sessionUri) {
  if (sessionUri.isEmpty) return Future.value();
  final controller = OxplayerTdlibBridgeController.instance();
  return _enqueue(() => controller.stopPlaybackSession(sessionUri));
}

Future<OxTdlibDeliveryRef?> sushiDeliveryRefForLocator(String locator) {
  final controller = OxplayerTdlibBridgeController.instance();
  return _enqueue(() => controller.deliveryRefForLocator(locator));
}
