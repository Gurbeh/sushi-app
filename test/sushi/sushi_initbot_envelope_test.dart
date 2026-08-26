import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';

void main() {
  test('sushiParseInitbotReply reads ASSIGNMENT type 15', () {
    // ver=1, corr=1, type=15, flags=0, payload=hello
    final bytes = BytesBuilder()
      ..addByte(1)
      ..add(_uvarint(1))
      ..add(_uvarint(15))
      ..add(_uvarint(0))
      ..add(utf8.encode('hello'));
    final reply = '!${base64Url.encode(bytes.toBytes()).replaceAll('=', '')}';
    final a = sushiParseInitbotReply(reply);
    expect(a.msgType, SushiAssignment.msgTypeAssignment);
    expect(a.pending, isFalse);
    expect(a.isError, isFalse);
    expect(utf8.decode(base64Url.decode(_pad(a.payloadBase64))), 'hello');
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
