import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_http.dart';
import 'package:fladder/sushi/sushi_login_seal.dart';
import 'package:http/http.dart' as http;

/// Public preview the app polls while focused (ADR 0013).
Uri sushiLoginChannelUri() =>
    Uri.https('t.me', '/s/${SushiConfig.loginChannelUsername}');

/// GET the preview and try to open each `s2.` blob with [nonce].
Future<String?> sushiPollLoginChannel(http.Client client, List<int> nonce) async {
  final uri = sushiLoginChannelUri();
  if (!sushiHttpUriAllowed(uri)) {
    throw StateError('login channel host is not on the allowlist');
  }
  final res = await client.get(uri, headers: {'User-Agent': kSushiHttpUserAgent});
  if (res.statusCode != 200) return null;
  for (final blob in sushiExtractLoginBlobs(res.body)) {
    final token = await sushiOpenLoginBlob(blob, nonce);
    if (token != null) return token;
  }
  return null;
}
