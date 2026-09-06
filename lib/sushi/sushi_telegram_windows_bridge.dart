import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fladder/sushi/sushi_telegram_stream_cb.dart';
import 'package:fladder/sushi/sushi_telegram_windows_ffi.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Windows gotd host implementing the same surface as Android Pigeon [SushiTdlibBridgeApi].
class SushiTelegramWindowsBridge {
  SushiTelegramWindowsBridge({void Function(SushiTdlibAuthState state)? onAuthStateChanged})
      : _onAuthStateChanged = onAuthStateChanged;

  final void Function(SushiTdlibAuthState state)? _onAuthStateChanged;
  final _native = SushiTelegramNative.instance();

  NativeCallable<SushiAuthSinkNative>? _sinkCallable;
  SushiTdlibAuthState _state = SushiTdlibAuthState(kind: SushiTdlibAuthStateKind.uninitialized);
  bool _configured = false;

  SushiTdlibAuthState get state => _state;

  /// True when a previous gotd login left `session.bin` on disk. Splash uses this instead of
  /// [configure] so a missing/legacy OX account does not block the UI isolate on Telegram DCs.
  Future<bool> hasPersistedSessionFile() async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File('${support.path}\\oxtelegram\\session.bin');
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> configure(int apiId, String apiHash) async {
    if (_configured) return;
    final support = await getApplicationSupportDirectory();
    final sessionPath = '${support.path}\\oxtelegram\\session.bin';
    final cachePath = '${support.path}\\oxtelegram\\cache';
    await Directory('${support.path}\\oxtelegram').create(recursive: true);

    _sinkCallable?.close();
    _sinkCallable = NativeCallable<SushiAuthSinkNative>.listener(_handleAuthSink);

    final hashPtr = apiHash.toNativeUtf8();
    final sessPtr = sessionPath.toNativeUtf8();
    final cachePtr = cachePath.toNativeUtf8();
    try {
      final rc = _native.configure(
        apiId,
        hashPtr,
        sessPtr,
        cachePtr,
        _sinkCallable!.nativeFunction,
      );
      _native.throwIfFailed(rc);
      _configured = true;
      _state = currentAuthState();
      _onAuthStateChanged?.call(_state);
    } finally {
      malloc.free(hashPtr);
      malloc.free(sessPtr);
      malloc.free(cachePtr);
    }
  }

  void _handleAuthSink(
    Pointer<Utf8> kind,
    Pointer<Utf8> qr,
    Pointer<Utf8> hint,
    Pointer<Utf8> err,
  ) {
    // Native owns these CStrings for the duration of the callback only — copy immediately.
    final state = SushiTdlibAuthState(
      kind: _kindFromString(kind.toDartString()),
      qrLoginUrl: _emptyToNull(qr.toDartString()),
      passwordHint: _emptyToNull(hint.toDartString()),
      errorMessage: _emptyToNull(err.toDartString()),
    );
    _state = state;
    _onAuthStateChanged?.call(state);
  }

  static String? _emptyToNull(String s) => s.isEmpty ? null : s;

  static SushiTdlibAuthStateKind _kindFromString(String kind) {
    switch (kind) {
      case 'waitingForPhoneNumber':
        return SushiTdlibAuthStateKind.waitingForPhoneNumber;
      case 'waitingForCode':
        return SushiTdlibAuthStateKind.waitingForCode;
      case 'waitingForPassword':
        return SushiTdlibAuthStateKind.waitingForPassword;
      case 'waitingForQrConfirmation':
        return SushiTdlibAuthStateKind.waitingForQrConfirmation;
      case 'ready':
        return SushiTdlibAuthStateKind.ready;
      case 'loggingOut':
        return SushiTdlibAuthStateKind.loggingOut;
      case 'closed':
        return SushiTdlibAuthStateKind.closed;
      case 'failed':
        return SushiTdlibAuthStateKind.failed;
      case 'uninitialized':
      default:
        return SushiTdlibAuthStateKind.uninitialized;
    }
  }

  /// Always false on Windows: the cshared FFI boundary doesn't expose gotd's AuthController.IsBotMode
  /// (unlike the Android gomobile/Pigeon path — see mobile.Client.IsBotMode's doc). Desktop's
  /// reader-sync mismatch detection still falls back to the caller-tracked bot-token flag, same as
  /// before this fix; only Android had the confirmed silent-hang bug from a warm-restored bot session.
  bool isNativeSessionBot() => false;

  SushiTdlibAuthState currentAuthState() {
    final kind = _native.readCString(_native.currentAuthKind());
    final qr = _native.readCString(_native.currentAuthQr());
    final hint = _native.readCString(_native.currentAuthHint());
    final err = _native.readCString(_native.currentAuthError());
    _state = SushiTdlibAuthState(
      kind: _kindFromString(kind),
      qrLoginUrl: _emptyToNull(qr),
      passwordHint: _emptyToNull(hint),
      errorMessage: _emptyToNull(err),
    );
    return _state;
  }

  Future<void> submitPhoneNumber(String phone) async {
    final p = phone.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitPhone(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> submitBotToken(String token) async {
    final p = token.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitBotToken(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> submitCode(String code) async {
    final p = code.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitCode(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> submitTwoFactorPassword(String password) async {
    final p = password.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitPassword(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> requestQrLogin() async {
    _native.throwIfFailed(_native.requestQr());
  }

  Future<void> logOut() async {
    _native.throwIfFailed(_native.logout());
    _configured = false;
    _state = SushiTdlibAuthState(kind: SushiTdlibAuthStateKind.uninitialized);
  }

  Future<String> startPlaybackSession(SushiTdlibPlaybackSource source) async {
    // Windows: gotd direct-play via libmpv stream_cb — replaces the HTTP loopback bridge
    // entirely (see go/oxtelegram/cshared/stream_cb.go). ox_start_playback still runs the real
    // resolve/download/registration; only the URL handed to mpv changes from an HTTP loopback
    // URL to a gotdstream:// one, via ox_stream_uri_for_current_playback.
    final loc = source.locator.toNativeUtf8();
    try {
      final urlPtr = _native.startPlayback(source.providerBotId, source.messageId, loc);
      if (urlPtr == nullptr) {
        final msg = _native.readCString(_native.lastError());
        throw SushiTelegramNativeException(msg.isEmpty ? 'startPlayback failed' : msg);
      }
      // The HTTP loopback URL itself is unused now — still free the native CString it holds.
      _native.free(urlPtr);
      final streamUri = SushiTelegramStreamCb.currentStreamUri();
      if (streamUri == null) {
        final msg = _native.readCString(_native.lastError());
        throw SushiTelegramNativeException(
          msg.isEmpty ? 'stream_cb: no active playback session after startPlayback' : msg,
        );
      }
      return streamUri;
    } finally {
      malloc.free(loc);
    }
  }

  /// Resolves the delivery and records where it landed, without opening a download — warm-up.
  Future<void> warmDelivery(SushiTdlibPlaybackSource source) async {
    final loc = source.locator.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.warmDelivery(source.providerBotId, source.messageId, loc));
    } finally {
      malloc.free(loc);
    }
  }

  /// Registers interest in [locator] before PlaybackInfo triggers the copy.
  void armDeliveryWaiter(String locator) {
    final p = locator.toNativeUtf8();
    try {
      _native.armDeliveryWaiter(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Starts, mutes and archives every delivery sender so copies stay out of the user's inbox.
  Future<void> ensureProviderBotsReady(List<SushiTdlibProviderBot> bots) async {
    final payload = jsonEncode([
      for (final bot in bots) {'id': bot.id, 'username': bot.username},
    ]).toNativeUtf8();
    try {
      _native.throwIfFailed(_native.ensureProviderBotsReady(payload));
    } finally {
      malloc.free(payload);
    }
  }

  /// Where this session read [locator], or null if it has read nothing. See
  /// SushiTelegramDeliveryApi for what Dart does with it.
  SushiTdlibDeliveryRef? deliveryRefForLocator(String locator) {
    final p = locator.toNativeUtf8();
    try {
      final messageId = _native.deliveryMessageIdForLocator(p);
      if (messageId <= 0) return null;
      return SushiTdlibDeliveryRef(
        messageId: messageId,
        providerBotId: _native.deliveryProviderBotIdForLocator(p),
      );
    } finally {
      malloc.free(p);
    }
  }

  Future<void> stopPlaybackSession(String sessionUri) async {
    final p = sessionUri.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.stopPlayback(p));
      // Keep Telegram client configured — stop only ends the progressive download.
    } finally {
      malloc.free(p);
    }
  }

  Future<String> fetchWebAppInitData(
    String botUsername,
    String? webAppShortName,
    String? hostedHttpsUrl,
  ) async {
    final bot = botUsername.toNativeUtf8();
    final short = (webAppShortName ?? '').toNativeUtf8();
    final hosted = (hostedHttpsUrl ?? '').toNativeUtf8();
    final platform = 'other'.toNativeUtf8();
    try {
      final ptr = _native.fetchWebApp(bot, short, hosted, platform);
      if (ptr == nullptr) {
        final msg = _native.readCString(_native.lastError());
        throw SushiTelegramNativeException(msg.isEmpty ? 'fetchWebAppInitData failed' : msg);
      }
      return _native.readCString(ptr);
    } finally {
      malloc.free(bot);
      malloc.free(short);
      malloc.free(hosted);
      malloc.free(platform);
    }
  }

  Future<String> sendTextAndWaitReply(String username, String text, int timeoutMs) async {
    final u = username.toNativeUtf8();
    final t = text.toNativeUtf8();
    try {
      final ptr = _native.sendTextAndWaitReply(u, t, timeoutMs);
      if (ptr == nullptr) {
        final msg = _native.readCString(_native.lastError());
        throw SushiTelegramNativeException(msg.isEmpty ? 'sendTextAndWaitReply failed' : msg);
      }
      return _native.readCString(ptr);
    } finally {
      malloc.free(u);
      malloc.free(t);
    }
  }
}

/// True when Windows oxtelegram.dll host should be used instead of Android Pigeon.
bool oxTelegramUseWindowsHost() => !kIsWeb && Platform.isWindows;
