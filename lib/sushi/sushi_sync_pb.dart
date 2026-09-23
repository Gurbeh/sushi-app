import 'dart:typed_data';

import 'package:fladder/sushi/sushi_wire.dart';

/// Hand-decode/encode of `sushi.v1.SyncReq`/`SyncRes`/`WatchedState` (proto/sushi/v1/sync.proto) —
/// cross-device watched-state sync (docs/11 §6.1). Same style as sushi_item_pb.dart. v1 carries
/// only the watched delta; there is no catalog_watermark yet (docs/11 §6 is not built).

/// Encodes a `sushi.v1.SyncReq`: field 1 `watched_watermark` (varint).
Uint8List sushiEncodeSyncReq({required int watchedWatermark}) {
  final out = BytesBuilder();
  if (watchedWatermark != 0) {
    out.add(sushiUvarint((1 << 3) | 0));
    out.add(sushiUvarint(watchedWatermark));
  }
  return out.toBytes();
}

/// One `sushi.v1.WatchedState`: an episode that changed since the caller's watermark.
class SushiWatchedState {
  const SushiWatchedState({required this.episodeId, required this.done});

  final int episodeId;
  final bool done;

  static SushiWatchedState decode(Uint8List bytes) {
    var episodeId = 0;
    var done = false;
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          episodeId = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          done = v.value != 0;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiWatchedState(episodeId: episodeId, done: done);
  }
}

/// Decoded `sushi.v1.SyncRes`.
class SushiSyncRes {
  const SushiSyncRes({
    required this.watched,
    required this.watchedWatermark,
    required this.watchedMore,
  });

  final List<SushiWatchedState> watched;
  final int watchedWatermark;
  final bool watchedMore;

  static SushiSyncRes decode(Uint8List bytes) {
    final watched = <SushiWatchedState>[];
    var watchedWatermark = 0;
    var watchedMore = false;
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          watched.add(SushiWatchedState.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          watchedWatermark = v.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          watchedMore = v.value != 0;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiSyncRes(
      watched: List.unmodifiable(watched),
      watchedWatermark: watchedWatermark,
      watchedMore: watchedMore,
    );
  }
}
