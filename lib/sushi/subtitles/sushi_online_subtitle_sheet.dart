// PROTOTYPE — sushi/docs/15-subtitles.md §7. Automatic / Online subtitle picker backed by a
// direct client -> sub-plus.ir call. Production runs the list + ranking server-side. Do not ship.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/subtitles/sushi_subplus.dart';
import 'package:fladder/sushi/subtitles/sushi_subtitle_actions.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

void _log(String phase, [Map<String, Object?> fields = const {}]) =>
    OxplayerStreamLog.event('sushi_sub_$phase', fields: fields);

const _kAutomatic = 'Automatic (online)';
const _kOnline = 'Online subtitles…';
const _kTranslate = 'Translate with AI (Persian)';
const _kSearching = 'Searching sub-plus…';
const _kNoResults = 'No subtitles found';
const _kApplied = 'Subtitle loaded';
const _kFailed = 'Could not load subtitle';
const _kTranslateFailed = 'AI translate failed';
const _kTranslating = 'Translating to Persian…';
const _kTranslated = 'Persian subtitle applied';
const _kNoSource = 'Need a text subtitle first — try Online subtitles';
const _kAiKeyMissing =
    'AI translate needs a free Gemini API key. Set it in the Sushi bot.';
const _kSetApiKey = 'Set API key';
const _kRetry = 'Retry';

/// The rows prepended to the subtitle dialog. Empty when the feature is off.
///
/// Everything the async work needs is read from [ref] here, synchronously, because the calls
/// below pop the dialog first — after which this [ref] is disposed and unusable.
List<Widget> sushiSubtitleMenuRows(BuildContext context, WidgetRef ref) {
  if (!OxplayerConfig.isEnabled) return const [];
  final theme = Theme.of(context);
  final active = ref.watch(sushiActiveSubtitleProvider);
  final sel = theme.colorScheme.primary.withValues(alpha: 0.3);

  void closeTransientRoutes() {
    Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
  }

  return [
    ListTile(
      leading: const Icon(Icons.auto_awesome_rounded),
      title: Text(_kAutomatic, style: theme.textTheme.titleMedium),
      tileColor: active?.auto == true ? sel : null,
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        final container = ProviderScope.containerOf(context, listen: false);
        final navigator = Navigator.of(context, rootNavigator: true);
        closeTransientRoutes();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          sushiAutoLoadSubtitle(messenger: messenger, container: container, navigator: navigator);
        });
      },
    ),
    ListTile(
      leading: const Icon(Icons.travel_explore_rounded),
      title: Text(_kOnline, style: theme.textTheme.titleMedium),
      subtitle: active?.auto == false ? Text(active!.label, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      tileColor: active?.auto == false ? sel : null,
      onTap: () {
        final navigator = Navigator.of(context, rootNavigator: true);
        closeTransientRoutes();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showSushiOnlineSubtitles(navigator.context);
        });
      },
    ),
    ListTile(
      leading: const Icon(Icons.translate_rounded),
      title: Text(_kTranslate, style: theme.textTheme.titleMedium),
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        final container = ProviderScope.containerOf(context, listen: false);
        final navigator = Navigator.of(context, rootNavigator: true);
        closeTransientRoutes();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          sushiTranslateSubtitle(
            messenger: messenger,
            container: container,
            navigator: navigator,
          );
        });
      },
    ),
    const Divider(height: 1),
  ];
}

void _toast(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
  );
}

Future<void> _withBusyDialog({
  required NavigatorState navigator,
  required String message,
  required Future<void> Function() body,
}) async {
  final ctx = navigator.context;
  if (!ctx.mounted) {
    await body();
    return;
  }
  showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    await body();
  } finally {
    if (ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  }
}

/// Automatic: search by playing title, apply the episode's (or top pack's first) file silently.
Future<void> sushiAutoLoadSubtitle({
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
  NavigatorState? navigator,
  MediaControlsWrapper? player,
  String? title,
  String? year,
  SushiEpisodeRef? episode,
}) async {
  late final SushiSubtitleOpResult result;
  Future<void> run() async {
    result = await sushiRunAutoLoad(container);
  }

  final nav = navigator;
  if (nav != null && nav.context.mounted) {
    await _withBusyDialog(navigator: nav, message: _kSearching, body: run);
  } else {
    await run();
  }
  if (result.errorCode == 'busy') {
    _toast(messenger, 'Still loading subtitles…');
    return;
  }
  if (result.ok) {
    _toast(messenger, _kApplied);
  } else if (result.errorCode == 'no_results') {
    _toast(messenger, _kNoResults);
  } else {
    _toast(messenger, _kFailed);
  }
}

Future<void> sushiTranslateSubtitle({
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
  required NavigatorState navigator,
  bool forceKeyRefresh = false,
}) async {
  late final SushiSubtitleOpResult result;
  await _withBusyDialog(
    navigator: navigator,
    message: _kTranslating,
    body: () async {
      result = await sushiRunTranslateToPersian(container, forceKeyRefresh: forceKeyRefresh);
    },
  );
  if (result.errorCode == 'busy') {
    _toast(messenger, 'Still translating…');
    return;
  }
  if (result.ok) {
    _toast(messenger, _kTranslated);
    return;
  }
  if (result.errorCode == 'missing_key') {
    final ctx = navigator.context;
    if (ctx.mounted) {
      await showSushiAiKeyMissingDialog(ctx, messenger: messenger, container: container);
    }
    return;
  }
  if (result.errorCode == 'no_source') {
    _toast(messenger, _kNoSource);
    return;
  }
  _toast(messenger, _kTranslateFailed);
}

Future<void> showSushiAiKeyMissingDialog(
  BuildContext context, {
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
}) async {
  final setup = await sushiAiKeySetupInfo();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _AiKeyMissingDialog(
      setup: setup,
      onRetry: () async {
        Navigator.of(ctx, rootNavigator: true).pop();
        await sushiTranslateSubtitle(
          messenger: messenger,
          container: container,
          navigator: Navigator.of(context, rootNavigator: true),
          forceKeyRefresh: true,
        );
      },
    ),
  );
}

class _AiKeyMissingDialog extends StatefulWidget {
  const _AiKeyMissingDialog({required this.setup, required this.onRetry});

  final SushiAiKeySetupInfo setup;
  final VoidCallback onRetry;

  @override
  State<_AiKeyMissingDialog> createState() => _AiKeyMissingDialogState();
}

class _AiKeyMissingDialogState extends State<_AiKeyMissingDialog> {
  bool _showQr = false;

  Future<void> _openBot() async {
    final uri = Uri.parse(widget.setup.deepLink);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) setState(() => _showQr = true);
    } catch (_) {
      if (mounted) setState(() => _showQr = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
    final showQr = !setup.telegramInstalled || _showQr;
    return AlertDialog(
      title: const Text(_kTranslate),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(_kAiKeyMissing),
          const SizedBox(height: 16),
          if (showQr) ...[
            QrImageView(data: setup.deepLink, size: 220, backgroundColor: Colors.white),
            if (setup.telegramInstalled)
              TextButton(
                onPressed: () => setState(() => _showQr = false),
                child: const Text('Hide QR'),
              ),
          ] else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _openBot,
                    child: const Text(_kSetApiKey),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'QR',
                  onPressed: () => setState(() => _showQr = true),
                  icon: const Icon(Icons.qr_code_2),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onRetry, child: const Text(_kRetry)),
        TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Close')),
      ],
    );
  }
}

Future<void> showSushiOnlineSubtitles(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const _OnlineSubtitleDialog(),
  );
}

class _OnlineSubtitleDialog extends ConsumerStatefulWidget {
  const _OnlineSubtitleDialog();

  @override
  ConsumerState<_OnlineSubtitleDialog> createState() => _OnlineSubtitleDialogState();
}

class _OnlineSubtitleDialogState extends ConsumerState<_OnlineSubtitleDialog> {
  final _client = SushiSubplusClient();
  late final TextEditingController _query = TextEditingController(text: sushiPlayingTitle(ref) ?? '');
  late final String? _year = sushiPlayingYear(ref);
  late final SushiEpisodeRef? _episode = sushiPlayingEpisode(ref);

  bool _loading = false;
  String? _error;
  List<SubplusPack> _packs = const [];
  SubplusPack? _openPack;
  List<SubplusSubFile> _files = const [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _client.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _openPack = null;
      _files = const [];
    });
    try {
      _log('search_start', {'q': _query.text});
      final packs = await _client.search(_query.text);
      _log('search_done', {'packs': packs.length});
      if (!mounted) return;
      setState(() {
        _packs = rankSubplusPacks(packs, query: _query.text, year: _year, episode: _episode);
        _loading = false;
      });
    } catch (e, st) {
      _log('search_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
      if (!mounted) return;
      setState(() {
        _error = e is SubplusException ? e.message : _kFailed;
        _loading = false;
      });
    }
  }

  Future<void> _openPackFiles(SubplusPack pack) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _log('pack_open', {'tag': pack.tag, 'title': pack.title});
      final subs = await _client.fetchSubs(pack.tag);
      _log('pack_files', {'files': subs.length, 'names': subs.map((s) => s.name).take(4).join(', ')});
      if (!mounted) return;
      final ep = _episode;
      final epMatch = ep == null ? null : pickEpisodeFile(subs, ep.season, ep.episode);
      if (subs.length == 1) {
        await _apply(pack, subs.first);
        return;
      }
      if (epMatch != null) {
        // Season pack + we know the episode — apply it straight away.
        await _apply(pack, epMatch);
        return;
      }
      setState(() {
        _openPack = pack;
        _files = subs;
        _loading = false;
        if (subs.isEmpty) _error = _kNoResults;
      });
    } catch (e, st) {
      _log('pack_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
      if (!mounted) return;
      setState(() {
        _error = e is SubplusException ? e.message : _kFailed;
        _loading = false;
      });
    }
  }

  Future<void> _apply(SubplusPack pack, SubplusSubFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final player = ref.read(videoPlayerProvider);
    final head = file.text.replaceAll('\n', '⏎');
    _log('apply', {
      'file': file.name,
      'ext': file.ext,
      'chars': file.text.length,
      'head': head.length > 80 ? head.substring(0, 80) : head,
    });
    sushiRememberSideloadedSrt(file.text);
    ref.read(sushiActiveSubtitleProvider.notifier).state =
        SushiActiveSubtitle(auto: false, label: '${pack.title} · ${file.name}');
    await player.setSubtitleFromText(file.text, title: '${pack.title} · ${file.name}', language: 'fa');
    if (!mounted) return;
    navigator.pop();
    _toast(messenger, _kApplied);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      title: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(isDense: true, hintText: 'Title…'),
              onSubmitted: (_) => _search(),
            ),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: _loading ? null : _search),
        ],
      ),
      content: SizedBox(width: 420, height: 380, child: _body()),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _search, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_openPack != null) {
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: const Text('Back to results'),
            onTap: () => setState(() => _openPack = null),
          ),
          const Divider(height: 1),
          ..._files.map((f) => ListTile(
                title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _apply(_openPack!, f),
              )),
        ],
      );
    }
    if (_packs.isEmpty) {
      return const Center(child: Text(_kNoResults));
    }
    return ListView.separated(
      itemCount: _packs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _packs[i];
        return ListTile(
          title: Text(p.hint.isEmpty ? p.title : p.hint, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (p.year.isNotEmpty) p.year,
              if (p.series) 'series',
              if (p.translator.isNotEmpty) p.translator.replaceAll('\n', ' ').trim(),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openPackFiles(p),
        );
      },
    );
  }
}
