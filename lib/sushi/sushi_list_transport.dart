import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

const _msgTypePersonRes = 23;
const _msgTypeListRes = 25;

Future<SushiPersonRes?> sushiFetchPerson({required int tmdbId}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiBotUsername.isEmpty) {
    return null;
  }
  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('person', corr, sushiEncodePersonReq(tmdbId: tmdbId));
  try {
    final reply = await sushiSendTextAndWaitReply(
      username: assignment.apiBotUsername,
      text: requestText,
      timeoutMs: 25000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr || env.type != _msgTypePersonRes) {
      debugPrint('[sushi] person: unexpected type=${env.type} tmdbId=$tmdbId');
      return null;
    }
    return SushiPersonRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] person fetch failed: $e\n$st');
    return null;
  }
}

Future<SushiListRes?> sushiFetchList({
  required SushiListScope scope,
  SushiListSort sort = SushiListSort.name,
  bool sortDesc = false,
  String genre = '',
  int year = 0,
  String q = '',
  int cursor = 0,
  int playlistId = 0,
}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiBotUsername.isEmpty) {
    return null;
  }
  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText(
    'list',
    corr,
    sushiEncodeListReq(
      scope: scope,
      sort: sort,
      sortDesc: sortDesc,
      genre: genre,
      year: year,
      q: q,
      cursor: cursor,
      playlistId: playlistId,
    ),
  );
  try {
    final reply = await sushiSendTextAndWaitReply(
      username: assignment.apiBotUsername,
      text: requestText,
      timeoutMs: 15000,
    );
    final env = SushiEnvelope.decode(reply);
    if (env.type == SushiEnvelope.msgTypeErr || env.type != _msgTypeListRes) {
      debugPrint('[sushi] list: unexpected type=${env.type}');
      return null;
    }
    return SushiListRes.decode(env.payload);
  } catch (e, st) {
    debugPrint('[sushi] list fetch failed: $e\n$st');
    return null;
  }
}

/// Fire-and-forget fav/later (docs/11).
Future<void> sushiSendFavEvent({required int tmdbId, required int kind, required bool on}) async {
  await _sendFlagEvent(field: 1, tmdbId: tmdbId, kind: kind, on: on);
}

Future<void> sushiSendLaterEvent({required int tmdbId, required int kind, required bool on}) async {
  await _sendFlagEvent(field: 2, tmdbId: tmdbId, kind: kind, on: on);
}

Future<void> _sendFlagEvent({required int field, required int tmdbId, required int kind, required bool on}) async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending || assignment.apiBotUsername.isEmpty) {
    return;
  }
  // Events { seq=1, events=[ Event { fav|later = { tmdb_id, kind, on } } ] }
  final inner = BytesBuilder();
  void writeTag(BytesBuilder b, int f, int wire) => b.add(sushiUvarint((f << 3) | wire));
  writeTag(inner, 1, 0);
  inner.add(sushiUvarint(tmdbId));
  writeTag(inner, 2, 0);
  inner.add(sushiUvarint(kind));
  if (on) {
    writeTag(inner, 3, 0);
    inner.add(sushiUvarint(1));
  }
  final event = BytesBuilder();
  writeTag(event, field, 2);
  final body = inner.toBytes();
  event.add(sushiUvarint(body.length));
  event.add(body);
  final events = BytesBuilder();
  writeTag(events, 1, 0);
  events.add(sushiUvarint(DateTime.now().millisecondsSinceEpoch & 0x3fffffff));
  writeTag(events, 2, 2);
  final evBytes = event.toBytes();
  events.add(sushiUvarint(evBytes.length));
  events.add(evBytes);

  final corr = sushiNewCorrBase36();
  final requestText = sushiEncodeRequestText('ev', corr, events.toBytes());
  try {
    await sushiSendTextFireAndForget(username: assignment.apiBotUsername, text: requestText);
  } catch (e) {
    debugPrint('[sushi] ev failed: $e');
  }
}
