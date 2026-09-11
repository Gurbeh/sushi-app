import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';

final seriesDetailsProvider =
    StateNotifierProvider.autoDispose.family<SeriesDetailViewNotifier, SeriesModel?, String>((ref, id) {
  return SeriesDetailViewNotifier(ref);
});

class SeriesDetailViewNotifier extends StateNotifier<SeriesModel?> {
  SeriesDetailViewNotifier(this.ref) : super(null);

  final Ref ref;
  int _loadGeneration = 0;

  Future<Response?> fetchDetails(ItemBaseModel seriesModel) async {
    Future<Response?> load() async {
      try {
        final loadGen = ++_loadGeneration;
        void apply(SeriesModel? next) {
          if (loadGen != _loadGeneration) return;
          state = next;
        }

        if (seriesModel is SeriesModel) {
          apply(state ?? seriesModel);
        }

        if (seriesModel is! SeriesModel) return null;
        final tmdbId = sushiTmdbIdFromItemId(seriesModel.id);
        if (tmdbId == null) return null;
        final catalog = ref.read(sushiCatalogControllerProvider);
        final cached = await catalog.peekTitle(tmdbId: tmdbId, kind: SushiKind.series);
        if (cached?.page != null) {
          var painted = sushiEnrichSeriesModel(seriesModel, cached!.page!);
          painted = await _paintWatchState(
            painted,
            files: cached.filesRes,
            filesEpisodeId: cached.page!.episodes.firstOrNull?.episodeId,
          );
          if (cached.files.isNotEmpty) {
            painted = sushiApplySeriesFiles(
              painted,
              cached.files,
              preferredFileId: cached.lastFileId,
            );
            sushiPlayWarmup.scheduleFromStreams(
              (painted.selectedEpisode ?? painted.nextUp)?.mediaStreams,
            );
          }
          apply(painted);
          unawaited(_sushiRefreshSeries(seriesModel, tmdbId, loadGen));
          return null;
        }
        await _sushiRefreshSeries(seriesModel, tmdbId, loadGen);
        return null;
      } catch (e) {
        log("Error fetching series details: $e");
        return null;
      }
    }

    return SushiScreenTelemetry.trackLoad(
      screen: 'series_detail',
      phase: 'fetch',
      load: load,
    );
  }

  Future<void> _sushiRefreshSeries(SeriesModel seriesModel, int tmdbId, int loadGen) async {
    try {
      final catalog = ref.read(sushiCatalogControllerProvider);
      final snap = await catalog.openTitle(tmdbId: tmdbId, kind: SushiKind.series);
      if (loadGen != _loadGeneration) return;
      if (snap.page == null) {
        log('[sushi] series details: itemRes null tmdbId=$tmdbId');
        return;
      }
      var next = sushiEnrichSeriesModel(seriesModel, snap.page!);
      final playTarget = next.selectedEpisode ?? next.nextUp;
      final playEpisodeId = playTarget == null ? null : sushiEpisodeIdFromItemId(playTarget.id);
      final firstEpisodeId = snap.page!.episodes.firstOrNull?.episodeId;
      var files = snap.filesRes;
      if (playEpisodeId != null && playEpisodeId != firstEpisodeId) {
        files = await catalog.openFiles(episodeId: playEpisodeId);
        if (loadGen != _loadGeneration) return;
      }
      next = await _paintWatchState(
        next,
        files: files,
        filesEpisodeId: playEpisodeId,
      );
      state = sushiApplySeriesFiles(next, files.files, preferredFileId: files.lastFileId);
      sushiPlayWarmup.scheduleFromStreams(
        (state?.selectedEpisode ?? state?.nextUp)?.mediaStreams,
      );
      if (loadGen == _loadGeneration) {
        ref.read(sushiTitleResolvedProvider.notifier).markResolved(seriesModel.id);
      }
    } catch (e, s) {
      log('[sushi] series details: refresh failed tmdbId=$tmdbId: $e', stackTrace: s);
    }
  }

  void updateEpisodeInfo(EpisodeModel episode) {
    final index = state?.availableEpisodes?.indexWhere((e) => e.id == episode.id);

    final newList = state?.availableEpisodes?.toList() ?? [];
    newList[index ?? 0] = episode;

    if (index != null) {
      state = state?.copyWith(
        availableEpisodes: newList,
      );
    }
    sushiPlayWarmup.scheduleFromStreams(episode.mediaStreams);
  }

  void setCurrentEpisode(EpisodeModel? episodeModel) {
    state = state?.copyWith(selectedEpisode: episodeModel);
    sushiPlayWarmup.scheduleFromStreams(episodeModel?.mediaStreams);
  }

  void mergeSeason(int seasonNo, List<EpisodeModel> loaded) {
    final current = state;
    if (current == null) return;
    state = sushiMergeSeasonEpisodes(current, seasonNo, loaded);
  }

  Future<List<EpisodeModel>> loadSeason(int seasonNo) async {
    final current = state;
    if (current == null) return const [];
    final tmdbId = sushiTmdbIdFromItemId(current.id);
    if (tmdbId == null) return const [];
    final season = current.seasons?.firstWhereOrNull((s) => s.season == seasonNo);
    if (season != null &&
        season.episodeCount > 0 &&
        season.episodes.length >= season.episodeCount) {
      return season.episodes;
    }
    final wire = await ref.read(sushiCatalogControllerProvider).openSeason(
          tmdbId: tmdbId,
          kind: SushiKind.series,
          seasonNo: seasonNo,
        );
    final loaded = sushiEpisodesFromWire(current, wire);
    mergeSeason(seasonNo, loaded);
    return loaded;
  }

  Future<SeriesModel> _paintWatchState(
    SeriesModel series, {
    SushiFilesRes? files,
    int? filesEpisodeId,
  }) async {
    final tmdbId = sushiTmdbIdFromItemId(series.id);
    final resume = tmdbId == null
        ? null
        : await sushiContinueFind(tmdbId: tmdbId, kind: SushiKind.series);
    return sushiPaintSeriesWatchState(
      series,
      playedIds: ref.read(sushiCatalogItemFlagsProvider).playedIds,
      resume: resume,
      files: files,
      filesEpisodeId: filesEpisodeId,
    );
  }
}
