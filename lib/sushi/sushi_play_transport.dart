import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypePlayRes = 10;
const _msgTypeAckRes = 21;

/// Sends `/play` for one file (docs/05 §3-4). Idempotent — an existing delivery row is returned
/// as-is by the server, so calling this more than once for the same [fileId] is cheap and safe.
/// Returns null on any transport failure (never throws) — same defensive style as
/// `sushiFetchItem`/`sushiFetchHome`.
Future<SushiPlayRes?> sushiPlay({required int fileId, bool force = false, int mode = sushiModeStream}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiBotUsername.isEmpty) {
    debugPrint('[sushi] play: no assignment yet, skipping fetch');
    return null;
  }

  final corr = sushiNewCorrBase36();
  final requestText =
      sushiEncodeRequestText('play', corr, sushiEncodePlayReq(fileId: fileId, force: force, mode: mode));

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: assignment.apiBotUsername,
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] play: server returned ERR (corr=${env.corr})');
      return null;
    }
    if (env.type != _msgTypePlayRes) {
      debugPrint('[sushi] play: unexpected msgType=${env.type} (corr=${env.corr})');
      return null;
    }
    return SushiPlayRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] play fetch failed: $e\n$st');
    return null;
  }
}

/// Sends `/ack` reporting the message id the client actually saw (docs/05 §4, "does not wait for
/// the server to acknowledge the ack" — callers should not await this before starting playback).
/// Best-effort: a failure here only costs one redundant copy on a future play, never a broken one.
Future<void> sushiAck({required int fileId, required int messageId}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiBotUsername.isEmpty) return;

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('ack', corr, sushiEncodeAckReq(fileId: fileId, messageId: messageId));

  try {
    final reply = await sushiSendTextAndWaitReply(
      username: assignment.apiBotUsername,
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type != _msgTypeAckRes && env.type != SushiEnvelope.msgTypeErr) {
      debugPrint('[sushi] ack: unexpected msgType=${env.type} (corr=${env.corr})');
    }
  } catch (e) {
    debugPrint('[sushi] ack failed (non-fatal): $e');
  }
}
