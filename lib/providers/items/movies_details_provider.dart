import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

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
      } catch (e) {
        return null;
      }
    }

    return SushiScreenTelemetry.trackLoad(
      screen: 'movie_detail',
      phase: 'fetch',
      load: load,
    );
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
      if (loadGen == _loadGeneration) {
        ref.read(sushiTitleResolvedProvider.notifier).markResolved(item.id);
      }
    }
  }

  void setMediaStreamHelper(MediaStreamsModel changed) {
    state = state?.copyWith(mediaStreams: changed);
    sushiPlayWarmup.scheduleFromStreams(changed);
  }

  void patchUserData(UserData userData) {
    final current = state;
    if (current == null) return;
    _loadGeneration++;
    state = current.copyWith(userData: userData);
  }
}
