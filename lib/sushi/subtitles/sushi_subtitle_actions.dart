import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_stream_log.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_prefs_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_subtitle_transport.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/subtitles/sushi_gemini.dart';
import 'package:fladder/sushi/subtitles/sushi_opensubtitles.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';
import 'package:fladder/sushi/subtitles/sushi_subplus.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

void _log(String phase, [Map<String, Object?> fields = const {}]) {
  SushiStreamLog.event('sushi_sub_$phase', fields: fields);
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
  // Result was superseded (user navigated to a different item mid-request) — not a
  // real failure, so callers should not surface a "failed" toast for this.
  static const stale = SushiSubtitleOpResult(ok: false, errorCode: 'stale');
  // Gemini call itself failed (network/HTTP/key-rejected), distinct from a source-fetch failure.
  static const translateServiceFailed = SushiSubtitleOpResult(ok: false, errorCode: 'translate_service_failed');
  // Every fallback model rejected the request with 429 RESOURCE_EXHAUSTED — the key's Gemini
  // billing/credits are depleted, not a transient rate limit. Retrying won't help until topped up.
  static const translateQuotaExceeded = SushiSubtitleOpResult(ok: false, errorCode: 'translate_quota_exceeded');
  // Translation succeeded but the player rejected applying it.
  static const applyFailed = SushiSubtitleOpResult(ok: false, errorCode: 'apply_failed');
}

/// Google's RESOURCE_EXHAUSTED for depleted prepaid credits (billing, account-wide) looks the
/// same as a per-model 429 in the exception message — distinguish it so the UI can point the
/// user at billing instead of suggesting a retry that can never succeed.
bool sushiGeminiQuotaExhausted(String message) =>
    message.contains('RESOURCE_EXHAUSTED') || message.contains('prepayment credits');

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
/// [sessionKey] must change whenever playback actually restarts fresh — item id alone is not
/// enough: picking a different file of the SAME item (e.g. a different upload/quality from
/// outside the player) reopens the player with a session id equal to the last one, so the stale
/// "AI Persian" / "Automatic" active-subtitle marker survived and kept showing as on even though
/// nothing had been sideloaded onto this new file. Callers should key on item id + the specific
/// version/file id, not item id alone.
void sushiBeginPlaybackSubtitleSession(Object src, String sessionKey) {
  if (_subtitleSessionItemId == sessionKey) return;
  _subtitleSessionItemId = sessionKey;
  _translateGen++;
  _lastSideloadedSrt = null;
  _cachedTranslateEn = null;
  _cachedTranslateEnKey = null;
  _packFiles.clear();
  try {
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state = null;
  } catch (_) {}
  _log('session_reset', {'sessionKey': sessionKey, 'gen': _translateGen});
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

bool sushiSubtitleOpShouldFallback(SushiSubtitleOpResult r) =>
    !r.ok && r.errorCode != 'busy' && r.errorCode != 'stale';

Future<SushiSubtitleOpResult> sushiRunAutoLoad(Object src, {MediaControlsWrapper? player}) async {
  if (_subtitleJobBusy) {
    _log('auto_busy');
    return SushiSubtitleOpResult.busy;
  }
  _subtitleJobBusy = true;
  try {
    final p = sushiPlayer(src, player: player);
    // sub-plus.ir has no SLA (doc 15 §6); subdl is the second provider (doc 15 §7) tried when it
    // comes back empty or erroring, before giving up.
    var pick = await _fetchSubplusFile(src, lang: 'persian');
    pick ??= await _fetchSubdlFile(src, lang: 'persian');
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

/// Playback-start chain: Automatic (online) → AI (if Gemini key) → muxed Farsi soft.
/// Hard-sub callers pass [allowAiFallback] false and [hasPersianSoft] false so only Automatic runs.
Future<SushiSubtitleOpResult> sushiRunStartSubtitlePipeline(
  Object src, {
  MediaControlsWrapper? player,
  required bool hasPersianSoft,
  bool allowAiFallback = true,
  PlaybackModel? model,
}) async {
  final auto = await sushiRunAutoLoad(src, player: player);
  if (!sushiSubtitleOpShouldFallback(auto)) return auto;

  if (allowAiFallback && await sushiHasGeminiApiKey()) {
    final ai = await sushiRunTranslateToPersian(src, forceKeyRefresh: false, player: player);
    _log('start_ai_fallback', {'ok': ai.ok, 'error': ai.errorCode});
    if (!sushiSubtitleOpShouldFallback(ai)) return ai;
  }

  if (hasPersianSoft) {
    final applied = await sushiApplyPersianSoftFallback(src, player: player, model: model);
    if (applied) {
      _log('start_soft_fallback');
      return const SushiSubtitleOpResult(ok: true, label: 'Soft sub');
    }
  }
  return auto;
}

Future<bool> sushiApplyPersianSoftFallback(
  Object src, {
  MediaControlsWrapper? player,
  PlaybackModel? model,
}) async {
  final p = sushiPlayer(src, player: player);
  final playback = model ?? sushiRead(src, playBackModel);
  if (playback == null) return false;
  final index = sushiPreferredPersianStreamIndex(playback.subStreams);
  if (index == null) return false;
  final track = playback.subStreams?.firstWhereOrNull((s) => s.index == index);
  if (track == null || !sushiSubtitleTrackIsPlayable(track)) return false;
  final newModel = await playback.setSubtitle(track, p);
  if (newModel == null) return false;
  sushiRead(src, playBackModel.notifier).update((_) => newModel);
  try {
    sushiRead(src, sushiActiveSubtitleProvider.notifier).state = null;
  } catch (_) {}
  return true;
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
      _log('translate_stale', {'gen': gen, 'currentGen': _translateGen});
      return SushiSubtitleOpResult.stale;
    }
    sushiRememberSideloadedSrt(nowFa);
    final applied = await p.setSubtitleFromText(nowFa, title: 'AI Persian', language: 'fa');
    if (!applied) {
      _log('translate_apply_failed', {'chars': nowFa.length});
      return SushiSubtitleOpResult.applyFailed;
    }
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
  } on SushiGeminiException catch (e, st) {
    _log('translate_service_error', {'error': e.toString(), 'stack': st.toString().split('\n').take(3).join(' | ')});
    if (sushiGeminiQuotaExhausted(e.message)) return SushiSubtitleOpResult.translateQuotaExceeded;
    return SushiSubtitleOpResult.translateServiceFailed;
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
    final applied = await player.setSubtitleFromText(merged, title: 'AI Persian', language: 'fa');
    if (!applied) {
      _log('translate_apply_failed', {'chars': merged.length, 'phase': 'full'});
      return;
    }
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
  // The file's own muxed/attached track (any non-Persian language) is a guaranteed timing
  // match for THIS exact media source — try it before searching external catalogs, which can
  // return a mistimed or wrong-cut file (see the Forced-subtitle bug this was added alongside).
  final embedded = await _fetchEmbeddedTranslateSourceSrt(src);
  if (embedded != null && embedded.isNotEmpty) {
    _cachedTranslateEn = embedded;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(embedded);
    _log('translate_source', {'via': 'embedded', 'chars': embedded.length});
    return embedded;
  }
  final os = await _fetchOpenSubtitlesEnglish(src);
  if (os != null && os.isNotEmpty) {
    _cachedTranslateEn = os;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(os);
    _log('translate_source', {'via': 'opensubtitles_en', 'chars': os.length});
    return os;
  }
  final subdlEn = await _fetchSubdlFile(src, lang: 'english');
  if (subdlEn != null) {
    _cachedTranslateEn = subdlEn.file.text;
    _cachedTranslateEnKey = cacheKey;
    sushiRememberSideloadedSrt(subdlEn.file.text);
    _log('translate_source', {'via': 'subdl_en', 'chars': subdlEn.file.text.length, 'label': subdlEn.label});
    return subdlEn.file.text;
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

/// Bitmap/image subtitle codecs Jellyfin can't hand back as text — a `.srt` fetch for one of
/// these would come back empty or garbage, not a translatable transcript.
const _sushiImageSubtitleCodecs = {
  'pgssub',
  'dvdsub',
  'dvd_subtitle',
  'dvbsub',
  'dvb_subtitle',
  'vobsub',
  'xsub',
  'hdmv_pgs_subtitle',
};

/// Picks a text-based, non-Persian, non-Off track with a fetchable delivery URL — preferring
/// English when more than one language is muxed in. Persian is excluded because translating it
/// would be Farsi-to-Farsi (doc 15 §12's "2017 same-title collision" case); any other language
/// works since Gemini's prompt doesn't pin a source language.
SubStreamModel? _pickEmbeddedTranslateSource(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final candidates = subStreams.where((s) {
    if (s.index == -1) return false;
    if ((s.url ?? '').trim().isEmpty) return false;
    if (_sushiImageSubtitleCodecs.contains(s.codec.trim().toLowerCase())) return false;
    if (SushiPersianLanguage.isPersianLanguage(s.language) ||
        SushiPersianLanguage.isPersianLanguage(s.displayTitle)) {
      return false;
    }
    return true;
  }).toList();
  if (candidates.isEmpty) return null;
  final english = candidates.firstWhereOrNull(
    (s) => sushiIsEnglishLanguage(s.language) || s.displayTitle.toLowerCase().contains('english'),
  );
  return english ?? candidates.first;
}

/// The file's own muxed/attached subtitle, fetched straight from the Jellyfin server (same
/// `.srt` delivery URL the player itself would use) — no title search, so no risk of matching
/// the wrong release or a Forced-only file.
Future<String?> _fetchEmbeddedTranslateSourceSrt(Object src) async {
  final subStreams = sushiRead(src, playBackModel)?.subStreams;
  final picked = _pickEmbeddedTranslateSource(subStreams);
  final url = picked?.url?.trim();
  if (picked == null || url == null || url.isEmpty) return null;
  try {
    final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    var text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    text = text.trim();
    if (sushiParseSrt(text).isEmpty) return null;
    return text;
  } catch (e) {
    _log('embedded_source_error', {'error': e.toString(), 'lang': picked.language});
    return null;
  }
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

/// Second subtitle provider (doc 15 §7), server-proxied so subdl's key never reaches this device.
/// Same return shape as [_fetchSubplusFile] so callers can try either interchangeably: subdl
/// matches by tmdb_id directly (no title-text search step), and each result is already a single
/// file (no multi-file ZIP pack to pick within), so this skips straight from a ranked pack to
/// `sushiFetchSubtitleFile`. `tag` is prefixed `subdl:` so a later fetch of the same pick (were it
/// ever cached like subplus's `_packFiles`) can tell providers apart.
Future<({SubplusSubFile file, String label})?> _fetchSubdlFile(Object src, {required String lang}) async {
  final tmdbId = sushiPlayingTmdbId(src);
  if (tmdbId == null) return null;
  final title = sushiPlayingTitle(src);
  final episode = sushiPlayingEpisode(src);
  final subdlLang = lang == 'persian' ? 'FA' : 'EN';
  try {
    _log('subdl_fetch', {'lang': lang, 'title': title ?? '', 'tmdbId': tmdbId});
    final res = await sushiFetchSubtitles(
      tmdbId: tmdbId,
      kind: episode != null ? 2 : 1,
      seasonNo: episode?.season ?? 0,
      episodeNo: episode?.episode ?? 0,
      lang: subdlLang,
    );
    if (res == null || res.packs.isEmpty) {
      _log('subdl_fetch_empty', {'lang': lang, 'title': title ?? ''});
      return null;
    }
    final packs = res.packs
        .map((p) => SubplusPack(
              tag: 'subdl:${p.tag}',
              title: p.releaseName,
              imdb: '',
              year: '',
              series: episode != null,
              translator: p.translator,
              releases: p.releases,
              poster: '',
            ))
        .toList();
    // No query filter here: subdl already matched on tmdb_id server-side, an exact-title
    // guarantee subplus's fuzzy multi-title search doesn't have. Re-applying the substring
    // title filter here only risks dropping every pack when a release name (a raw scene
    // filename, e.g. "Ride.or.Die.2021.1080p...") doesn't happen to contain the query text.
    final ranked = rankSubplusPacks(packs, episode: episode);
    if (ranked.isEmpty) {
      _log('subdl_fetch_empty', {'lang': lang, 'title': title ?? '', 'reason': 'no_rank_match'});
      return null;
    }
    final top = ranked.first;
    final rawTag = top.tag.substring('subdl:'.length);
    final kind = episode != null ? 2 : 1;
    final seasonNo = episode?.season ?? 0;
    final episodeNo = episode?.episode ?? 0;
    // locator must match exactly what the server stamps as the copy's caption
    // (api.subtitleLocator, be/internal/app/api/subtitle.go) — arm the delivery waiter for it
    // *before* triggering the copy below, same ordering sushi_tdlib_playback_resolver.dart uses
    // for video, so the live push can never land before something is listening for it.
    final locator = 'sub_${tmdbId}_${kind}_${seasonNo}_${episodeNo}_$subdlLang';
    final controller = SushiTdlibBridgeController.instance();
    await controller.armDeliveryWaiter(locator);
    final fileRes = await sushiFetchSubtitleFile(tag: rawTag);
    if (fileRes == null) {
      _log('subdl_fetch_error', {'lang': lang, 'reason': 'no_delivery_ref'});
      return null;
    }
    // The server placed a fresh copy in this session's own chat, round-robinned across delivery
    // bots — the reference alone (doc 15 §7) never carries the text, since a real subtitle
    // routinely exceeds the wire protocol's per-message size limit. fileRes.messageId is the
    // Bot API's own chat-scoped counter, NOT this reader account's MTProto message-id space, so
    // it cannot be looked up directly (that mismatch is what produced OX_DM_STALE / wrong-file
    // reads before this fix) — fetchSmallDocument resolves the real id from the live push instead,
    // exactly like a fresh (0/0) video delivery does.
    final text = await SushiTdlibBridgeController.instance().fetchSmallDocument(
      botId: fileRes.botId,
      messageId: fileRes.messageId,
      locator: locator,
    );
    if (text.isEmpty) {
      _log('subdl_fetch_error', {'lang': lang, 'reason': 'empty_document'});
      return null;
    }
    _log('subdl_pick', {'lang': lang, 'pack': top.title});
    final file = SubplusSubFile(
      name: top.title,
      ext: fileRes.ext.isNotEmpty ? fileRes.ext : '.srt',
      text: text,
    );
    return (file: file, label: top.title);
  } catch (e, st) {
    _log('subdl_fetch_error', {
      'lang': lang,
      'error': e.toString(),
      'stack': st.toString().split('\n').take(3).join(' | '),
    });
    return null;
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
  final applied = await player.setSubtitleFromText(file.text, title: labelPrefix, language: 'fa');
  if (!applied) {
    _log('apply_failed', {'chars': file.text.length, 'label': labelPrefix, 'auto': auto});
    return SushiSubtitleOpResult.applyFailed;
  }
  sushiRead(src, sushiActiveSubtitleProvider.notifier).state =
      SushiActiveSubtitle(auto: auto, label: labelPrefix);
  _log('applied', {'chars': file.text.length, 'label': labelPrefix, 'auto': auto});
  return SushiSubtitleOpResult(ok: true, label: labelPrefix);
}
