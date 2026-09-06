import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';

/// Fladder falls back to the first episode when none are playable; OX hides play instead.
EpisodeModel? sushiSeriesPlayableNextUp(SeriesModel? series) {
  if (series == null) return null;
  
  return series.availableEpisodes?.nextUp;
}
