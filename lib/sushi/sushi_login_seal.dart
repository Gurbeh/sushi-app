import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:fladder/sushi/sushi_bot_login_code.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Channel blob prefix (ADR 0013). Not the old copy-code `s1.`.
const kSushiLoginBlobPrefix = 's2.';

const kSushiLoginInfo = 'sushi-bot-login-v1';
const kSushiLoginNonceSize = 16;
const kSushiGcmNonceSize = 12;
const kSushiGcmTagSize = 16;

Uint8List sushiNewLoginNonce() {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(kSushiLoginNonceSize, (_) => r.nextInt(256)));
}

String sushiLoginStartPayload(Uint8List nonce) {
  if (nonce.length != kSushiLoginNonceSize) {
    throw ArgumentError('login nonce must be $kSushiLoginNonceSize bytes');
  }
  return 'ac_${base64Url.encode(nonce).replaceAll('=', '')}';
}

Future<List<int>> _deriveKey(List<int> nonce) async {
  final hash = await Sha256().hash([...utf8.encode(kSushiLoginInfo), ...nonce]);
  return hash.bytes;
}

/// Encrypts [token] the same way Go `botlogin.Seal` does.
Future<String> sushiSealLoginToken(String token, List<int> nonce, {List<int>? gcmNonce}) async {
  final t = token.trim();
  if (!sushiLooksLikeBotToken(t)) {
    throw const FormatException('not a bot token');
  }
  if (nonce.length != kSushiLoginNonceSize) {
    throw ArgumentError('login nonce must be $kSushiLoginNonceSize bytes');
  }
  final algorithm = AesGcm.with256bits();
  final iv = gcmNonce ?? algorithm.newNonce();
  if (iv.length != kSushiGcmNonceSize) {
    throw ArgumentError('gcm nonce must be $kSushiGcmNonceSize bytes');
  }
  final box = await algorithm.encrypt(
    utf8.encode(t),
    secretKey: SecretKey(await _deriveKey(nonce)),
    nonce: iv,
    aad: utf8.encode(kSushiLoginInfo),
  );
  final packed = Uint8List.fromList([...iv, ...box.cipherText, ...box.mac.bytes]);
  return kSushiLoginBlobPrefix + base64Url.encode(packed).replaceAll('=', '');
}

/// Returns the token if [blob] opens under [nonce]; otherwise null.
Future<String?> sushiOpenLoginBlob(String blob, List<int> nonce) async {
  final trimmed = blob.trim();
  if (!trimmed.startsWith(kSushiLoginBlobPrefix)) return null;
  if (nonce.length != kSushiLoginNonceSize) return null;
  final raw = trimmed.substring(kSushiLoginBlobPrefix.length);
  if (raw.isEmpty) return null;
  late final Uint8List packed;
  try {
    packed = base64Url.decode(sushiPadBase64Url(raw));
  } catch (_) {
    return null;
  }
  if (packed.length < kSushiGcmNonceSize + kSushiGcmTagSize) return null;
  final iv = packed.sublist(0, kSushiGcmNonceSize);
  final rest = packed.sublist(kSushiGcmNonceSize);
  final mac = rest.sublist(rest.length - kSushiGcmTagSize);
  final cipherText = rest.sublist(0, rest.length - kSushiGcmTagSize);
  try {
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(mac)),
      secretKey: SecretKey(await _deriveKey(nonce)),
      aad: utf8.encode(kSushiLoginInfo),
    );
    final token = utf8.decode(clear);
    if (!sushiLooksLikeBotToken(token)) return null;
    return token;
  } catch (_) {
    return null;
  }
}

/// Finds `s2.` payloads in a t.me/s HTML page.
List<String> sushiExtractLoginBlobs(String page) {
  const min = 4 + 20; // 's2.' + payload
  final out = <String>[];
  var i = 0;
  while (i < page.length) {
    final j = page.indexOf(kSushiLoginBlobPrefix, i);
    if (j < 0) return out;
    var k = j + kSushiLoginBlobPrefix.length;
    while (k < page.length) {
      final c = page.codeUnitAt(k);
      final ok = (c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122) ||
          (c >= 48 && c <= 57) ||
          c == 45 ||
          c == 95;
      if (!ok) break;
      k++;
    }
    if (k - j >= min) {
      out.add(page.substring(j, k));
    }
    i = k;
  }
  return out;
}
