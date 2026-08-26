import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart'
    show oxplayerIsTelegramDeliveryWaitTimeoutError, oxplayerIsTdlibFileMissingError;
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_play_transport.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Matches `be/internal/app/api/play.go`'s `locatorPrefix` — the client hard-codes it too
/// (docs/05 §3), so changing it is a wire break.
const _sushiLocatorPrefix = 'plm';

const _sushiPlayLogTag = 'OXPLAY_SUSHI';
void _log(String message) => debugPrint('$_sushiPlayLogTag: $message');

/// Resolves one Sushi file id to a playable url, following docs/05-media-delivery.md §4:
///
/// 1. Arm the delivery-bot waiter for this file's locator BEFORE asking (a push that arrives
///    before the waiter exists is lost forever for a bot-login client).
/// 2. Send `/play`. A `Delivered` answer names a remembered message (no copy needed); a `Pending`
///    answer means deliveryd is copying it now — the native `startPlaybackSession(0/0, locator)`
///    already knows how to wait on the armed locator waiter for that copy to land (the same
///    primitive `oxplayer_tdlib_playback_resolver.dart` uses for its own cold plays).
/// 3. A remembered message that turns out to be gone (deleted, wrong chat, cleared history) is a
///    "broken row" (docs/05 §4/§6): retry once with `force: true`, which makes the server delete
///    the row and re-deliver under the same locator — the waiter armed in step 1 is still good.
Future<String> sushiResolvePlaybackUrl({
  required int fileId,
  bool preferHttpBridge = false,
}) async {
  final locator = '${_sushiLocatorPrefix}_$fileId';
  await sushiArmDeliveryWaiter(locator);

  final playRes = await sushiPlay(fileId: fileId);
  if (playRes == null) {
    throw StateError('sushi play: no reply for file $fileId');
  }

  return _startSession(
    fileId: fileId,
    locator: locator,
    playRes: playRes,
    preferHttpBridge: preferHttpBridge,
  );
}

/// Polls [sushiDeliveryRefForLocator] (queued, so this never races the native side's own use of
/// the bridge) until the push lands or [timeout] elapses. Mirrors
/// `oxplayer_tdlib_playback_resolver.dart`'s `waitForTdlibDeliveryRef`, but through the Sushi
/// queue rather than calling the controller directly.
Future<OxTdlibDeliveryRef?> _pollDeliveryRef(
  String locator, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ref = await sushiDeliveryRefForLocator(locator);
    if (ref != null && ref.messageId > 0 && ref.providerBotId > 0) {
      return ref;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return sushiDeliveryRefForLocator(locator);
}

Future<String> _startSession({
  required int fileId,
  required String locator,
  required SushiPlayRes playRes,
  required bool preferHttpBridge,
  bool isRetry = false,
}) async {
  final delivered = playRes.delivered;
  final source = OxTdlibPlaybackSource(
    providerBotId: delivered?.botId ?? 0,
    messageId: delivered?.messageId ?? 0,
    preferHttpBridge: preferHttpBridge,
    locator: locator,
  );

  _log(
    'startPlaybackSession fileId=$fileId providerBotId=${source.providerBotId} '
    'messageId=${source.messageId} pending=${delivered == null} locator=$locator',
  );

  try {
    final session = await sushiStartPlaybackSession(source);
    _log('startPlaybackSession ok -> $session');
    final landedMessageId = delivered?.messageId ?? (await sushiDeliveryRefForLocator(locator))?.messageId;
    if (landedMessageId != null && landedMessageId > 0) {
      unawaited(sushiAck(fileId: fileId, messageId: landedMessageId));
    }
    return session;
  } catch (e) {
    _log('startPlaybackSession FAILED fileId=$fileId error=$e');
    if (isRetry) rethrow;

    if (oxplayerIsTelegramDeliveryWaitTimeoutError(e)) {
      // The native wait is a fixed 8s, but deliveryd's own idle-to-active latency can run close to
      // that on its own (up to maxIdleDelay) before the copyMessage round-trip even starts — a cold
      // first play can easily land just after the native side gives up (confirmed live: the push
      // arrived a few seconds after this exact timeout). Keep checking a while longer before
      // surfacing the failure.
      final landed = await _pollDeliveryRef(locator);
      if (landed != null && landed.messageId > 0 && landed.providerBotId > 0) {
        _log('retry after 0/0 timeout using landed botId=${landed.providerBotId} messageId=${landed.messageId}');
        return _startSession(
          fileId: fileId,
          locator: locator,
          playRes: SushiPlayRes(
            delivered: SushiDelivered(botId: landed.providerBotId, messageId: landed.messageId, locator: locator),
          ),
          preferHttpBridge: preferHttpBridge,
          isRetry: true,
        );
      }
    }

    if (delivered != null && oxplayerIsTdlibFileMissingError(e)) {
      _log('delivery stale for $locator — forcing re-delivery');
      final forced = await sushiPlay(fileId: fileId, force: true);
      if (forced != null) {
        return _startSession(
          fileId: fileId,
          locator: locator,
          playRes: forced,
          preferHttpBridge: preferHttpBridge,
          isRetry: true,
        );
      }
    }

    rethrow;
  }
}
