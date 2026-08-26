/// Master switch for Sushi-specific behavior (Telegram-native, no HTTP API).
///
/// Hardcoded on — this fork is always Sushi. Handles baked in per R-SEC-6 / ADR 0004.
abstract final class SushiConfig {
  static const bool isEnabled = true;

  /// Public main-bot handle (no @). User-facing; baked into the build.
  static const String mainBotUsername = 'sushiMovieBot';

  /// Init-bot handle (no @). Machine handshake only (`/initbot`).
  static const String initBotUsername = 'OXStreamer29bot';
}
