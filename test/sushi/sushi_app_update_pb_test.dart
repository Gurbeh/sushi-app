import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_app_update_transport.dart';
import 'package:fladder/sushi/sushi_semver.dart';
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

void main() {
  test('sushiEncodeAppUpdateReq writes platform', () {
    final bytes = sushiEncodeAppUpdateReq(platform: 'android_tv');
    expect(bytes.first, 0x0a);
    final decoded = utf8.decode(bytes.sublist(2));
    expect(decoded, 'android_tv');
  });

  test('SushiAppUpdateRes decodes all fields including a Telegram-sized bot id', () {
    final out = BytesBuilder();
    out.add(_varintField(1, 8271796073));
    out.add(_varintField(2, 88));
    out.add(_lenDelim(3, utf8.encode('1.2.0')));
    out.add(_lenDelim(4, utf8.encode('sushi.apk')));
    out.add(_lenDelim(5, utf8.encode('app_android_new')));
    final res = SushiAppUpdateRes.decode(out.toBytes());
    expect(res.botId, 8271796073);
    expect(res.messageId, 88);
    expect(res.version, '1.2.0');
    expect(res.fileName, 'sushi.apk');
    expect(res.locator, 'app_android_new');
  });

  test('appupdate request line is a command with corr and args', () {
    final text = sushiEncodeRequestText(
      'appupdate',
      'a',
      sushiEncodeAppUpdateReq(platform: 'windows'),
    );
    expect(text, startsWith('/appupdate a '));
  });

  test('sushiMsgTypeAppUpdateRes matches protocol.proto', () {
    expect(sushiMsgTypeAppUpdateRes, 31);
  });

  test('sushiIsNewerApp compares semver and ignores nightly suffix', () {
    expect(sushiIsNewerApp('1.1.150', '1.2.0'), isTrue);
    expect(sushiIsNewerApp('1.2.0', '1.2.0'), isFalse);
    expect(sushiIsNewerApp('1.2.0-nightly', '1.2.0'), isFalse);
    expect(SushiSemver.parse('1.1.150-nightly')?.patch, 150);
  });

  test('sushiNoteLatestApp ignores empty and keeps the last real one', () {
    sushiLatestApp.value = null;
    sushiNoteLatestApp(null);
    expect(sushiLatestApp.value, isNull);
    sushiNoteLatestApp(const SushiLatestApp(platform: 'windows', version: '2.0.0'));
    expect(sushiLatestApp.value?.version, '2.0.0');
    sushiNoteLatestApp(const SushiLatestApp(platform: 'windows', version: ''));
    expect(sushiLatestApp.value?.version, '2.0.0');
  });

  test('sushiAppUpdateLocator matches server caption', () {
    expect(sushiAppUpdateLocator('android_new'), 'app_android_new');
    expect(sushiAppUpdateLocator('android_tv'), 'app_android_tv');
  });

  test('sushiAppUpdateColdSource ignores sender-side copyMessage id', () {
    final src = sushiAppUpdateColdSource('app_android_new');
    expect(src.providerBotId, 0);
    expect(src.messageId, 0);
    expect(src.locator, 'app_android_new');
    expect(src.preferHttpBridge, isTrue);
  });
}
