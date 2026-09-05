/// Master switch for Sushi-specific behavior (Telegram-native, no HTTP API).
///
/// Hardcoded on — this fork is always Sushi. Handles baked in per R-SEC-6 / ADR 0004.
///
/// `production` flavor always uses the baked handle (`sushiMovieBot` unless `--dart-define`).
/// `development` reads `assets/env/default.env` (`OXPLAYER_BOT_USERNAME` from `npm run env:pull`).
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

abstract final class SushiConfig {
  static const bool isEnabled = true;

  static const String _bakedMain = String.fromEnvironment(
    'SUSHI_MAIN_BOT',
    defaultValue: 'sushiMovieBot',
  );
  static const String _bakedInit = String.fromEnvironment(
    'SUSHI_INIT_BOT',
    defaultValue: 'OXStreamer29bot',
  );
  static const String _flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  static String _handle(String raw) => raw.trim().replaceFirst(RegExp(r'^@'), '');

  /// Store / CI production APK must not follow a leftover local `default.env`.
  static bool get _allowEnvHandles => _flavor != 'production';

  /// Public main-bot handle (no @).
  static String get mainBotUsername {
    if (_allowEnvHandles) {
      final fromEnv = _handle(OxplayerDotenv.get('OXPLAYER_BOT_USERNAME'));
      if (fromEnv.isNotEmpty) return fromEnv;
    }
    return _handle(_bakedMain);
  }

  /// Init-bot handle (no @). Machine handshake only (`/initbot`).
  static String get initBotUsername {
    if (_allowEnvHandles) {
      final fromEnv = _handle(OxplayerDotenv.get('OXPLAYER_INIT_BOT_USERNAME'));
      if (fromEnv.isNotEmpty) return fromEnv;
    }
    return _handle(_bakedInit);
  }

  /// Public preview channel (ADR 0013). Same handle in every environment.
  static const String loginChannelUsername = 'SushiBotsConversation';

  /// Unique each tap so Telegram actually sends `/start ac_…` instead of opening a stale /start chat.
  static String mainBotAppCodeUrl(String startPayload) {
    return 'https://t.me/$mainBotUsername?start=$startPayload';
  }

  static const _bakedOpenSubtitlesKey = String.fromEnvironment('OPENSUBTITLES_API_KEY');

  /// Free OpenSubtitles **consumer** key (app, not a user login). Anonymous download quota is
  /// 5/day per IP. Empty skips that translate fallback.
  static String get openSubtitlesApiKey {
    if (_bakedOpenSubtitlesKey.trim().isNotEmpty) return _bakedOpenSubtitlesKey.trim();
    if (_allowEnvHandles) return OxplayerDotenv.get('OPENSUBTITLES_API_KEY').trim();
    return '';
  }
}
