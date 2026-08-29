import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_delivery_reader_sync.dart';
import 'package:fladder/oxplayer/oxplayer_dpad_text_field.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart';
import 'package:fladder/oxplayer/oxplayer_main_bot_login_api.dart';
import 'package:fladder/oxplayer/oxplayer_ox_login_kind_store.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_connecting_experience.dart';
import 'package:fladder/sushi/sushi_bot_login_code.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_local_account.dart';
import 'package:fladder/theme.dart';

/// Sign-in without a personal Telegram user session.
///
/// OXPlayer: approve a login-attempt in @main-bot, poll `/auth/login-attempt`.
/// Sushi: open main-bot (`?start=ac_<nonce>`). BotFather walkthrough is ForceReply in Telegram;
/// then a monospace `s1.` code — paste that here, never the raw token.
class OxplayerMainBotLoginPanel extends ConsumerStatefulWidget {
  const OxplayerMainBotLoginPanel(
      {required this.onSuccess, this.onBack, super.key});

  final Future<void> Function() onSuccess;
  final VoidCallback? onBack;

  @override
  ConsumerState<OxplayerMainBotLoginPanel> createState() =>
      _OxplayerMainBotLoginPanelState();
}

class _OxplayerMainBotLoginPanelState
    extends ConsumerState<OxplayerMainBotLoginPanel> {
  final _api = OxplayerMainBotLoginApi();
  final _tokenController = TextEditingController();
  OxplayerLoginAttemptStart? _attempt;
  String? _error;
  bool _starting = !SushiConfig.isEnabled;
  bool _finishing = false;
  int _pollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tokenController.addListener(_onSushiCodeChanged);
    if (!SushiConfig.isEnabled) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _pollGeneration++;
    _tokenController.removeListener(_onSushiCodeChanged);
    _tokenController.dispose();
    super.dispose();
  }

  void _onSushiCodeChanged() {
    if (!SushiConfig.isEnabled || _finishing) return;
    final token = sushiTryParseBotLoginCode(_tokenController.text);
    if (token == null) return;
    unawaited(_submitSushiBotToken(token));
  }

  Future<void> _pasteSushiCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      final fa = Localizations.localeOf(context).languageCode == 'fa';
      setState(() => _error = fa ? 'کلیپ‌بورد خالیه' : 'Clipboard is empty');
      return;
    }
    _tokenController.text = text;
    if (sushiTryParseBotLoginCode(text) == null) {
      final fa = Localizations.localeOf(context).languageCode == 'fa';
      setState(() => _error = fa
          ? 'این کد اپ نیست. کادر تلگرام رو کپی کن، نه توکن BotFather.'
          : 'That is not an app code. Copy the boxed code from Telegram, not the BotFather token.');
    }
  }

  String _sushiInitbotNotReady(SushiAssignment assignment) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final blob = assignment.rawReply.toLowerCase();
    if (blob.contains('user_is_bot') ||
        blob.contains("can't send messages to other bots")) {
      return fa
          ? 'باتت هنوز نمی‌تونه به بات سوشی پیام بده. تو @BotFather روی همون بات، Bot to Bot Communication Mode رو روشن کن، بعد از تلگرام کد جدید بگیر.'
          : 'Your bot cannot message Sushi bots yet. In @BotFather, turn on Bot to Bot Communication Mode for that bot, then copy a fresh code from Telegram.';
    }
    return fa
        ? 'هنوز آماده نیست. تو تلگرام راهنما رو تموم کن، کد رو کپی کن، دوباره بچسبون.'
        : 'Not ready yet. Finish setup in Telegram, copy the code, then try again.';
  }

  Future<void> _submitSushiBotToken(String token) async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      await OxplayerTdlibBridgeController.instance()
          .ensureBotTokenSession(token);
      final assignment = await sushiRunInitbotAfterTdlibReady();
      if (assignment.pending || assignment.apiSendTargets.isEmpty) {
        throw StateError(_sushiInitbotNotReady(assignment));
      }
      final account = await sushiEnsureLocalAccount(ref);
      await OxplayerOxLoginKindStore.save(
          accountId: account.id, kind: OxplayerOxLoginKind.bot);
      await widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        if (e is StateError) {
          _error = e.message;
        } else if (e is OxplayerLoginAttemptException) {
          _error = e.message;
        } else {
          _error = oxTdlibAuthUserMessage(e);
        }
      });
    }
  }

  Future<void> _openMainBotForAppCode() async {
    await OxplayerDotenv.ensureLoaded();
    await launchUrl(Uri.parse(SushiConfig.mainBotAppCodeUrl()),
        mode: LaunchMode.externalApplication);
  }

  /// [silent]: background auto-refresh (see _pollLoop) — swap in a fresh code/QR without
  /// flashing the full loading spinner, same idea as a QR code that quietly rotates itself.
  Future<void> _start({bool silent = false}) async {
    setState(() {
      _starting = !silent;
      _error = null;
    });
    final generation = ++_pollGeneration;
    try {
      final identity =
          await OxplayerTdlibBridgeController.resolveDeviceIdentity();
      final attempt = await _api.createAttempt(deviceId: identity);
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _attempt = attempt;
        _starting = false;
      });
      unawaited(_pollLoop(attempt, identity, generation));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _attempt = null;
        _error = e is OxplayerLoginAttemptException
            ? e.message
            : 'Could not start sign-in';
      });
    }
  }

  /// Refresh this far ahead of expiry — comfortably longer than one poll()'s ~55s server-side
  /// long-poll cycle, so a refresh is never raced by a call that was already in flight.
  static const _refreshMargin = Duration(seconds: 75);

  Future<void> _pollLoop(OxplayerLoginAttemptStart attempt, String deviceId,
      int generation) async {
    final deadline = DateTime.now().add(Duration(seconds: attempt.expiresIn));
    var consecutiveFailures = 0;
    while (mounted && generation == _pollGeneration) {
      if (deadline.difference(DateTime.now()) <= _refreshMargin) {
        unawaited(_start(silent: true));
        return;
      }
      try {
        final result =
            await _api.poll(attemptId: attempt.attemptId, deviceId: deviceId);
        if (!mounted || generation != _pollGeneration) return;
        consecutiveFailures = 0;
        if (result.isPending) continue;
        await _finish(result);
        return;
      } catch (e) {
        if (!mounted || generation != _pollGeneration) return;
        consecutiveFailures++;
        if (consecutiveFailures <= 6) {
          await Future<void>.delayed(
              Duration(seconds: consecutiveFailures.clamp(1, 5)));
          continue;
        }
        unawaited(_start(silent: true));
        return;
      }
    }
  }

  Future<void> _finish(OxplayerLoginAttemptPollResult result) async {
    setState(() => _finishing = true);
    try {
      final response = await oxplayerAuthenticateFromLoginAttemptPoll(
        ref,
        result,
        loginKind: OxplayerOxLoginKind.bot,
      );
      final account = response?.body;
      if (account == null) {
        throw StateError('Sign-in did not complete');
      }
      await _applyBotTokenIfConnected(account.credentials.token);
      await widget.onSuccess();
    } catch (e) {
      if (mounted) {
        setState(() => _finishing = false);
        unawaited(_start());
      }
    }
  }

  /// Best-effort — playback (not sign-in) is what actually needs this, and it re-checks with a
  /// clear in-app message if the user hasn't finished /connectbot yet.
  Future<void> _applyBotTokenIfConnected(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      await oxplayerEnsureTdlibMatchesOxUser(accessToken);
    } catch (_) {}
  }

  Future<void> _openBot() async {
    final id = _attempt?.attemptId;
    if (id == null) return;
    final link = OxplayerEnv.telegramBotLoginAttemptLink(id);
    if (link == null) return;
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_finishing || _starting) {
      return const OxplayerTdlibConnectingExperience();
    }

    if (SushiConfig.isEnabled) {
      return _buildSushi(theme);
    }
    return _buildOx(theme);
  }

  static const _sushiSalmon = Color(0xFFE37A42);

  ButtonStyle get _sushiFill => FilledButton.styleFrom(
        backgroundColor: _sushiSalmon,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _sushiSalmon.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size.fromHeight(52),
      );

  Widget _buildSushi(ThemeData theme) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fa ? 'ورود با بات خودت' : 'Sign in with a bot you own',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _sushiStep(
            theme,
            fa ? '۱' : '1',
            fa
                ? 'دکمهٔ نارنجی رو بزن تا تلگرام باز بشه.'
                : 'Tap the salmon button to open Telegram.'),
        _sushiStep(
            theme,
            fa ? '۲' : '2',
            fa
                ? 'تو BotFather بات بساز، Bot-to-Bot رو روشن کن، توکن رو همون‌جا ریپلای کن — تو اپ نچسبون.'
                : 'In BotFather: create a bot, turn on Bot-to-Bot, reply with the token there — never paste it in the app.'),
        _sushiStep(
            theme,
            fa ? '۳' : '3',
            fa
                ? 'کادر کد (s1.) رو کپی کن و اینجا بچسبون. اپ خودش وارد می‌شه.'
                : 'Copy the boxed code (s1.) and paste it here. Sushi signs in on a valid code.'),
        const SizedBox(height: 20),
        FilledButton.icon(
          autofocus: true,
          style: _sushiFill,
          onPressed: () => unawaited(_openMainBotForAppCode()),
          icon: const Icon(IconsaxPlusLinear.send_2),
          label: Text(fa ? 'باز کردن تلگرام' : 'Open Telegram'),
        ),
        const SizedBox(height: 16),
        OxplayerDpadTextField(
          controller: _tokenController,
          label: fa ? 'کد اپ' : 'App code',
          hint: 's1.…',
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: _sushiFill,
          onPressed: () => unawaited(_pasteSushiCode()),
          icon: const Icon(IconsaxPlusLinear.copy),
          label: Text(fa ? 'چسباندن کد' : 'Paste code'),
        ),
        if (widget.onBack != null) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(IconsaxPlusLinear.arrow_left_2, size: 18),
            label: Text(fa
                ? 'با اکانت تلگرام وارد شو'
                : 'Use my Telegram account instead'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: muted?.copyWith(color: theme.colorScheme.error) ??
                TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _sushiStep(ThemeData theme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: _sushiSalmon, shape: BoxShape.circle),
            child: Text(
              n,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOx(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in with @${OxplayerEnv.botUsername ?? "main-bot"}',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          "Approve sign-in in Telegram — OXPlayer never sees your Telegram account.",
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_attempt != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: OxplayerEnv.telegramBotLoginAttemptLink(
                        _attempt!.attemptId) ??
                    '',
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            autofocus: true,
            style: FilledButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _openBot,
            icon: const Icon(IconsaxPlusLinear.send_2),
            label: const Text('Open Telegram to approve'),
          ),
          const SizedBox(height: 14),
          Text(
            'Or type this code into @${OxplayerEnv.botUsername ?? "main-bot"} in Telegram:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          SelectableText(
            _attempt!.code,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: 6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (widget.onBack != null) ...[
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(IconsaxPlusLinear.arrow_left_2, size: 18),
            label: const Text('Use my Telegram account instead'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => unawaited(_start()), child: const Text('Retry')),
        ],
      ],
    );
  }
}
