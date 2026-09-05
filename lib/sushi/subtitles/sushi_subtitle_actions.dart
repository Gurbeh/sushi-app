import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_prefs_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/subtitles/sushi_gemini.dart';
import 'package:fladder/sushi/subtitles/sushi_opensubtitles.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';
import 'package:fladder/sushi/subtitles/sushi_subplus.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

void _log(String phase, [Map<String, Object?> fields = const {}]) {
  OxplayerStreamLog.event('sushi_sub_$phase', fields: fields);
  developer.log('sushi_sub_$phase $fields', name: 'sushi.subs');
}

typedef SushiEpisodeRef = ({int season, int episode});

class SushiActiveSubtitle {
  const SushiActiveSubtitle({required this.auto, required this.label});
  final bool auto;
  final String label;
}

final sushiActiveSubtitleProvider = StateProvider<SushiActiveSubtitle?>((ref) => null);

T sushiRead<T>(Object src, ProviderListenable<T> provider) {
  if (src is WidgetRef) return src.read(provider);
  if (src is Ref) return src.read(provider);
  if (src is ProviderContainer) return src.read(provider);
  throw ArgumentError.value(src, 'src', 'want WidgetRef, Ref or ProviderContainer');
}

/// [MediaControlsWrapper.ref] is [videoPlayerProvider]'s Ref. Reading that
/// provider from inside [VideoPlayerNotifier] trips Riverpod's debug
/// "A provider cannot depend on itself" and kills Automatic on play.
MediaControlsWrapper sushiPlayer(Object src, {MediaControlsWrapper? player}) {
  return player ?? sushiRead(src, videoPlayerProvider);
}

bool sushiEmbeddedRowSelectable(WidgetRef ref) => ref.watch(sushiActiveSubtitleProvider) == null;

void sushiClearActiveSubtitle(WidgetRef ref) =>
    ref.read(sushiActiveSubtitleProvider.notifier).state = null;

/// Prototype ranking. For a TV [episode] the season match dominates (wrong-season packs sink);
/// then a matching year, then packs that carry release names. The full heuristic (release-token
/// overlap, fps) is doc 15 §4.
List<SubplusPack> rankSubplusPacks(
  List<SubplusPack> packs, {
  String? query,
  String? year,
  SushiEpisodeRef? episode,
}) {
  final sorted = sushiFilterSubplusPacks(
    packs,
    query: query,
    year: year,
    episode: episode,
  );
  sorted.sort((a, b) {
    int score(SubplusPack p) {
      var s = 0;
      if (episode != null) {
        s -= seasonMatchScore(p, episode.season) * 100;
        if (p.releases.any((r) {
          final se = parseSeasonEpisode(r);
          return se.season == episode.season && se.episode == episode.episode;
        })) {
          s -= 20;
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

class SushiSubtitleOpResult {
  const SushiSubtitleOpResult({
    required this.ok,
    this.errorCode,
    this.label,
    this.fileNames,
    this.tag,
  });

  final bool ok;
  final String? errorCode;
  final String? label;
  final List<String>? fileNames;
  final String? tag;

  static const missingKey = SushiSubtitleOpResult(ok: false, errorCode: 'missing_key');
  static const noSource = SushiSubtitleOpResult(ok: false, errorCode: 'no_source');
  static const noResults = SushiSubtitleOpResult(ok: false, errorCode: 'no_results');
  static const failed = SushiSubtitleOpResult(ok: false, errorCode: 'failed');
  static const busy = SushiSubtitleOpResult(ok: false, errorCode: 'busy');
}

class SushiAiKeySetupInfo {
  const SushiAiKeySetupInfo({required this.deepLink, required this.telegramInstalled});
  final String deepLink;
  final bool telegramInstalled;
}

String? _lastSideloadedSrt;
String? _subtitleSessionItemId;
final Map<String, List<SubplusSubFile>> _packFiles = {};
bool _subtitleJobBusy = false;

String? sushiLastSideloadedSrt() => _lastSideloadedSrt;

void sushiRememberSideloadedSrt(String text) => _lastSideloadedSrt = text;

/// Drop the previous title's AI/Automatic sideload so it cannot land on this item minutes later.
void sushiBeginPlaybackSubtitleSession(Object src, String itemId) {
  if (_subtitleSessionItemId == itemId) return;
  _subtitleSessionItemId = itemId;
  _translateGen++;
  _lastSideloadedSrt = null;
  _cachedTranslateEn = null;
  _cachedTranslateEnKey = null;
  _packFiles.clear();
  try {
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state = null;
  } catch (_) {}
  _log('session_reset', {'itemId': itemId, 'gen': _translateGen});
}

Future<List<SubplusPack>> sushiSearchOnlinePacks(Object src) async {
  final title = sushiPlayingTitle(src);
  if (title == null) return const [];
  final client = SushiSubplusClient();
  try {
    _log('search_start', {'q': title});
    final packs = rankSubplusPacks(
      await client.search(title),
      query: title,
      year: sushiPlayingYear(src),
      episode: sushiPlayingEpisode(src),
    );
    _log('search_done', {'packs': packs.length});
    return packs;
  } finally {
    client.close();
  }
}

Future<SushiSubtitleOpResult> sushiDownloadOnlinePack({
  required Object src,
  required String tag,
  required String fileName,
  MediaControlsWrapper? player,
}) async {
  final p = sushiPlayer(src, player: player);
  final client = SushiSubplusClient();
  try {
    var files = _packFiles[tag];
    if (files == null) {
      files = await client.fetchSubs(tag);
      _packFiles[tag] = files;
    }
    if (files.isEmpty) return SushiSubtitleOpResult.noResults;
    if (fileName.isEmpty) {
      if (files.length == 1) {
        return _applyFile(src, p, files.first, auto: false, labelPrefix: files.first.name);
      }
      final episode = sushiPlayingEpisode(src);
      if (episode != null) {
        final pick = pickEpisodeFile(files, episode.season, episode.episode);
        if (pick != null) {
          return _applyFile(src, p, pick, auto: false, labelPrefix: pick.name);
        }
      }
      return SushiSubtitleOpResult(
        ok: false,
        errorCode: 'need_pick',
        tag: tag,
        fileNames: files.map((f) => f.name).toList(),
      );
    }
    final match = files.where((f) => f.name == fileName);
    if (match.isEmpty) return SushiSubtitleOpResult.noResults;
    return _applyFile(src, p, match.first, auto: false, labelPrefix: match.first.name);
  } catch (e, st) {
    _log('download_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    return SushiSubtitleOpResult.failed;
  } finally {
    client.close();
  }
}

Future<SushiSubtitleOpResult> sushiRunAutoLoad(Object src, {MediaControlsWrapper? player}) async {
  if (_subtitleJobBusy) {
    _log('auto_busy');
    return SushiSubtitleOpResult.busy;
  }
  _subtitleJobBusy = true;
  try {
    final p = sushiPlayer(src, player: player);
    final pick = await _fetchSubplusFile(src, lang: 'persian');
    if (pick == null) {
      _log('auto_no_results');
      return SushiSubtitleOpResult.noResults;
    }
    return _applyFile(
      src,
      p,
      pick.file,
      auto: true,
      labelPrefix: pick.label,
    );
  } finally {
    _subtitleJobBusy = false;
  }
}

Future<SushiSubtitleOpResult> sushiRunTranslateToPersian(
  Object src, {
  bool forceKeyRefresh = true,
  MediaControlsWrapper? player,
}) async {
  if (_subtitleJobBusy) return SushiSubtitleOpResult.busy;
  _subtitleJobBusy = true;
  try {
    return await _sushiRunTranslateToPersianBody(src, forceKeyRefresh: forceKeyRefresh, player: player);
  } finally {
    _subtitleJobBusy = false;
  }
}

Future<SushiSubtitleOpResult> _sushiRunTranslateToPersianBody(
  Object src, {
  required bool forceKeyRefresh,
  MediaControlsWrapper? player,
}) async {
  final key = await sushiGeminiApiKey(force: forceKeyRefresh);
  if (key == null || key.isEmpty) return SushiSubtitleOpResult.missingKey;

  // Never reuse a prior sideload — Automatic/Online can cache the wrong same-title pack
  // (2017 *The Breadwinner* while TMDB 1440050 is the 2026 film).
  final source = await _fetchTranslateSourceSrt(src);
  if (source == null || source.isEmpty) return SushiSubtitleOpResult.noSource;

  final cues = sushiParseSrt(source);
  if (cues.isEmpty) return SushiSubtitleOpResult.noSource;

  final gemini = SushiGeminiClient();
  final p = sushiPlayer(src, player: player);
  final gen = ++_translateGen;
  final startedFor = _subtitleSessionItemId;
  try {
    var at = p.lastState?.position ?? Duration.zero;
    try {
      final media = sushiRead(src, mediaPlaybackProvider);
      if (media.position > at) at = media.position;
    } catch (_) {}
    try {
      final start = await sushiRead(src, playBackModel)?.startDuration();
      if (start != null && start > at) at = start;
    } catch (_) {}
    final window = sushiSplitCuesAroundPlayback(cues, at);
    _log('translate_start', {
      'cues': cues.length,
      'now': window.now.length,
      'later': window.later.length,
      'posMs': at.inMilliseconds,
    });
    final nowFa = await gemini.translateCuesToPersian(window.now, key);
    if (gen != _translateGen || startedFor != _subtitleSessionItemId) {
      return SushiSubtitleOpResult.failed;
    }
    sushiRememberSideloadedSrt(nowFa);
    await p.setSubtitleFromText(nowFa, title: 'AI Persian', language: 'fa');
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state =
        const SushiActiveSubtitle(auto: false, label: 'AI Persian');
    _log('translate_applied', {'chars': nowFa.length, 'phase': 'window', 'cues': window.now.length});
    if (window.later.isNotEmpty) {
      unawaited(_translateRestInBackground(
        gen: gen,
        startedFor: startedFor,
        player: p,
        key: key,
        nowCues: sushiParseSrt(nowFa),
        later: window.later,
      ));
    }
    return const SushiSubtitleOpResult(ok: true, label: 'AI Persian');
  } catch (e, st) {
    _log('translate_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    return SushiSubtitleOpResult.failed;
  } finally {
    gemini.close();
  }
}

int _translateGen = 0;

Future<void> _translateRestInBackground({
  required int gen,
  required String? startedFor,
  required MediaControlsWrapper player,
  required String key,
  required List<SushiSrtCue> nowCues,
  required List<SushiSrtCue> later,
}) async {
  final gemini = SushiGeminiClient();
  try {
    final rest = await gemini.translateCuesToPersian(later, key, concurrency: 3);
    if (gen != _translateGen || startedFor != _subtitleSessionItemId) return;
    final merged = sushiMergeSrtByTiming(nowCues, sushiParseSrt(rest));
    sushiRememberSideloadedSrt(merged);
    await player.setSubtitleFromText(merged, title: 'AI Persian', language: 'fa');
    _log('translate_applied', {'chars': merged.length, 'phase': 'full'});
  } catch (e, st) {
    _log('translate_bg_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
  } finally {
    gemini.close();
  }
}

/// English first (OpenSubtitles TMDB id, then sub-plus). Never Persian — that was the 2017
/// same-title collision, then Gemini rewrote Farsi into Farsi. Gemini output is what gets
/// sideloaded.
String? _cachedTranslateEn;
String? _cachedTranslateEnKey;

Future<String?> _fetchTranslateSourceSrt(Object src) async {
  final cacheKey = '${sushiPlayingTitle(src) ?? ''}|${sushiPlayingYear(src) ?? ''}|${sushiPlayingTmdbId(src) ?? ''}';
  final cached = _cachedTranslateEn;
  if (cached != null && cached.isNotEmpty && _cachedTranslateEnKey == cacheKey) {
    _log('translate_source', {'via': 'memory', 'chars': cached.length});
    return cached;
  }
  final os = await _fetchOpenSubtitlesEnglish(src);
  if (os != null && os.isNotEmpty) {
    _cachedTranslateEn = os;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(os);
    _log('translate_source', {'via': 'opensubtitles_en', 'chars': os.length});
    return os;
  }
  final en = await _fetchSubplusFile(src, lang: 'english');
  if (en != null) {
    _cachedTranslateEn = en.file.text;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(en.file.text);
    _log('translate_source', {'via': 'subplus_en', 'chars': en.file.text.length, 'label': en.label});
    return en.file.text;
  }
  return null;
}

Future<({SubplusSubFile file, String label})?> _fetchSubplusFile(Object src, {required String lang}) async {
  final title = sushiPlayingTitle(src);
  if (title == null) return null;
  final year = sushiPlayingYear(src);
  final episode = sushiPlayingEpisode(src);
  final client = SushiSubplusClient();
  try {
    _log('subplus_fetch', {'lang': lang, 'title': title, 'year': year ?? ''});
    final raw = await client.search(title, lang: lang);
    final packs = rankSubplusPacks(raw, query: title, year: year, episode: episode);
    if (packs.isEmpty) {
      _log('subplus_fetch_empty', {'lang': lang, 'title': title, 'year': year ?? '', 'raw': raw.length});
      return null;
    }
    final pack = packs.first;
    final subs = await client.fetchSubs(pack.tag);
    _packFiles[pack.tag] = subs;
    final pick = episode == null
        ? pickMovieSubFile(subs)
        : pickEpisodeFile(subs, episode.season, episode.episode);
    if (pick == null) return null;
    _log('subplus_pick', {
      'lang': lang,
      'pack': pack.title,
      'packYear': pack.year,
      'imdb': pack.imdb,
      'file': pick.name,
    });
    return (file: pick, label: '${pack.title} · ${pick.name}');
  } catch (e, st) {
    _log('subplus_fetch_error', {
      'lang': lang,
      'error': e.toString(),
      'stack': st.toString().split('\n').take(3).join(' | '),
    });
    return null;
  } finally {
    client.close();
  }
}

Future<String?> _fetchOpenSubtitlesEnglish(Object src) async {
  final title = sushiPlayingTitle(src);
  if (title == null) return null;
  final client = SushiOpenSubtitlesClient();
  if (!client.configured) {
    _log('opensubs_skip', {'reason': 'no_consumer_key'});
    return null;
  }
  try {
    final text = await client.fetchEnglishSrt(
      title: title,
      tmdbId: sushiPlayingTmdbId(src),
      episode: sushiPlayingEpisode(src),
      year: sushiPlayingYear(src),
    );
    return text;
  } catch (e, st) {
    _log('opensubs_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    return null;
  } finally {
    client.close();
  }
}

Future<SushiAiKeySetupInfo> sushiAiKeySetupInfo() async {
  final url = SushiConfig.mainBotAppCodeUrl('ai_key');
  var installed = true;
  try {
    installed = await canLaunchUrl(
      Uri.parse('tg://resolve?domain=${SushiConfig.mainBotUsername}'),
    );
  } catch (_) {
    installed = true;
  }
  return SushiAiKeySetupInfo(deepLink: url, telegramInstalled: installed);
}

String? sushiPlayingTitle(Object src) {
  final name = sushiRead(src, playBackModel)?.item.title.trim() ?? '';
  return name.isEmpty ? null : name;
}

String? sushiPlayingYear(Object src) {
  final overview = sushiRead(src, playBackModel)?.item.overview;
  return (overview?.yearAired ?? overview?.productionYear)?.toString();
}

SushiEpisodeRef? sushiPlayingEpisode(Object src) {
  final item = sushiRead(src, playBackModel)?.item;
  if (item is EpisodeModel && item.season > 0 && item.episode > 0) {
    return (season: item.season, episode: item.episode);
  }
  return null;
}

int? sushiPlayingTmdbId(Object src) {
  final item = sushiRead(src, playBackModel)?.item;
  if (item == null) return null;
  if (item is EpisodeModel) {
    return sushiTmdbIdFromItemId(item.parentId ?? '') ?? sushiTmdbIdFromItemId(item.id);
  }
  return sushiTmdbIdFromItemId(item.id);
}

Future<SushiSubtitleOpResult> _applyFile(
  Object src,
  MediaControlsWrapper player,
  SubplusSubFile file, {
  required bool auto,
  required String labelPrefix,
}) async {
  sushiRememberSideloadedSrt(file.text);
  await player.setSubtitleFromText(file.text, title: labelPrefix, language: 'fa');
  sushiRead(src, sushiActiveSubtitleProvider.notifier).state =
      SushiActiveSubtitle(auto: auto, label: labelPrefix);
  _log('applied', {'chars': file.text.length, 'label': labelPrefix, 'auto': auto});
  return SushiSubtitleOpResult(ok: true, label: labelPrefix);
}
