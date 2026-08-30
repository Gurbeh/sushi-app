import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_staged_detail_load.dart';
import 'package:fladder/oxplayer/oxplayer_playback_prefetch.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_media_variant.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

part 'movies_details_provider.g.dart';

@riverpod
class MovieDetails extends _$MovieDetails {
  int _loadGeneration = 0;

  late final JellyService api = ref.read(jellyApiProvider);

  @override
  MovieModel? build(String arg) => null;

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    Future<Response?> load() async {
      try {
        final loadGen = ++_loadGeneration;
        void apply(MovieModel? next) {
          if (loadGen != _loadGeneration) return;
          state = next;
        }

        if (item is MovieModel) {
          apply(state ?? item);
        }

        if (SushiConfig.isEnabled) {
          if (item is! MovieModel) return null;
          final tmdbId = sushiTmdbIdFromItemId(item.id);
          if (tmdbId == null) return null;

          final catalog = ref.read(sushiCatalogControllerProvider);
          final cached = await catalog.peekTitle(tmdbId: tmdbId, kind: SushiKind.movie);
          if (cached?.page != null) {
            final painted = sushiEnrichMovieModel(item, cached!.page!, cached.files);
            apply(painted);
            sushiPlayWarmup.scheduleFromStreams(painted.mediaStreams);
            unawaited(_sushiRefreshMovie(item, tmdbId, loadGen));
            return null;
          }
          await _sushiRefreshMovie(item, tmdbId, loadGen);
          return null;
        }

        if (OxplayerConfig.isEnabled) {
          // Disk SWR: MediaSources → Play button before network round-trip.
          final cached = await oxLoadCachedLibraryItemDetails(ref, item.id);
          if (cached != null && cached.model is MovieModel) {
            final cachedMovie = (cached.model as MovieModel).copyWith(
              related: state?.related ?? const [],
              seerrRelated: state?.seerrRelated ?? const [],
              seerrRecommended: state?.seerrRecommended ?? const [],
              specialFeatures: state?.specialFeatures ?? const [],
            );
            apply(oxplayerPrepareMovieMediaStreams(cachedMovie, ref) ?? cachedMovie);
          }

          final core = await oxFetchMovieCoreState(ref, item, state);
          if (core == null) return null;
          var playable = oxplayerPrepareMovieMediaStreams(core, ref) ?? core;
          apply(playable);
          OxplayerPlaybackPrefetch.scheduleForMovie(ref.read, playable);

          oxPrefetchMovieSeerrRatings(ref, item.id, core.tmdbId);

          unawaited(_oxContinueMovieLoad(item.id, loadGen));
          return null;
        }

        final newState = await oxFetchMovieCoreState(ref, item, state);
        if (newState == null) return null;
        apply(newState);

        oxPrefetchMovieSeerrRatings(ref, item.id, newState.tmdbId);

        final supplementary = await oxLoadMovieSupplementaryPhase(ref, item.id, newState);
        var merged = oxMergeMovieSupplementary(
          newState,
          related: supplementary.related,
          seerrRelated: supplementary.seerrRelated,
          seerrRecommended: supplementary.seerrRecommended,
          seerrUrl: supplementary.seerrUrl,
          specialFeatures: supplementary.specialFeatures,
        );
        if (OxplayerConfig.isEnabled) {
          merged = oxplayerPrepareMovieMediaStreams(merged, ref) ?? merged;
        }
        apply(merged);
        return null;
      } catch (e) {
        return null;
      }
    }

    if (OxplayerConfig.isEnabled) {
      return OxplayerScreenTelemetry.trackLoad(
        screen: 'movie_detail',
        phase: 'fetch',
        load: load,
      );
    }
    return load();
  }

  Future<void> _sushiRefreshMovie(MovieModel item, int tmdbId, int loadGen) async {
    try {
      final snap = await ref.read(sushiCatalogControllerProvider).openTitle(
            tmdbId: tmdbId,
            kind: SushiKind.movie,
          );
      if (loadGen != _loadGeneration) return;
      if (snap.page == null) {
        log('[sushi] movie details: itemRes null tmdbId=$tmdbId');
        return;
      }
      state = sushiEnrichMovieModel(item, snap.page!, snap.files);
      sushiPlayWarmup.scheduleFromStreams(state?.mediaStreams);
    } finally {
      // Play/Request are only decidable once this has run (ADR 0014) — mark it so the screen can
      // stop showing a placeholder. Not on a superseded load.
      if (loadGen == _loadGeneration) {
        ref.read(sushiTitleResolvedProvider.notifier).markResolved(item.id);
      }
    }
  }

  Future<void> _oxContinueMovieLoad(String itemId, int loadGen) async {
    try {
      final base = state;
      if (base == null || loadGen != _loadGeneration) return;

      final supplementary = await oxLoadMovieSupplementaryPhase(ref, itemId, base);
      if (loadGen != _loadGeneration) return;

      var merged = oxMergeMovieSupplementary(
        base,
        related: supplementary.related,
        seerrRelated: supplementary.seerrRelated,
        seerrRecommended: supplementary.seerrRecommended,
        seerrUrl: supplementary.seerrUrl,
        specialFeatures: supplementary.specialFeatures,
      );
      merged = oxplayerPrepareMovieMediaStreams(merged, ref) ?? merged;
      state = merged;
    } catch (e) {
      log("Error loading staged movie details: $e");
    }
  }

  void setMediaStreamHelper(MediaStreamsModel changed) {
    state = state?.copyWith(mediaStreams: changed);
    sushiPlayWarmup.scheduleFromStreams(changed);
  }

  /// Local UserData patch after playback stop — avoids waiting on a stale post-play refetch.
  void patchUserData(UserData userData) {
    final current = state;
    if (current == null) return;
    // Invalidate in-flight fetchDetails from post-play (often started before stop persisted).
    _loadGeneration++;
    state = current.copyWith(userData: userData);
  }
}
