import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_home_feed.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_home_rails_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

final dashboardProvider = StateNotifierProvider<DashboardNotifier, HomeModel>((ref) {
  return DashboardNotifier(ref);
});

class DashboardNotifier extends StateNotifier<HomeModel> {
  DashboardNotifier(this.ref) : super(HomeModel());

  final Ref ref;
  bool _sushiHomeQueued = false;
  bool _sushiHomeQueuedForce = false;
  bool _sushiHomeInFlight = false;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<void> fetchNextUpAndResume({bool force = false}) async {
    if (SushiConfig.isEnabled) {
      // Each call is a real Telegram bot round-trip, not a cheap HTTP GET — never let two
      // overlap (e.g. pull-to-refresh landing while an initial fetch is still in flight).
      // Queue a follow-up instead of dropping: refreshOnStart often races /initbot, and dropping
      // the second call leaves rails empty until the user pulls again.
      if (_sushiHomeInFlight) {
        _sushiHomeQueued = true;
        _sushiHomeQueuedForce |= force;
        return;
      }
      _sushiHomeInFlight = true;
      try {
        var runForce = force;
        do {
          _sushiHomeQueued = false;
          final extra = _sushiHomeQueuedForce;
          _sushiHomeQueuedForce = false;
          await _fetchSushiHome(force: runForce || extra);
          runForce = false;
        } while (_sushiHomeQueued);
      } finally {
        _sushiHomeInFlight = false;
        state = state.copyWith(loading: false, loaded: true);
      }
      return;
    }
    if (OxplayerConfig.isEnabled && state.loaded) return;

    Future<void> load() async {
      if (state.loading) return;
      state = state.copyWith(loading: true);

      final viewTypes =
          ref.read(viewsProvider.select((value) => value.dashboardViews)).map((e) => e.collectionType).toSet();
      const limit = 16;

      final imagesToFetch = {
        ImageType.logo,
        ImageType.primary,
        ImageType.backdrop,
        ImageType.banner,
      }.toList();

      final fieldsToFetch = {
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
        ItemFields.airtime,
      };

      final activeProgramsFuture = viewTypes.contains(CollectionType.livetv)
          ? _fetchActivePrograms(limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final resumeVideoFuture = viewTypes.contains(CollectionType.movies) ||
              viewTypes.contains(CollectionType.tvshows)
          ? _fetchResumeItems(mediaTypes: [MediaType.video], imagesToFetch: imagesToFetch, fieldsToFetch: fieldsToFetch, limit: limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final resumeAudioFuture = viewTypes.contains(CollectionType.music)
          ? _fetchResumeItems(mediaTypes: [MediaType.audio], imagesToFetch: imagesToFetch, fieldsToFetch: fieldsToFetch, limit: limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final resumeBooksFuture = viewTypes.contains(CollectionType.books)
          ? _fetchResumeItems(mediaTypes: [MediaType.book], imagesToFetch: imagesToFetch, fieldsToFetch: fieldsToFetch, limit: limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final nextUpFuture = _fetchNextUp(fieldsToFetch);

      final results = await Future.wait<Object>([
        activeProgramsFuture,
        resumeVideoFuture,
        resumeAudioFuture,
        resumeBooksFuture,
        nextUpFuture,
      ]);

      state = state.copyWith(
        activePrograms: results[0] as List<ItemBaseModel>,
        resumeVideo: results[1] as List<ItemBaseModel>,
        resumeAudio: results[2] as List<ItemBaseModel>,
        resumeBooks: results[3] as List<ItemBaseModel>,
        nextUp: results[4] as List<ItemBaseModel>,
        loading: false,
        loaded: true,
      );
    }

    if (OxplayerConfig.isEnabled) {
      await OxplayerScreenTelemetry.trackLoad(screen: 'home', phase: 'dashboard', load: load);
      return;
    }
    await load();
  }

  Future<List<ItemBaseModel>> _fetchActivePrograms(int limit) async {
    var channels = (await api.liveTvChannelsGet(limit: limit))
            .body
            ?.items
            ?.map((e) => ChannelModel.fromBaseDto(e, ref))
            .toList() ??
        <ChannelModel>[];

    channels = await Future.wait(
      channels.map(
        (e) async {
          final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(e);
          return e.copyChannelWith(programs: programs);
        },
      ),
    );

    return channels;
  }

  Future<List<ItemBaseModel>> _fetchNextUp(Set<ItemFields> fieldsToFetch) async {
    final response = await api.showsNextUpGet(
      nextUpDateCutoff: DateTime.now().subtract(
        ref.read(clientSettingsProvider.select((value) => value.nextUpDateCutoff ?? const Duration(days: 28))),
      ),
      fields: fieldsToFetch.toList(),
    );

    return response.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? const [];
  }

  Future<List<ItemBaseModel>> _fetchResumeItems({
    required List<MediaType> mediaTypes,
    required List<ImageType> imagesToFetch,
    required Set<ItemFields> fieldsToFetch,
    required int limit,
  }) async {
    final response = await api.usersUserIdItemsResumeGet(
      enableImageTypes: imagesToFetch,
      fields: fieldsToFetch.toList(),
      mediaTypes: mediaTypes,
      enableTotalRecordCount: false,
      limit: limit,
    );

    return response.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? const [];
  }

  /// Sushi: paint cache first, then `/home` only when stale or forced (docs/11 §3).
  Future<void> _fetchSushiHome({bool force = false}) async {
    final catalog = ref.read(sushiCatalogControllerProvider);
    final cached = await catalog.peekHome();
    if (cached != null && !cached.isEmpty) {
      await _applySushiHome(cached);
    }

    if (!force && cached != null && !cached.isEmpty && !await catalog.homeIsStale()) {
      debugPrint('[sushi] home cache hit seq=${cached.seq}');
      return;
    }

    if (cached == null || cached.isEmpty) {
      state = state.copyWith(loading: true);
    }

    final live = await catalog.refreshHome(force: true);
    if (live == null) return;
    debugPrint(
      '[sushi] home network slider=${live.slider.length} '
      'series trending=${live.seriesTrending.length}',
    );
    await _applySushiHome(live);
  }

  Future<void> _applySushiHome(SushiCachedHome home) async {
    List<ItemBaseModel> map(List<SushiRow> rows) => rows.map(sushiRowToItemBaseModel).toList();
    final slider = map(home.slider);
    oxApplySushiHomeRailsRef(
      ref,
      SushiHomeRailsData(
        slider: slider,
        mostWatched: map(home.mostWatched),
        trending: map(home.trending),
        seriesMostWatched: map(home.seriesMostWatched),
        seriesTrending: map(home.seriesTrending),
      ),
    );
    final resume = await sushiContinueLoad();
    state = state.copyWith(nextUp: slider, resumeVideo: resume);
    unawaited(ref.read(sushiCatalogControllerProvider).prefetchVisibleHome(home));
  }

  /// Re-reads the client-owned continue-watching store into [state] — no `/home` bot round-trip.
  /// Driven by the poster menu's "Add / Remove Continue Watching" toggle on the home rows.
  Future<void> reloadSushiContinue() async {
    if (!SushiConfig.isEnabled) return;
    state = state.copyWith(resumeVideo: await sushiContinueLoad());
  }

  void applyOxHomeFeed(OxHomeFeedDashboard feed) {
    state = state.copyWith(
      nextUp: feed.nextUp,
      resumeVideo: feed.resumeVideo,
      loading: false,
      loaded: true,
    );
  }

  void clear() {
    state = HomeModel();
  }
}
