import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libcompress/libcompress.dart';
import 'package:fladder/sushi/sushi_assignment_pb.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';

void main() {
  test('SushiAssignmentPb round-trip fields 1-5', () {
    final token = utf8.encode('tok-bytes');
    final encoded = SushiAssignmentPb.encode(
      apiBotUsername: 'OXStreamer31bot',
      pool: const ['OXStreamer31bot', 'OXStreamer32bot'],
      providerId: 7,
      bindingToken: token,
      epoch: 3,
    );
    final pb = SushiAssignmentPb.decode(encoded);
    expect(pb.apiBotUsername, 'OXStreamer31bot');
    expect(pb.pool, ['OXStreamer31bot', 'OXStreamer32bot']);
    expect(pb.providerId, 7);
    expect(pb.bindingToken, token);
    expect(pb.epoch, 3);
    expect(pb.deliveryBots, isEmpty);
  });

  test('SushiAssignmentPb round-trips field 6 delivery_bots', () {
    final encoded = SushiAssignmentPb.encode(
      apiBotUsername: 'OXStreamer31bot',
      deliveryBots: const ['OXStreamer36bot', 'OXStreamer35bot', 'OXStreamer33bot'],
    );
    final pb = SushiAssignmentPb.decode(encoded);
    expect(pb.deliveryBots, ['OXStreamer36bot', 'OXStreamer35bot', 'OXStreamer33bot']);
  });

  test('sushiParseInitbotReply decodes Assignment protobuf', () {
    final payload = SushiAssignmentPb.encode(
      apiBotUsername: 'apiBotOne',
      pool: const ['apiBotOne', 'apiBotTwo'],
      providerId: 42,
      bindingToken: utf8.encode('bind-secret'),
      epoch: 9,
    );
    final envelope = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(1))
      ..add(_uvarint(15))
      ..add(_uvarint(0))
      ..add(payload);
    final reply = '!${base64Url.encode(envelope.toBytes()).replaceAll('=', '')}';

    final a = sushiParseInitbotReply(reply);
    expect(a.msgType, SushiAssignment.msgTypeAssignment);
    expect(a.pending, isFalse);
    expect(a.isError, isFalse);
    expect(a.apiBotUsername, 'apiBotOne');
    expect(a.pool, ['apiBotOne', 'apiBotTwo']);
    expect(a.providerId, 42);
    expect(a.epoch, 9);
    expect(a.bindingToken, isNotEmpty);
    expect(utf8.decode(base64Url.decode(_pad(a.bindingToken))), 'bind-secret');
    expect(a.payloadBase64, isNotEmpty);
  });

  test('sushiParseInitbotReply reads ERR type 14 as pending', () {
    final bytes = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(2))
      ..add(_uvarint(14))
      ..add(_uvarint(0));
    final reply = '!${base64Url.encode(bytes.toBytes()).replaceAll('=', '')}';
    final a = sushiParseInitbotReply(reply);
    expect(a.msgType, SushiAssignment.msgTypeErr);
    expect(a.isError, isTrue);
    expect(a.pending, isTrue);
    expect(a.apiBotUsername, isEmpty);
  });

  test('sushiParseInitbotReply decompresses FlagCompressed Assignment', () {
    final bigPool = List.generate(40, (i) => 'pool-bot-$i-${'x' * 8}');
    final fatPlain = SushiAssignmentPb.encode(
      apiBotUsername: 'compressedBot',
      pool: bigPool,
      providerId: 1,
      bindingToken: utf8.encode('tok'),
      epoch: 2,
    );
    final compressed = ZstdCodec(level: 3).compress(fatPlain);
    expect(compressed.length, lessThan(fatPlain.length));

    final envelope = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(1))
      ..add(_uvarint(15))
      ..add(_uvarint(SushiAssignment.flagCompressed))
      ..add(compressed);
    final reply = '!${base64Url.encode(envelope.toBytes()).replaceAll('=', '')}';

    final a = sushiParseInitbotReply(reply);
    expect(a.pending, isFalse);
    expect(a.apiBotUsername, 'compressedBot');
    expect(a.pool.length, 40);
    expect(a.providerId, 1);
    expect(a.epoch, 2);
  });
}

List<int> _uvarint(int n) {
  final out = <int>[];
  var x = n;
  while (x >= 0x80) {
    out.add((x & 0x7f) | 0x80);
    x >>= 7;
  }
  out.add(x);
  return out;
}

String _pad(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s.padRight(s.length + (4 - mod), '=');
}
