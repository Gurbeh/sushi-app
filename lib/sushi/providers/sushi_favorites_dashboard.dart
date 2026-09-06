import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/sushi/sushi_favourites_feed.dart';

const _dashboardFavoritesLimit = 16;

class SushiFavoritesDashboardData {
  const SushiFavoritesDashboardData({this.items = const []});

  final List<ItemBaseModel> items;

  static const empty = SushiFavoritesDashboardData();
}

/// Favorites row parsed from GET /Users/{id}/Home/Feed (no extra HTTP on home).
final sushiFavoritesDashboardFeedProvider = StateProvider<SushiFavoritesDashboardData?>((ref) => null);

/// True after home feed applied favorites data.
final sushiFavoritesFeedHandledProvider = StateProvider<bool>((ref) => false);

void sushiApplyFavoritesFromHomeFeedRef(Ref ref, SushiFavoritesDashboardData data) {
  ref.read(sushiFavoritesDashboardFeedProvider.notifier).state = data;
  ref.read(sushiFavoritesFeedHandledProvider.notifier).state = true;
}

void sushiResetFavoritesHomeFeedRef(Ref ref) {
  ref.read(sushiFavoritesDashboardFeedProvider.notifier).state = null;
  ref.read(sushiFavoritesFeedHandledProvider.notifier).state = false;
}

/// Fallback when Home/Feed omits Favorites (older API).
final sushiFavoritesDashboardProvider = FutureProvider<SushiFavoritesDashboardData>((ref) async {
  

  final feed = await SushiFavoritesFeed.fetch(ref);
  if (feed == null) return SushiFavoritesDashboardData.empty;

  final items = feed.favourites.values
      .expand((list) => list)
      .take(_dashboardFavoritesLimit)
      .toList();
  if (items.isEmpty) return SushiFavoritesDashboardData.empty;
  return SushiFavoritesDashboardData(items: items);
});
