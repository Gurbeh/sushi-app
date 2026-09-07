import 'package:collection/collection.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_next_up.dart';

/// Series with no watched or in-progress episode — user must pick season + episode first.
bool sushiSeriesNeedsEpisodePick(SeriesModel? series) {
  if (series == null) return false;
  final episodes = series.availableEpisodes;
  if (episodes == null || episodes.isEmpty) return false;
  return !episodes.any((episode) => episode.userData.played || episode.userData.progress != 0);
}

class SushiSeriesPickerSeason {
  const SushiSeriesPickerSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodes,
  });

  final int seasonNumber;
  final String name;
  final List<EpisodeModel> episodes;
}

List<SushiSeriesPickerSeason> sushiSeriesPickerSeasons(SeriesModel series) {
  final episodes = series.availableEpisodes?.where((episode) => episode.season > 0).toList() ?? [];
  if (episodes.isEmpty) return const [];

  final bySeason = episodes.episodesBySeason;
  return bySeason.entries
      .map((entry) {
        final seasonMeta = series.seasons?.firstWhereOrNull((season) => season.season == entry.key);
        final name = _oxPickerSeasonName(seasonMeta, entry.key);
        final seasonEpisodes = entry.value.where((episode) => episode.playAble).toList();
        return SushiSeriesPickerSeason(
          seasonNumber: entry.key,
          name: name,
          episodes: seasonEpisodes,
        );
      })
      .where((season) => season.episodes.isNotEmpty)
      .toList();
}

String _oxPickerSeasonName(SeasonModel? seasonMeta, int seasonNumber) {
  if (seasonMeta != null) {
    if (seasonMeta.seasonName.isNotEmpty) return seasonMeta.seasonName;
    if (seasonMeta.name.isNotEmpty) return seasonMeta.name;
  }
  return seasonNumber.toString();
}

/// Header Play on series detail follows watch progress — not row focus.
/// Never-watched → first episode. In-progress → that episode. Finished → next.
EpisodeModel? sushiSeriesDetailPlayTarget(SeriesModel? series) {
  if (series == null) return null;
  return sushiSeriesPlayableNextUp(series);
}
