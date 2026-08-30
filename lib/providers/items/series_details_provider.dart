import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/ox_series_details_loader.dart';
import 'package:fladder/oxplayer/ox_staged_detail_load.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/oxplayer/oxplayer_playback_prefetch.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

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

        if (SushiConfig.isEnabled) {
          if (seriesModel is! SeriesModel) return null;
          final tmdbId = sushiTmdbIdFromItemId(seriesModel.id);
          if (tmdbId == null) return null;
          final catalog = ref.read(sushiCatalogControllerProvider);
          final cached = await catalog.peekTitle(tmdbId: tmdbId, kind: SushiKind.series);
          if (cached?.page != null) {
            var painted = sushiEnrichSeriesModel(seriesModel, cached!.page!);
            if (cached.files.isNotEmpty) {
              painted = sushiApplySeriesFiles(painted, cached.files);
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
        }

        if (OxplayerConfig.isEnabled) {
          final catalogPrefetch = oxFetchSeriesCatalogBySeason(
            ref.read(jellyApiProvider),
            seriesModel.id,
          );

          // Catalog = playable episodes. Apply before core so Play is not blocked on item JSON.
          // Chopper disk SWR makes seasons/episodes near-instant on revisit.
          final catalogBase = state;
          if (catalogBase != null) {
            final withCatalog = await oxLoadSeriesCatalogPhase(
              ref,
              catalogBase,
              seriesModel.id,
              prefetchCatalog: catalogPrefetch,
            );
            apply(withCatalog);
            OxplayerPlaybackPrefetch.scheduleForSeries(ref.read, withCatalog);
          }

          final core = await oxFetchSeriesCoreState(ref, seriesModel, state);
          if (core == null) {
            if (state == null) return null;
          } else {
            apply(core);
          }

          if (oxSeerrRatingsMissingRt(ref.read(oxLibraryItemRatingsProvider(seriesModel.id)))) {
            oxPrefetchSeerrTvRatings(ref, seriesModel.id, state?.tmdbId);
          }

          unawaited(_oxContinueSeriesSupplementary(seriesModel.id, loadGen));
          return null;
        }

        final newState = await oxFetchSeriesCoreState(ref, seriesModel, state);
        if (newState == null) return null;
        apply(newState);

        if (OxplayerEnv.isEnabled &&
            oxSeerrRatingsMissingRt(ref.read(oxLibraryItemRatingsProvider(seriesModel.id)))) {
          oxPrefetchSeerrTvRatings(ref, seriesModel.id, newState.tmdbId);
        }

        final withCatalog = await oxLoadSeriesCatalogPhase(ref, newState, seriesModel.id);
        apply(withCatalog);

        final supplementary = await oxLoadSeriesSupplementaryPhase(ref, seriesModel.id, withCatalog);
        apply(
          oxMergeSeriesSupplementary(
            withCatalog,
            related: supplementary.related,
            seerrRelated: supplementary.seerrRelated,
            seerrRecommended: supplementary.seerrRecommended,
            seerrUrl: supplementary.seerrUrl,
            specialFeatures: supplementary.specialFeatures,
          ),
        );
        return null;
      } catch (e) {
        log("Error fetching series details: $e");
        return null;
      }
    }

    if (OxplayerConfig.isEnabled) {
      return OxplayerScreenTelemetry.trackLoad(
        screen: 'series_detail',
        phase: 'fetch',
        load: load,
      );
    }
    return load();
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
      var files = snap.files;
      if (playEpisodeId != null && playEpisodeId != firstEpisodeId) {
        files = await catalog.openFiles(episodeId: playEpisodeId);
        if (loadGen != _loadGeneration) return;
      }
      state = sushiApplySeriesFiles(next, files);
      sushiPlayWarmup.scheduleFromStreams(
        (state?.selectedEpisode ?? state?.nextUp)?.mediaStreams,
      );
    } finally {
      // Play/Request are only decidable once this has run (ADR 0014). Not on a superseded load.
      if (loadGen == _loadGeneration) {
        ref.read(sushiTitleResolvedProvider.notifier).markResolved(seriesModel.id);
      }
    }
  }

  Future<void> _oxContinueSeriesSupplementary(String seriesId, int loadGen) async {
    try {
      final base = state;
      if (base == null || loadGen != _loadGeneration) return;

      final supplementary = await oxLoadSeriesSupplementaryPhase(ref, seriesId, base);
      if (loadGen != _loadGeneration) return;
      state = oxMergeSeriesSupplementary(
        base,
        related: supplementary.related,
        seerrRelated: supplementary.seerrRelated,
        seerrRecommended: supplementary.seerrRecommended,
        seerrUrl: supplementary.seerrUrl,
        specialFeatures: supplementary.specialFeatures,
      );
    } catch (e) {
      log("Error loading staged series details: $e");
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
}
