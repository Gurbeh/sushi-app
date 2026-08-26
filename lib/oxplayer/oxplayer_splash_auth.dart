import 'dart:io';

import 'dart:io';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_local_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OxplayerSplashAuthResult {
  /// No stored account or session tokens are invalid.
  needsLogin,

  /// Session restored; open the app shell.
  sessionReady,

  /// Session restored; show lock screen (biometric / PIN) before use.
  sessionWithLock,
}

bool _oxTdlibSessionGateSupported() {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isWindows;
  } catch (_) {
    return false;
  }
}

/// OX cold-start: restore API session for any saved account, then decide lock vs home.
///
/// When this build has TDLib credentials, also require a **ready** Telegram user-session
/// on device. Legacy OX logins (bot deep-link) without MTProto are signed out so the user
/// re-authenticates via Telegram. Users who already completed Telegram sign-in stay signed in.
Future<OxplayerSplashAuthResult> oxplayerResolveSplashAuth(
  WidgetRef ref,
  AccountModel account,
) async {
  try {
    // Sushi: no HTTP session. Local stub account + optional TDLib readiness is enough.
    if (SushiConfig.isEnabled && sushiIsLocalAccount(account)) {
      final assignment = await SushiAssignmentStore.load();
      if (assignment == null) {
        return OxplayerSplashAuthResult.needsLogin;
      }
      if (account.askForAuthOnLaunch && account.authMethod.shouldLock) {
        return OxplayerSplashAuthResult.sessionWithLock;
      }
      return OxplayerSplashAuthResult.sessionReady;
    }

    final sessionOk = await oxplayerRestoreSession(ref, account);
    if (!sessionOk) {
      await oxplayerLogoutLocallySkippingServer(ref.read, fallbackAccount: account);
      return OxplayerSplashAuthResult.needsLogin;
    }

    if (OxplayerEnv.telegramDirectPlayConfigured && _oxTdlibSessionGateSupported()) {
      final hasTelegramSession =
          await OxplayerTdlibBridgeController.instance().hasReadyUserSession();
      if (!hasTelegramSession) {
        // Keep OX tokens. `adb install -r` / TV Keystore often leaves TDLib in
        // WAITING_FOR_QR; wiping here forced QR login after every rebuild.
        debugPrint('OX_IMAGE phase=splash_tdlib_not_ready keep_ox_session=true');
        return OxplayerSplashAuthResult.sessionReady;
      }
    }

    if (account.askForAuthOnLaunch && account.authMethod.shouldLock) {
      return OxplayerSplashAuthResult.sessionWithLock;
    }
    return OxplayerSplashAuthResult.sessionReady;
  } catch (_) {
    try {
      await oxplayerLogoutLocallySkippingServer(ref.read, fallbackAccount: account);
    } catch (_) {}
    return OxplayerSplashAuthResult.needsLogin;
  }
}
