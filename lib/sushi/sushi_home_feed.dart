import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/sushi/sushi_api_disk_cache.dart';
import 'package:fladder/sushi/sushi_catalog_http.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_view_labels.dart';
import 'package:fladder/sushi/providers/sushi_favorites_dashboard.dart';
import 'package:fladder/sushi/providers/sushi_watchlist_dashboard.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// Dashboard slider data from GET /Users/{id}/Home/Feed.
class SushiHomeFeedDashboard {
  const SushiHomeFeedDashboard({
    this.nextUp = const [],
    this.resumeVideo = const [],
  });

  final List<ItemBaseModel> nextUp;
  final List<ItemBaseModel> resumeVideo;
}

/// Parsed home feed (views + shelves + slider rails + watch later).
class SushiHomeFeedResult {
  const SushiHomeFeedResult({
    required this.views,
    required this.dashboard,
    required this.watchLater,
    required this.favorites,
    required this.favoritesInFeed,
  });

  final List<ViewModel> views;
  final SushiHomeFeedDashboard dashboard;
  final SushiWatchlistDashboardData watchLater;
  final SushiFavoritesDashboardData favorites;
  /// False when the API omits [Favorites] (older server) so the client can fall back.
  final bool favoritesInFeed;
}

abstract final class SushiHomeFeed {
  static const _feedLimit = 16;

  static Uri? _feedUri(Ref ref) {
    final base = SushiEnv.apiBaseUrl?.trim();
    final userId = ref.read(userProvider)?.id;
    if (base == null || base.isEmpty || userId == null || userId.isEmpty) {
      return null;
    }
    return Uri.parse('$base/Users/$userId/Home/Feed').replace(
      queryParameters: {'limit': '$_feedLimit'},
    );
  }

  static String? _cacheKey(Ref ref, Uri uri) {
    final userId = ref.read(userProvider)?.id;
    if (userId == null || userId.isEmpty) return null;
    return SushiApiDiskCache.key(userId: userId, method: 'GET', uri: uri);
  }

  /// Disk SWR: last successful Home/Feed body (survives kill / dispose).
  static Future<SushiHomeFeedResult?> loadCached(Ref ref) async {
    final uri = _feedUri(ref);
    if (uri == null) return null;
    final key = _cacheKey(ref, uri);
    if (key == null) return null;
    final entry = await SushiApiDiskCache.read(key);
    if (entry == null || entry.body.isEmpty) return null;
    return _parseBodyString(entry.body, ref);
  }

  /// One HTTP round-trip for views, latest shelves, next up, continue watching, and watch later.
  /// On 200, writes disk cache for the next cold open.
  static Future<SushiHomeFeedResult?> fetch(Ref ref) async {
    final uri = _feedUri(ref);
    if (uri == null) return null;
    final headers = sushiCatalogApiHeaders(ref);

    http.Response response;
    try {
      response = await http.get(uri, headers: headers);
    } catch (_) {
      return null;
    }

    if (response.statusCode == 404 || response.statusCode == 405) {
      return null;
    }
    if (response.statusCode != 200) {
      return null;
    }

    final key = _cacheKey(ref, uri);
    if (key != null && response.body.isNotEmpty) {
      await SushiApiDiskCache.write(
        key,
        SushiApiDiskCacheEntry(
          savedAt: DateTime.now().toUtc(),
          statusCode: response.statusCode,
          body: response.body,
          headers: {'content-type': response.headers['content-type'] ?? 'application/json'},
        ),
      );
    }

    return _parseBodyString(response.body, ref);
  }

  static SushiHomeFeedResult? _parseBodyString(String raw, Ref ref) {
    try {
      final body = jsonDecode(raw);
      if (body is! Map<String, dynamic>) return null;
      return _parse(body, ref);
    } catch (_) {
      return null;
    }
  }

  static SushiHomeFeedResult _parse(Map<String, dynamic> body, Ref ref) {
    final shelfItemsByParent = <String, List<ItemBaseModel>>{};
    final shelves = body['Shelves'];
    if (shelves is List) {
      for (final shelf in shelves) {
        if (shelf is! Map<String, dynamic>) continue;
        final parentId = shelf['ParentId']?.toString();
        final rawItems = shelf['Items'];
        if (parentId == null || parentId.isEmpty || rawItems is! List) continue;
        shelfItemsByParent[parentId] = rawItems
            .whereType<Map<String, dynamic>>()
            .map((item) => ItemBaseModel.fromBaseDto(BaseItemDto.fromJson(item), ref))
            .toList();
      }
    }

    final rawViews = (body['Views'] as Map<String, dynamic>?)?['Items'];
    final views = <ViewModel>[];
    if (rawViews is List) {
      for (final raw in rawViews) {
        if (raw is! Map<String, dynamic>) continue;
        final view = SushiViewLabels.apply(
          ViewModel.fromBodyDto(BaseItemDto.fromJson(raw), ref),
        );
        views.add(
          view.copyWith(recentlyAdded: shelfItemsByParent[view.id] ?? const []),
        );
      }
    }

    final nextUp = _itemsFromSection(body['NextUp'], ref);
    final resume = _itemsFromSection(body['Resume'], ref);
    final watchLater = _watchLaterFromBody(body['WatchLater'], ref);
    final favoritesInFeed = body.containsKey('Favorites');
    final favorites = favoritesInFeed ? _favoritesFromBody(body['Favorites'], ref) : SushiFavoritesDashboardData.empty;

    return SushiHomeFeedResult(
      views: views,
      dashboard: SushiHomeFeedDashboard(nextUp: nextUp, resumeVideo: resume),
      watchLater: watchLater,
      favorites: favorites,
      favoritesInFeed: favoritesInFeed,
    );
  }

  static void applyWatchLater(Ref ref, SushiWatchlistDashboardData watchLater) {
    sushiApplyWatchlistFromHomeFeedRef(ref, watchLater);
  }

  static void applyFavorites(Ref ref, SushiFavoritesDashboardData favorites) {
    sushiApplyFavoritesFromHomeFeedRef(ref, favorites);
  }

  static void applyDashboard(Ref ref, SushiHomeFeedDashboard dashboard) {
    ref.read(dashboardProvider.notifier).applyOxHomeFeed(dashboard);
  }

  static List<ItemBaseModel> _itemsFromSection(Object? section, Ref ref) {
    if (section is! Map<String, dynamic>) return const [];
    final rawItems = section['Items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map<String, dynamic>>()
        .map((item) => ItemBaseModel.fromBaseDto(BaseItemDto.fromJson(item), ref))
        .toList();
  }

  static SushiWatchlistDashboardData _watchLaterFromBody(Object? section, Ref ref) {
    if (section is! Map<String, dynamic>) return SushiWatchlistDashboardData.empty;
    final playlistId = section['PlaylistId']?.toString();
    final items = _itemsFromSection(section, ref);
    if (items.isEmpty && (playlistId == null || playlistId.isEmpty)) {
      return SushiWatchlistDashboardData.empty;
    }
    return SushiWatchlistDashboardData(playlistId: playlistId, items: items);
  }

  static SushiFavoritesDashboardData _favoritesFromBody(Object? section, Ref ref) {
    final items = _itemsFromSection(section, ref);
    if (items.isEmpty) return SushiFavoritesDashboardData.empty;
    return SushiFavoritesDashboardData(items: items);
  }
}
