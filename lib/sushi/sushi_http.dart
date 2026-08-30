import 'package:fladder/sushi/sushi_config.dart';

/// Neutral UA — must not name Sushi (doc 07 §8).
const kSushiHttpUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

/// R-SEC-12 / ADR 0013: posters on TMDB, bot-login preview on t.me only.
bool sushiHttpUriAllowed(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (uri.host == 'image.tmdb.org') return true;
  if (uri.host == 't.me' && uri.path == '/s/${SushiConfig.loginChannelUsername}') {
    return true;
  }
  return false;
}
