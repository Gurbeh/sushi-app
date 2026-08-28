import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/cache/sushi_catalog_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_transport.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_item_transport.dart';

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
typedef SushiHomeFetcher = Future<SushiHomeRes?> Function({required int tab});

/// Client-first cache (docs/11): screens read SQLite, network only updates.
///
/// Cached title → `/files` (lite). Miss → `/item` then `/files`. TMDB-only pages
/// (empty episodes) are never written (R-CACHE-6).
class SushiCatalogController {
  SushiCatalogController(
    this._store, {
    SushiItemFetcher fetchItem = sushiFetchItem,
    SushiFilesFetcher fetchFiles = sushiFetchFiles,
    SushiHomeFetcher fetchHome = sushiFetchHome,
    DateTime Function()? clock,
    Duration prefetchGap = sushiPrefetchGap,
    Future<void> Function(Duration duration)? sleep,
  })  : _fetchItem = fetchItem,
        _fetchFiles = fetchFiles,
        _fetchHome = fetchHome,
        _clock = clock ?? DateTime.now,
        _prefetchGap = prefetchGap,
        _sleep = sleep ?? Future<void>.delayed;

  final SushiCatalogStore _store;
  final SushiItemFetcher _fetchItem;
  final SushiFilesFetcher _fetchFiles;
  final SushiHomeFetcher _fetchHome;
  final DateTime Function() _clock;
  final Duration _prefetchGap;
  final Future<void> Function(Duration duration) _sleep;

  int _p0 = 0;
  int _epoch = 0;
  bool _busy = false;
  Completer<void>? _busyDone;
  List<SushiRow> _queue = [];
  SushiCachedHome? _prefetchHome;

  Future<SushiCachedHome?> peekHome() => _store.readHome();

  Future<bool> homeIsStale() async {
    final home = await _store.readHome();
    if (home == null || home.isEmpty) return true;
    return !_clock().isBefore(home.fetchedAt.add(home.ttl));
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
        slider: [...rail(movies, SushiRailKind.slider), ...rail(series, SushiRailKind.slider)],
        mostWatched: rail(movies, SushiRailKind.mostWatched),
        trending: rail(movies, SushiRailKind.trending),
        seriesMostWatched: rail(series, SushiRailKind.mostWatched),
        seriesTrending: rail(series, SushiRailKind.trending),
        seq: series?.seq ?? movies?.seq ?? 0,
        ttl: Duration(seconds: ttlSeconds > 0 ? ttlSeconds : sushiHomeTtlFallback.inSeconds),
        fetchedAt: _clock(),
      );
      await _store.writeHome(home);
      return home;
    });
  }

  Future<SushiTitleSnapshot?> peekTitle({required int tmdbId, required SushiKind kind}) async {
    final page = await _store.readTitle(tmdbId, sushiKindToWire(kind));
    if (page == null) return null;
    final episodeId = page.episodes.firstOrNull?.episodeId;
    var files = const <SushiFile>[];
    if (episodeId != null && episodeId != 0) {
      files = (await _store.readFiles(episodeId))?.files ?? const [];
    }
    return SushiTitleSnapshot(page: page, files: files, fromCache: true, lite: true);
  }

  /// Paint from [peekTitle] first. This call does the network update.
  Future<SushiTitleSnapshot> openTitle({
    required int tmdbId,
    required SushiKind kind,
    int? episodeId,
    bool force = false,
  }) {
    return _exclusiveRead(() async {
      final cached = await _store.readTitle(tmdbId, sushiKindToWire(kind));
      var page = cached;
      var lite = cached != null && !force;

      if (cached == null || force) {
        final live = await _fetchItem(tmdbId: tmdbId, kind: sushiKindToWire(kind));
        if (live != null) {
          page = live;
          lite = false;
          if (live.episodes.isNotEmpty) await _store.writeTitle(live);
        }
      }

      final epId = episodeId ?? page?.episodes.firstOrNull?.episodeId;
      var files = const <SushiFile>[];
      if (epId != null && epId != 0) {
        files = await openFiles(episodeId: epId, force: force);
      }
      debugPrint('[sushi] title tmdb=$tmdbId lite=$lite fromCache=${cached != null} files=${files.length}');
      return SushiTitleSnapshot(page: page, files: files, fromCache: cached != null, lite: lite);
    });
  }

  Future<List<SushiFile>> openFiles({required int episodeId, bool force = false}) {
    return _exclusiveRead(() async {
      final cached = await _store.readFiles(episodeId);
      if (!force && cached != null && _clock().isBefore(cached.fetchedAt.add(sushiFilesTtl))) {
        debugPrint('[sushi] files cache episode=$episodeId n=${cached.files.length}');
        return cached.files;
      }
      debugPrint('[sushi] files network episode=$episodeId');
      final live = await _fetchFiles(episodeId: episodeId);
      if (live != null) {
        await _store.replaceFiles(episodeId, live.files, _clock());
        return live.files;
      }
      return cached?.files ?? const [];
    });
  }

  /// P2: `/item` only for viewport-ish home cards missing from SQLite (docs/11 §4).
  Future<void> prefetchVisibleHome(SushiCachedHome home) async {
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

  Future<T> _exclusiveRead<T>(Future<T> Function() run) async {
    _p0++;
    try {
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
        if (live != null && live.episodes.isNotEmpty) {
          await _store.writeTitle(live);
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
