import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/cache/sushi_catalog_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/sushi_home_transport.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_item_transport.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';
import 'package:fladder/sushi/sushi_sync_transport.dart';

export 'package:fladder/sushi/cache/sushi_catalog_store.dart';

/// Title page is cached until a catalog delta; files live 5 minutes (docs/11 §2, docs/12 §5).
const sushiFilesTtl = Duration(minutes: 5);
const sushiHomeTtlFallback = Duration(hours: 1);

/// First N cards of each non-slider rail (viewport on phone ≈ 2). Slider is taken whole.
const sushiHomePrefetchPerRail = 2;
const sushiPrefetchGap = Duration(seconds: 1);

/// Slider first (all), then [sushiHomePrefetchPerRail] from each other rail. Dedupes `(tmdbId, kind)`.
List<SushiRow> sushiHomePrefetchPlan(SushiCachedHome home, {int perRail = sushiHomePrefetchPerRail}) {
  final out = <SushiRow>[];
  final seen = <String>{};
  void add(Iterable<SushiRow> rows) {
    for (final row in rows) {
      if (row.tmdbId <= 0) continue;
      final key = '${row.tmdbId}:${sushiKindToWire(row.kind)}';
      if (seen.add(key)) out.add(row);
    }
  }

  add(home.slider);
  add(home.mostWatched.take(perRail));
  add(home.trending.take(perRail));
  add(home.seriesMostWatched.take(perRail));
  add(home.seriesTrending.take(perRail));
  return out;
}

typedef SushiItemFetcher = Future<SushiItemRes?> Function({required int tmdbId, required int kind});
typedef SushiFilesFetcher = Future<SushiFilesRes?> Function({required int episodeId});
typedef SushiEpisodesFetcher = Future<SushiEpisodesRes?> Function({
  required int tmdbId,
  required int kind,
  required int seasonNo,
  int page,
});
typedef SushiHomeFetcher = Future<SushiHomeRes?> Function({required int tab});
typedef SushiSyncFetcher = Future<SushiSyncRes?> Function({required int watchedWatermark});
typedef SushiCatalogSessionOwner = Future<String> Function();
typedef SushiCatalogOwnerRead = Future<String> Function();
typedef SushiCatalogOwnerWrite = Future<void> Function(String owner);

/// Client-first cache (docs/11): screens read SQLite, network only updates.
///
/// Cached title → `/files` (lite). Miss → `/item` then `/files`. TMDB-only pages
/// (no play-target, no season index) are never written (R-CACHE-6).
class SushiCatalogController {
  SushiCatalogController(
    this._store, {
    SushiItemFetcher fetchItem = sushiFetchItem,
    SushiFilesFetcher fetchFiles = sushiFetchFiles,
    SushiEpisodesFetcher fetchEpisodes = sushiFetchEpisodes,
    SushiHomeFetcher fetchHome = sushiFetchHome,
    SushiSyncFetcher fetchSync = sushiFetchSync,
    DateTime Function()? clock,
    Duration prefetchGap = sushiPrefetchGap,
    Future<void> Function(Duration duration)? sleep,
    this.sessionOwner,
    this.readPersistedOwner,
    this.persistOwner,
  })  : _fetchItem = fetchItem,
        _fetchFiles = fetchFiles,
        _fetchEpisodes = fetchEpisodes,
        _fetchHome = fetchHome,
        _fetchSync = fetchSync,
        _clock = clock ?? DateTime.now,
        _prefetchGap = prefetchGap,
        _sleep = sleep ?? Future<void>.delayed;

  /// Current Sushi assignment identity (binding token). Empty = no usable session.
  /// Null [sessionOwner] skips the lock (unit tests that do not care about logout).
  final SushiCatalogSessionOwner? sessionOwner;
  final SushiCatalogOwnerRead? readPersistedOwner;
  final SushiCatalogOwnerWrite? persistOwner;

  /// Home slider paints backdrop from the title page. Prefetch calls this after `/item` lands.
  void Function(SushiItemRes page)? onTitleCached;

  final SushiCatalogStore _store;
  final SushiItemFetcher _fetchItem;
  final SushiFilesFetcher _fetchFiles;
  final SushiEpisodesFetcher _fetchEpisodes;
  final SushiHomeFetcher _fetchHome;
  final SushiSyncFetcher _fetchSync;
  final DateTime Function() _clock;
  final Duration _prefetchGap;
  final Future<void> Function(Duration duration) _sleep;

  int _p0 = 0;
  int _epoch = 0;
  bool _busy = false;
  Completer<void>? _busyDone;
  List<SushiRow> _queue = [];
  SushiCachedHome? _prefetchHome;
  Completer<void>? _bindInFlight;

  Future<SushiCachedHome?> peekHome() async {
    await _bindSession();
    return _store.readHome();
  }

  Future<bool> homeIsStale() async {
    final home = await peekHome();
    if (home == null || home.isEmpty) return true;
    return !_clock().isBefore(home.fetchedAt.add(home.ttl));
  }

  /// Logout / account-switch: drop SQLite rows and the persisted owner stamp.
  Future<void> wipeSession() async {
    await _wipeCatalogRows();
    await persistOwner?.call('');
  }

  Future<void> _wipeCatalogRows() async {
    cancelPrefetch();
    _prefetchHome = null;
    await _store.clearAll();
  }

  Future<SushiCachedHome?> refreshHome({bool force = false}) {
    return _exclusiveRead(() async {
      if (!force && !await homeIsStale()) return _store.readHome();

      final movies = await _fetchHome(tab: sushiHomeTabMovies);
      final series = await _fetchHome(tab: sushiHomeTabSeries);
      if (movies == null && series == null) return _store.readHome();

      List<SushiRow> rail(SushiHomeRes? res, SushiRailKind kind) => res?.rowsFor(kind) ?? const [];
      final ttlSeconds = movies?.ttlSeconds ?? series?.ttlSeconds ?? 0;
      final home = SushiCachedHome(
        slider: sushiUniqueRows([
          ...rail(movies, SushiRailKind.slider),
          ...rail(series, SushiRailKind.slider),
        ]),
        mostWatched: rail(movies, SushiRailKind.mostWatched),
        trending: rail(movies, SushiRailKind.trending),
        seriesMostWatched: rail(series, SushiRailKind.mostWatched),
        seriesTrending: rail(series, SushiRailKind.trending),
        seq: series?.seq ?? movies?.seq ?? 0,
        ttl: Duration(seconds: ttlSeconds > 0 ? ttlSeconds : sushiHomeTtlFallback.inSeconds),
        fetchedAt: _clock(),
        latestApp: movies?.latestApp ?? series?.latestApp,
      );
      await _store.writeHome(home);
      return home;
    });
  }

  /// Cross-device watched-state sync (docs/11 §6.1): pulls what changed since the last applied
  /// `user_episode_state.seq` and merges it into the local mirror. Loops while the reply says
  /// more is waiting (capped so a bad server reply cannot spin forever), same pattern as
  /// [openSeason]'s page loop.
  Future<List<SushiWatchedState>> refreshWatchedState() {
    return _exclusiveRead(() async {
      final applied = <SushiWatchedState>[];
      var loops = 0;
      while (loops < 50) {
        loops++;
        final watermark = await _store.readWatchedWatermark();
        final res = await _fetchSync(watchedWatermark: watermark);
        if (res == null) return applied;
        if (res.watched.isNotEmpty || res.watchedWatermark != watermark) {
          await _store.applyWatchedDelta(res.watched, res.watchedWatermark);
          applied.addAll(res.watched);
        }
        if (!res.watchedMore) return applied;
      }
      return applied;
    });
  }

  Future<bool> isEpisodeWatched(int episodeId) => _store.isEpisodeWatched(episodeId);

  /// Immediate same-device write, ahead of the next [refreshWatchedState] round trip (docs/11 §6.1).
  Future<void> markEpisodeWatchedLocally(int episodeId, bool done) =>
      _store.markEpisodeWatchedLocally(episodeId, done);

  Future<SushiTitleSnapshot?> peekTitle({required int tmdbId, required SushiKind kind}) async {
    await _bindSession();
    final page = await _store.readTitle(tmdbId, sushiKindToWire(kind));
    if (page == null) return null;
    final episodeId = page.episodes.firstOrNull?.episodeId;
    var files = const <SushiFile>[];
    var filesKnown = episodeId == null || episodeId == 0;
    if (episodeId != null && episodeId != 0) {
      final cachedFiles = await _store.readFiles(episodeId);
      if (cachedFiles != null) {
        files = cachedFiles.files;
        filesKnown = true;
      }
    }
    return SushiTitleSnapshot(
      page: page,
      files: files,
      fromCache: true,
      lite: true,
      filesKnown: filesKnown,
    );
  }

  /// Title page only — home slider overlay. Skips `/files`.
  Future<SushiItemRes?> peekCachedTitle({required int tmdbId, required SushiKind kind}) async {
    await _bindSession();
    return _store.readTitle(tmdbId, sushiKindToWire(kind));
  }

  /// Paint from [peekTitle] first. This call does the network update.
  /// Titles whose cached page has no trailer key. One live `/item` per controller, so a miss
  /// does not refetch on every open.
  final Set<String> _trailerProbed = {};

  Future<SushiTitleSnapshot> openTitle({
    required int tmdbId,
    required SushiKind kind,
    int? episodeId,
    bool force = false,
  }) {
    return _exclusiveRead(() async {
      final cached = await _store.readTitle(tmdbId, sushiKindToWire(kind));
      var page = cached;
      final trailerStamp = '$tmdbId:${sushiKindToWire(kind)}';
      final probeTrailer = cached != null &&
          cached.trailerKey.isEmpty &&
          !_trailerProbed.contains(trailerStamp);
      var lite = cached != null && !force && !probeTrailer;

      if (cached == null || force || probeTrailer) {
        final live = await _fetchItem(tmdbId: tmdbId, kind: sushiKindToWire(kind));
        if (live != null) {
          _trailerProbed.add(trailerStamp);
          page = live;
          lite = false;
          if (sushiItemResPlayable(live)) {
            await _store.writeTitle(live);
            onTitleCached?.call(live);
          }
        }
      }

      final epId = episodeId ?? page?.episodes.firstOrNull?.episodeId;
      var files = const <SushiFile>[];
      var positionS = 0;
      var done = false;
      var lastFileId = 0;
      var filesKnown = true;
      if (epId != null && epId != 0) {
        final filesRes = await openFiles(episodeId: epId, force: force);
        files = filesRes.files;
        positionS = filesRes.positionS;
        done = filesRes.done;
        lastFileId = filesRes.lastFileId;
        filesKnown = filesRes.known;
      }
      debugPrint(
        '[sushi] title tmdb=$tmdbId lite=$lite fromCache=${cached != null} files=${files.length} filesKnown=$filesKnown',
      );
      return SushiTitleSnapshot(
        page: page,
        files: files,
        fromCache: cached != null,
        lite: lite,
        positionS: positionS,
        done: done,
        lastFileId: lastFileId,
        filesKnown: filesKnown,
      );
    });
  }

  Future<SushiFilesRes> openFiles({required int episodeId, bool force = false}) {
    return _exclusiveRead(() async {
      final cached = await _store.readFiles(episodeId);
      if (!force && cached != null && _clock().isBefore(cached.fetchedAt.add(sushiFilesTtl))) {
        debugPrint('[sushi] files cache episode=$episodeId n=${cached.files.length}');
        return SushiFilesRes(files: cached.files);
      }
      debugPrint('[sushi] files network episode=$episodeId');
      final live = await _fetchFiles(episodeId: episodeId);
      if (live != null) {
        await _store.replaceFiles(episodeId, live.files, _clock());
        return live;
      }
      if (cached != null) {
        return SushiFilesRes(files: cached.files);
      }
      return const SushiFilesRes(files: [], known: false);
    });
  }

  Future<List<SushiEpisode>?> peekSeason({
    required int tmdbId,
    required SushiKind kind,
    required int seasonNo,
  }) async {
    await _bindSession();
    return _store.readSeason(tmdbId, sushiKindToWire(kind), seasonNo);
  }

  /// One season's episode list. Cached after the first full fetch (ADR 0028).
  Future<List<SushiEpisode>> openSeason({
    required int tmdbId,
    required SushiKind kind,
    required int seasonNo,
    bool force = false,
  }) {
    return _exclusiveRead(() async {
      final kindWire = sushiKindToWire(kind);
      if (!force) {
        final cached = await _store.readSeason(tmdbId, kindWire, seasonNo);
        if (cached != null) return cached;
      }
      final all = <SushiEpisode>[];
      var page = 0;
      var pages = 1;
      while (page < pages && page < 50) {
        final live = await _fetchEpisodes(
          tmdbId: tmdbId,
          kind: kindWire,
          seasonNo: seasonNo,
          page: page,
        );
        if (live == null) break;
        all.addAll(live.episodes);
        pages = live.pages < 1 ? 1 : live.pages;
        page++;
        if (live.episodes.isEmpty) break;
      }
      if (all.isNotEmpty) {
        await _store.writeSeason(tmdbId, kindWire, seasonNo, all);
      }
      return all;
    });
  }

  /// P2: `/item` only for viewport-ish home cards missing from SQLite (docs/11 §4).
  Future<void> prefetchVisibleHome(SushiCachedHome home) async {
    await _bindSession();
    _prefetchHome = home;
    final pending = <SushiRow>[];
    for (final row in sushiHomePrefetchPlan(home)) {
      if (await _store.readTitle(row.tmdbId, sushiKindToWire(row.kind)) == null) {
        pending.add(row);
      }
    }
    _queue = pending;
    unawaited(_pump());
  }

  /// R-CACHE-3 / R-SCHED-3: drop remaining P2 work (app background).
  void cancelPrefetch() {
    _epoch++;
    _queue = [];
  }

  /// After resume: retry last home plan, skip rows already cached.
  void resumePrefetch() {
    final home = _prefetchHome;
    if (home == null || home.isEmpty) return;
    unawaited(prefetchVisibleHome(home));
  }

  Future<void> _bindSession() async {
    final getOwner = sessionOwner;
    if (getOwner == null) return;
    final inFlight = _bindInFlight;
    if (inFlight != null) {
      await inFlight.future;
      return;
    }
    final done = Completer<void>();
    _bindInFlight = done;
    try {
      final owner = await getOwner();
      final stored = readPersistedOwner != null ? await readPersistedOwner!() : '';
      if (owner.isEmpty) {
        // Logout clears the stamp first. A transient `/initbot` ERR must not
        // wipe rails while the previous identity's stamp is still on disk.
        if (stored.isNotEmpty) {
          debugPrint('[sushi] catalog bind: empty owner, keep stored rows');
          return;
        }
        await _wipeCatalogRows();
        return;
      }
      if (owner == stored) return;
      debugPrint('[sushi] catalog session mismatch — wiping');
      await _wipeCatalogRows();
      await persistOwner?.call(owner);
    } finally {
      done.complete();
      if (identical(_bindInFlight, done)) _bindInFlight = null;
    }
  }

  Future<T> _exclusiveRead<T>(Future<T> Function() run) async {
    _p0++;
    try {
      await _bindSession();
      await _waitIdle();
      return await run();
    } finally {
      _p0--;
      unawaited(_pump());
    }
  }

  Future<void> _waitIdle() async {
    final pending = _busyDone;
    if (pending != null) await pending.future;
  }

  Future<void> _pump() async {
    if (_busy || _p0 > 0 || _queue.isEmpty) return;
    _busy = true;
    final done = Completer<void>();
    _busyDone = done;
    final epoch = _epoch;
    try {
      while (_queue.isNotEmpty && _p0 == 0 && epoch == _epoch) {
        final row = _queue.removeAt(0);
        final kind = sushiKindToWire(row.kind);
        if (await _store.readTitle(row.tmdbId, kind) != null) continue;
        debugPrint('[sushi] prefetch tmdb=${row.tmdbId}');
        final live = await _fetchItem(tmdbId: row.tmdbId, kind: kind);
        if (live != null && sushiItemResPlayable(live)) {
          await _store.writeTitle(live);
          onTitleCached?.call(live);
        }
        if (_prefetchGap > Duration.zero && _queue.isNotEmpty && _p0 == 0 && epoch == _epoch) {
          await _sleep(_prefetchGap);
        }
      }
    } finally {
      _busy = false;
      _busyDone = null;
      done.complete();
    }
  }
}
