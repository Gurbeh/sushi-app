import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart'
    show oxplayerIsTelegramDeliveryWaitTimeoutError, oxplayerIsTdlibFileMissingError;
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_play_transport.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

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
  final locator = sushiLocatorForFile(fileId);
  final warmed = await sushiPlayWarmup.wait(fileId);
  if (warmed != null && warmed.messageId > 0) {
    await sushiArmDeliveryWaiter(locator);
    try {
      return await _startSession(
        fileId: fileId,
        locator: locator,
        playRes: SushiPlayRes(delivered: warmed),
        preferHttpBridge: preferHttpBridge,
      );
    } catch (e) {
      sushiPlayWarmup.invalidate(fileId);
      _log('warmup delivery unusable fileId=$fileId error=$e — falling through to /play');
    }
  }

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

SushiDelivered? _deliveredFromSessionRef(OxTdlibDeliveryRef? ref, String locator) {
  if (ref == null || ref.messageId <= 0 || ref.providerBotId <= 0) return null;
  return SushiDelivered(botId: ref.providerBotId, messageId: ref.messageId, locator: locator);
}

Future<String> _startSession({
  required int fileId,
  required String locator,
  required SushiPlayRes playRes,
  required bool preferHttpBridge,
  bool isRetry = false,
}) async {
  var delivered = playRes.delivered;
  // copyMessage's message_id is the *sender* numbering. Bot-login TDLib uses the receiver's.
  // A push that landed while /play was in flight is already in DeliveryRef — use that, don't 0/0.
  if (delivered == null || delivered.messageId == 0) {
    delivered = _deliveredFromSessionRef(await sushiDeliveryRefForLocator(locator), locator) ?? delivered;
  }

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

    if (oxplayerIsTelegramDeliveryWaitTimeoutError(e)) {
      final landed = await _pollDeliveryRef(locator);
      if (landed != null && landed.messageId > 0 && landed.providerBotId > 0) {
        _log('retry after 0/0 timeout using landed botId=${landed.providerBotId} messageId=${landed.messageId}');
        return _startSession(
          fileId: fileId,
          locator: locator,
          playRes: SushiPlayRes(delivered: _deliveredFromSessionRef(landed, locator)),
          preferHttpBridge: preferHttpBridge,
          isRetry: true,
        );
      }
      rethrow;
    }

    if (isRetry) rethrow;

    if (delivered != null && oxplayerIsTdlibFileMissingError(e)) {
      final sessionRef = _deliveredFromSessionRef(await sushiDeliveryRefForLocator(locator), locator);
      if (sessionRef != null && sessionRef.messageId != delivered.messageId) {
        _log('stale server id ${delivered.messageId}; using session ref ${sessionRef.messageId}');
        return _startSession(
          fileId: fileId,
          locator: locator,
          playRes: SushiPlayRes(delivered: sessionRef),
          preferHttpBridge: preferHttpBridge,
          isRetry: true,
        );
      }
      _log('delivery stale for $locator — forcing re-delivery');
      sushiPlayWarmup.invalidate(fileId);
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
