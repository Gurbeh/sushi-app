import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

Uint8List _tag(int field, int wire) => Uint8List.fromList(sushiUvarint((field << 3) | wire));

Uint8List _lenDelim(int field, List<int> bytes) {
  final out = BytesBuilder();
  out.add(_tag(field, 2));
  out.add(sushiUvarint(bytes.length));
  out.add(bytes);
  return out.toBytes();
}

Uint8List _varintField(int field, int value) {
  final out = BytesBuilder();
  out.add(_tag(field, 0));
  out.add(sushiUvarint(value));
  return out.toBytes();
}

Uint8List _encodeWatchedState({required int episodeId, required bool done}) {
  final out = BytesBuilder();
  if (episodeId != 0) out.add(_varintField(1, episodeId));
  if (done) out.add(_varintField(2, 1));
  return out.toBytes();
}

void main() {
  test('sushiEncodeSyncReq encodes watched_watermark, omits zero', () {
    expect(sushiEncodeSyncReq(watchedWatermark: 0), isEmpty);
    final bytes = sushiEncodeSyncReq(watchedWatermark: 42);
    final tagR = sushiReadVarint(bytes, 0);
    expect(tagR.value >> 3, 1);
    final v = sushiReadVarint(bytes, tagR.next);
    expect(v.value, 42);
  });

  test('SushiSyncRes decodes watched rows, watermark and watched_more', () {
    final w1 = _encodeWatchedState(episodeId: 1, done: true);
    final w2 = _encodeWatchedState(episodeId: 2, done: false);
    final out = BytesBuilder()
      ..add(_lenDelim(1, w1))
      ..add(_lenDelim(1, w2))
      ..add(_varintField(2, 30))
      ..add(_varintField(3, 1));

    final res = SushiSyncRes.decode(out.toBytes());
    expect(res.watched, hasLength(2));
    expect(res.watched[0].episodeId, 1);
    expect(res.watched[0].done, isTrue);
    expect(res.watched[1].episodeId, 2);
    expect(res.watched[1].done, isFalse);
    expect(res.watchedWatermark, 30);
    expect(res.watchedMore, isTrue);
  });

  test('SushiSyncRes decodes an empty reply (nothing new)', () {
    final res = SushiSyncRes.decode(Uint8List(0));
    expect(res.watched, isEmpty);
    expect(res.watchedWatermark, 0);
    expect(res.watchedMore, isFalse);
  });
}
