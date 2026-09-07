import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/refresh_after_watch_state.dart';

/// Mark every available episode in the season. Season catalog ids are not
/// what next-up / played flags match (`sushi_ep_*`).
Future<void> sushiSeasonMarkPlayed(WidgetRef ref, SeasonModel season, bool played) async {
  final episodeIds = [
    for (final episode in season.episodes)
      if (episode.status == EpisodeStatus.available) episode.id,
  ];
  if (episodeIds.isEmpty) {
    await ref.read(userProvider.notifier).markAsPlayed(played, season.id);
  } else {
    for (final id in episodeIds) {
      await ref.read(userProvider.notifier).markAsPlayed(played, id);
    }
  }
  await refreshAfterWatchStateChange(ref, season);
}
