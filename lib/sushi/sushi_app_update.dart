import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/oxplayer/services/ox_update_service.dart';
import 'package:fladder/oxplayer/widgets/ox_dialog_focus_trap.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_app_update_transport.dart';

export 'package:fladder/sushi/sushi_app_update_pb.dart' show SushiLatestApp;
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

const _kSkippedVersionKey = 'sushi_skipped_app_version';

/// Latest shelf version from HomeRes. Null until the first home answer that carried one.
final ValueNotifier<SushiLatestApp?> sushiLatestApp = ValueNotifier<SushiLatestApp?>(null);

SharedPreferences? _updatePrefs;
String _updateCurrentVersion = '';

/// Called once from bootstrap so the prompt host can skip/compare without a Riverpod read.
void sushiBindUpdatePrompt(SharedPreferences prefs, String currentVersion) {
  _updatePrefs = prefs;
  _updateCurrentVersion = currentVersion;
}

/// Called from the home transport whenever a HomeRes includes latest_app (ADR 0019).
void sushiNoteLatestApp(SushiLatestApp? latest) {
  if (latest == null || latest.version.isEmpty) return;
  sushiLatestApp.value = latest;
}

bool sushiIsNewerApp(String currentVersion, String latestVersion) {
  final current = OxSemver.parse(currentVersion) ?? const OxSemver(major: 0, minor: 0, patch: 0);
  final latest = OxSemver.parse(latestVersion);
  return latest != null && latest.isNewerThan(current);
}

Future<bool> sushiShouldOfferUpdate({
  required String currentVersion,
  required SharedPreferences prefs,
}) async {
  final latest = sushiLatestApp.value;
  if (latest == null || !sushiIsNewerApp(currentVersion, latest.version)) return false;
  return prefs.getString(_kSkippedVersionKey) != latest.version;
}

Future<void> sushiSkipAppVersion(SharedPreferences prefs, String version) {
  return prefs.setString(_kSkippedVersionKey, version);
}

/// Copies the shelf file into the protocol chat, pulls it over MTProto, installs.
Future<void> sushiInstallLatestApp({
  required void Function(double? progress) onProgress,
}) async {
  final res = await sushiFetchAppUpdate();
  if (res == null || res.messageId == 0) {
    throw StateError('appupdate: no file');
  }
  await sushiArmDeliveryWaiter(res.locator);
  final url = await sushiStartPlaybackSession(OxTdlibPlaybackSource(
    providerBotId: res.botId,
    messageId: res.messageId,
    preferHttpBridge: true,
    locator: res.locator,
  ));
  try {
    final file = await _downloadLocalhost(url, res.fileName, onProgress);
    onProgress(1);
    await _installFile(file);
  } finally {
    await sushiStopPlaybackSession(url);
  }
}

Future<File> _downloadLocalhost(
  String url,
  String fileName,
  void Function(double? progress) onProgress,
) async {
  final uri = Uri.parse(url);
  if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
    throw StateError('appupdate: expected localhost bridge, got ${uri.host}');
  }
  final dir = await getTemporaryDirectory();
  final safe = fileName.isEmpty ? 'sushi_update' : fileName.replaceAll(RegExp(r'[/\\]'), '_');
  final out = File('${dir.path}/$safe');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final resp = await req.close();
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw StateError('appupdate: download HTTP ${resp.statusCode}');
    }
    final sink = out.openWrite();
    final total = resp.contentLength;
    var got = 0;
    await for (final chunk in resp) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    return out;
  } finally {
    client.close(force: true);
  }
}

Future<void> _installFile(File file) async {
  if (Platform.isAndroid) {
    final opened = await FileDownloader().openFile(
      filePath: file.path,
      mimeType: 'application/vnd.android.package-archive',
    );
    if (!opened) {
      throw StateError('Could not launch the Android package installer');
    }
    return;
  }
  if (Platform.isWindows) {
    await Process.start(
      file.path,
      const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    await windowManager.close();
    return;
  }
  throw StateError('in-app install is not supported on this platform');
}

Future<void> sushiOpenMainBotDownload() async {
  final uri = Uri.parse('tg://resolve?domain=${SushiConfig.mainBotUsername}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await launchUrl(
      Uri.parse(SushiConfig.mainBotAppCodeUrl('')),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// EN + FA copy for the update surfaces (R-I18N-1).
class SushiUpdateCopy {
  const SushiUpdateCopy(this._fa);

  factory SushiUpdateCopy.of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return SushiUpdateCopy(code.toLowerCase().startsWith('fa'));
  }

  final bool _fa;

  String get bannerTitle => _fa ? 'نسخه جدید سوشی' : 'New Sushi version';
  String bannerSub(String version) =>
      _fa ? 'سوشی $version آماده‌ست. از همین‌جا نصبش کن.' : 'Sushi $version is ready. Install it here.';
  String get dialogTitle => _fa ? 'نسخه جدید' : 'Update available';
  String dialogBody(String current, String latest) => _fa
      ? 'الان $current داری. $latest بهتره. دانلود و نصب از تلگرام، بدون سایت.'
      : 'You have $current. $latest is newer. Download and install through Telegram — no website.';
  String get install => _fa ? 'دانلود و نصب' : 'Download and install';
  String get skip => _fa ? 'فعلا نه' : 'Not now';
  String get later => _fa ? 'بعدا' : 'Later';
  String get downloading => _fa ? 'داره میاد…' : 'Downloading…';
  String get installing => _fa ? 'داره نصب میشه…' : 'Installing…';
  String get failed => _fa ? 'دانلود نشد. از ربات بگیر.' : 'Download failed. Get it from the bot.';
  String get openBot => _fa ? 'باز کردن ربات' : 'Open bot';
}

Future<void> sushiShowUpdateDialog({
  required BuildContext context,
  required String currentVersion,
  required SharedPreferences prefs,
}) async {
  final latest = sushiLatestApp.value;
  if (latest == null || !context.mounted) return;
  final copy = SushiUpdateCopy.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => OxDialogFocusTrap(
      child: _SushiUpdateDialog(
        copy: copy,
        currentVersion: currentVersion,
        latestVersion: latest.version,
        prefs: prefs,
      ),
    ),
  );
}

class _SushiUpdateDialog extends StatefulWidget {
  const _SushiUpdateDialog({
    required this.copy,
    required this.currentVersion,
    required this.latestVersion,
    required this.prefs,
  });

  final SushiUpdateCopy copy;
  final String currentVersion;
  final String latestVersion;
  final SharedPreferences prefs;

  @override
  State<_SushiUpdateDialog> createState() => _SushiUpdateDialogState();
}

enum _Phase { ask, downloading, installing, error }

class _SushiUpdateDialogState extends State<_SushiUpdateDialog> {
  _Phase _phase = _Phase.ask;
  double? _progress;

  Future<void> _install() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
    });
    try {
      await sushiInstallLatestApp(onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          if (p != null && p >= 1) _phase = _Phase.installing;
        });
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('[sushi] update install failed: $e\n$st');
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    if (_phase == _Phase.ask) {
      return AlertDialog(
        title: Text(copy.dialogTitle),
        content: Text(copy.dialogBody(widget.currentVersion, widget.latestVersion)),
        actions: [
          TextButton(
            onPressed: () async {
              await sushiSkipAppVersion(widget.prefs, widget.latestVersion);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(copy.skip),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(copy.later),
          ),
          FilledButton(onPressed: _install, child: Text(copy.install)),
        ],
      );
    }
    if (_phase == _Phase.error) {
      return AlertDialog(
        title: Text(copy.failed),
        actions: [
          TextButton(
            onPressed: () async {
              await sushiOpenMainBotDownload();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(copy.openBot),
          ),
          FilledButton(onPressed: _install, child: Text(copy.install)),
        ],
      );
    }
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(_phase == _Phase.installing ? copy.installing : copy.downloading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: _progress),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              Text('${((_progress ?? 0) * 100).round()}%'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps the app so a newer HomeRes can prompt once past first frame.
class SushiUpdatePromptHost extends StatefulWidget {
  const SushiUpdatePromptHost({required this.child, super.key});

  final Widget child;

  @override
  State<SushiUpdatePromptHost> createState() => _SushiUpdatePromptHostState();
}

class _SushiUpdatePromptHostState extends State<SushiUpdatePromptHost> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    sushiLatestApp.addListener(_maybeShow);
  }

  @override
  void dispose() {
    sushiLatestApp.removeListener(_maybeShow);
    super.dispose();
  }

  Future<void> _maybeShow() async {
    if (_shown || !mounted) return;
    final prefs = _updatePrefs;
    if (prefs == null || _updateCurrentVersion.isEmpty) return;
    if (!await sushiShouldOfferUpdate(currentVersion: _updateCurrentVersion, prefs: prefs)) {
      return;
    }
    _shown = true;
    if (!mounted) return;
    await sushiShowUpdateDialog(
      context: context,
      currentVersion: _updateCurrentVersion,
      prefs: prefs,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
