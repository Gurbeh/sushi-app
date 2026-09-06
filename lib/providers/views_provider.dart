import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/sushi/sushi_home_detail_prefetch.dart';
import 'package:fladder/sushi/sushi_provider_bots_bootstrap.dart';
import 'package:fladder/sushi/sushi_home_feed.dart';
import 'package:fladder/sushi/sushi_view_labels.dart';
import 'package:fladder/sushi/providers/sushi_favorites_dashboard.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/providers/sushi_watchlist_dashboard.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_views.dart';

//Known supported collection types
const enableCollectionTypes = {
  CollectionType.movies,
  CollectionType.books,
  CollectionType.tvshows,
  CollectionType.homevideos,
  CollectionType.boxsets,
  CollectionType.playlists,
  CollectionType.photos,
  CollectionType.livetv,
  CollectionType.folders,
  CollectionType.music,
  CollectionType.musicvideos,
};

final viewsProvider = StateNotifierProvider<ViewsNotifier, ViewsModel>((ref) {
  return ViewsNotifier(ref);
});

class ViewsNotifier extends StateNotifier<ViewsModel> {
  ViewsNotifier(this.ref) : super(ViewsModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);
  bool _fetchInFlight = false;

  Future<ViewsModel?> fetchViews({bool background = false}) async {
    Future<ViewsModel?> load() async {
      if (_fetchInFlight) return null;
      _fetchInFlight = true;
      try {
        // Sushi: synthetic library views (Movies/Series/Box sets/Playlists) + empty home rails.
        
          final sushiViews = sushiSyntheticViews();
          state = state.copyWith(
            views: sushiViews,
            dashboardViews: const [],
            loading: false,
            loaded: true,
          );
          return state;
        

        final showAllCollections = ref.read(clientSettingsProvider.select((value) => value.showAllCollectionTypes));

        
          var user = ref.read(userProvider);
          if (user?.userConfiguration == null) {
            await ref.read(userProvider.notifier).updateInformation();
          }
          unawaited(ref.read(sushiCatalogItemFlagsProvider.notifier).load());

          // Disk SWR: paint last Home/Feed immediately, then revalidate.
          final cachedFeed = await SushiHomeFeed.loadCached(ref);
          if (cachedFeed != null) {
            _applyHomeFeed(cachedFeed, showAllCollections: showAllCollections);
          }
          final hadDisk = cachedFeed != null;

          final staleRefresh = background && state.loaded;
          if (!staleRefresh && !hadDisk) {
            state = state.copyWith(loading: true);
          }

          final feed = await SushiHomeFeed.fetch(ref);
          if (feed != null) {
            _applyHomeFeed(feed, showAllCollections: showAllCollections);
            return state;
          }
          if (hadDisk) {
            state = state.copyWith(loading: false, loaded: true);
            return state;
          }
        

        final response = await api.usersUserIdViewsGet();
        final createdViews = response.body?.items?.map((e) => ViewModel.fromBodyDto(e, ref)).where((element) {
          return showAllCollections ? true : enableCollectionTypes.contains(element.collectionType);
        });

        List<ViewModel> newList = [];

        if (createdViews != null) {
          
            newList = createdViews.toList();
            _publishViews(newList, loading: true);

            SushiWatchlistDashboardData watchLaterData = SushiWatchlistDashboardData.empty;
            await Future.wait([
              Future.wait(
                newList.map((view) async {
                  final updated = await _fetchRecentlyAdded(view, showAllCollections: showAllCollections);
                  final index = newList.indexWhere((element) => element.id == updated.id);
                  if (index == -1) return;
                  newList[index] = updated;
                }),
              ),
              ref.read(sushiWatchlistDashboardProvider.future).then((data) => watchLaterData = data),
              ref.read(dashboardProvider.notifier).fetchNextUpAndResume(),
            ]);
            sushiApplyWatchlistFromHomeFeedRef(ref, watchLaterData);
          
        }

        state = state.copyWith(
            views: _applyLibraryOrdering(newList),
            dashboardViews: _applyLibraryOrdering(newList
                .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true))
                .toList()),
            loading: false,
            loaded: true);
        return state;
      } finally {
        _fetchInFlight = false;
      }
    }

    
      return SushiScreenTelemetry.trackLoad(screen: 'home', phase: 'views', load: load);
    
    return load();
  }

  void _applyHomeFeed(SushiHomeFeedResult feed, {required bool showAllCollections}) {
    final filtered = feed.views
        .where((v) => showAllCollections || enableCollectionTypes.contains(v.collectionType))
        .toList();
    final ordered = _applyLibraryOrdering(filtered);
    SushiHomeFeed.applyWatchLater(ref, feed.watchLater);
    if (feed.favoritesInFeed) {
      SushiHomeFeed.applyFavorites(ref, feed.favorites);
    } else {
      sushiResetFavoritesHomeFeedRef(ref);
    }
    SushiHomeFeed.applyDashboard(ref, feed.dashboard);
    state = state.copyWith(
      views: ordered,
      dashboardViews: _applyLibraryOrdering(
        ordered
            .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true))
            .toList(),
      ),
      loading: false,
      loaded: true,
    );
    // App enter: start+mute+archive every delivery sender. Prefetch/play await [ensureReady]
    // so copyMessage cannot race ahead of startBot (Telegram 400 chat not found).
    SushiProviderBotsBootstrap.schedule();
    SushiHomeDetailPrefetch.schedule(ref, dashboardViews: state.dashboardViews);
  }

  Future<ViewModel> _fetchRecentlyAdded(ViewModel view, {required bool showAllCollections}) async {
    if (ref.read(userProvider)?.latestItemsExcludes.contains(view.id) == true) return view;
    final recents = await api.usersUserIdItemsLatestGet(
      parentId: view.id,
      imageTypeLimit: 1,
      limit: 16,
      includeItemTypes: (view.collectionType == CollectionType.books && !showAllCollections) ? [BaseItemKind.book] : null,
      enableImageTypes: [
        ImageType.primary,
        ImageType.backdrop,
        ImageType.thumb,
      ],
      fields: [
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
      ],
    );
    return view.copyWith(recentlyAdded: recents.body?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList());
  }

  void _publishViews(List<ViewModel> views, {required bool loading}) {
    state = state.copyWith(
      views: _applyLibraryOrdering(views),
      dashboardViews: _applyLibraryOrdering(
        views
            .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true))
            .toList(),
      ),
      loading: loading,
    );
  }

  List<ViewModel> _applyLibraryOrdering(List<ViewModel> views) {
    final orderedViews = ref.read(userProvider)?.userConfiguration?.orderedViews ?? [];
    if (orderedViews.isEmpty) return SushiViewLabels.applyAll(views);

    final viewMap = {for (var v in views) v.id: v};
    final ordered = <ViewModel>[];

    for (final id in orderedViews) {
      final view = viewMap.remove(id);
      if (view != null) ordered.add(view);
    }
    ordered.addAll(viewMap.values);
    return SushiViewLabels.applyAll(ordered);
  }

  void clear() {
    state = ViewsModel();
  }
}
