// PROTOTYPE — sushi/docs/15-subtitles.md §7. Automatic / Online subtitle picker backed by a
// direct client -> sub-plus.ir call. Production runs the list + ranking server-side. Do not ship.

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/subtitles/sushi_subplus.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

typedef SushiEpisodeRef = ({int season, int episode});

void _log(String phase, [Map<String, Object?> fields = const {}]) =>
    OxplayerStreamLog.event('sushi_sub_$phase', fields: fields);

/// What Sushi has injected into the player right now, or null when a normal (embedded / off)
/// track is active. Drives the "selected" mark in the subtitle list, which the embedded-track
/// machinery knows nothing about because [MediaControlsWrapper.setSubtitleFromText] bypasses it.
class SushiActiveSubtitle {
  const SushiActiveSubtitle({required this.auto, required this.label});
  final bool auto; // true = Automatic, false = a manual pick from the Online sheet
  final String label;
}

final sushiActiveSubtitleProvider = StateProvider<SushiActiveSubtitle?>((ref) => null);

// TODO(sushi): localise these once the feature graduates from prototype (doc 07 §7).
const _kAutomatic = 'Automatic (online)';
const _kOnline = 'Online subtitles…';
const _kSearching = 'Searching sub-plus…';
const _kNoResults = 'No subtitles found';
const _kApplied = 'Subtitle loaded';
const _kFailed = 'Could not load subtitle';

/// The two rows prepended to the subtitle dialog. Empty when the feature is off.
///
/// Everything the async work needs is read from [ref] here, synchronously, because the calls
/// below pop the dialog first — after which this [ref] is disposed and unusable.
List<Widget> sushiSubtitleMenuRows(BuildContext context, WidgetRef ref) {
  if (!OxplayerConfig.isEnabled) return const [];
  final theme = Theme.of(context);
  final active = ref.watch(sushiActiveSubtitleProvider);
  final sel = theme.colorScheme.primary.withValues(alpha: 0.3);
  return [
    ListTile(
      leading: const Icon(Icons.auto_awesome_rounded),
      title: Text(_kAutomatic, style: theme.textTheme.titleMedium),
      tileColor: active?.auto == true ? sel : null,
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        final container = ProviderScope.containerOf(context, listen: false);
        final player = ref.read(videoPlayerProvider);
        final title = _playingTitle(ref);
        final year = _playingYear(ref);
        final episode = _playingEpisode(ref);
        Navigator.of(context).pop();
        sushiAutoLoadSubtitle(
          messenger: messenger,
          container: container,
          player: player,
          title: title,
          year: year,
          episode: episode,
        );
      },
    ),
    ListTile(
      leading: const Icon(Icons.travel_explore_rounded),
      title: Text(_kOnline, style: theme.textTheme.titleMedium),
      subtitle: active?.auto == false ? Text(active!.label, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      tileColor: active?.auto == false ? sel : null,
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        showSushiOnlineSubtitles(navigator.context);
      },
    ),
    const Divider(height: 1),
  ];
}

/// Whether a normal embedded/off subtitle row should show as selected: only when Sushi has not
/// injected an online subtitle over the top of it.
bool sushiEmbeddedRowSelectable(WidgetRef ref) => ref.watch(sushiActiveSubtitleProvider) == null;

/// Call when the user picks a normal embedded / off track, so the Sushi mark clears.
void sushiClearActiveSubtitle(WidgetRef ref) =>
    ref.read(sushiActiveSubtitleProvider.notifier).state = null;

String? _playingTitle(WidgetRef ref) {
  final name = ref.read(playBackModel)?.item.title.trim() ?? '';
  return name.isEmpty ? null : name;
}

String? _playingYear(WidgetRef ref) {
  final overview = ref.read(playBackModel)?.item.overview;
  return (overview?.yearAired ?? overview?.productionYear)?.toString();
}

/// Season/episode of the playing item when it is a TV episode, else null.
SushiEpisodeRef? _playingEpisode(WidgetRef ref) {
  final item = ref.read(playBackModel)?.item;
  if (item is EpisodeModel && item.season > 0 && item.episode > 0) {
    return (season: item.season, episode: item.episode);
  }
  return null;
}

void _toast(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
  );
}

/// Automatic: search by [title], apply the episode's (or top pack's first) file silently.
Future<void> sushiAutoLoadSubtitle({
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
  required MediaControlsWrapper player,
  required String? title,
  required String? year,
  required SushiEpisodeRef? episode,
}) async {
  if (title == null) return;
  _log('auto_start', {'title': title, 'year': year, 'ep': episode == null ? '' : 'S${episode.season}E${episode.episode}'});
  final client = SushiSubplusClient();
  try {
    _toast(messenger, _kSearching);
    final packs = rankSubplusPacks(await client.search(title), year: year, episode: episode);
    _log('auto_search', {'packs': packs.length, 'top': packs.isEmpty ? '' : packs.first.title});
    if (packs.isEmpty) {
      _toast(messenger, _kNoResults);
      return;
    }
    final subs = await client.fetchSubs(packs.first.tag);
    final pick = episode == null
        ? (subs.isEmpty ? null : subs.first)
        : pickEpisodeFile(subs, episode.season, episode.episode);
    _log('auto_files', {'tag': packs.first.tag, 'files': subs.length, 'pick': pick?.name ?? ''});
    if (pick == null) {
      _toast(messenger, _kNoResults);
      return;
    }
    await player.setSubtitleFromText(pick.text, title: '${packs.first.title} · auto', language: 'fa');
    container.read(sushiActiveSubtitleProvider.notifier).state =
        SushiActiveSubtitle(auto: true, label: '${packs.first.title} · ${pick.name}');
    _log('auto_applied', {'chars': pick.text.length});
    _toast(messenger, _kApplied);
  } catch (e, st) {
    _log('auto_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    _toast(messenger, _kFailed);
  } finally {
    client.close();
  }
}

/// Prototype ranking. For a TV [episode] the season match dominates (wrong-season packs sink);
/// then a matching year, then packs that carry release names. The full heuristic (release-token
/// overlap, fps) is doc 15 §4.
List<SubplusPack> rankSubplusPacks(List<SubplusPack> packs, {String? year, SushiEpisodeRef? episode}) {
  final sorted = [...packs];
  sorted.sort((a, b) {
    int score(SubplusPack p) {
      var s = 0;
      if (episode != null) {
        s -= seasonMatchScore(p, episode.season) * 100; // +/-100 dominates everything else
        if (p.releases.any((r) {
          final se = parseSeasonEpisode(r);
          return se.season == episode.season && se.episode == episode.episode;
        })) {
          s -= 20; // a release line naming this exact episode
        }
      }
      if (year != null && year.isNotEmpty && p.year == year) s -= 2;
      if (p.releases.isNotEmpty) s -= 1;
      return s;
    }

    return score(a).compareTo(score(b));
  });
  return sorted;
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
  late final TextEditingController _query = TextEditingController(text: _playingTitle(ref) ?? '');
  late final String? _year = _playingYear(ref);
  late final SushiEpisodeRef? _episode = _playingEpisode(ref);

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
        _packs = rankSubplusPacks(packs, year: _year, episode: _episode);
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
