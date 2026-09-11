import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_season_user_data.dart';

/// Overlay client watch state onto catalog episodes.
///
/// `/item` has no UserData. Played lives in `/me/item-flags`. Resume lives in
/// the continue-watching store. `nextUp` and the series play button both read
/// [EpisodeModel.userData], so this must run after every enrich.
SeriesModel sushiPaintSeriesWatchState(
  SeriesModel series, {
  Set<String> playedIds = const {},
  SushiContinueEntry? resume,
}) {
  var withResume = sushiAttachResumeEpisode(series, resume);
  final episodes = withResume.availableEpisodes;
  if (episodes == null || episodes.isEmpty) return withResume;

  final painted = [
    for (final episode in episodes)
      episode.copyWith(
        userData: _watchUserData(episode, playedIds: playedIds, resume: resume),
      ),
  ];

  return withResume.copyWith(
    availableEpisodes: painted,
    seasons: [
      for (final season in withResume.seasons ?? const <SeasonModel>[])
        season.copyWith(
          episodes: painted.where((e) => e.season == season.season).toList(),
          userData: sushiSeasonUserDataFromEpisodes(
            painted.where((e) => e.season == season.season),
          ),
        ),
    ],
  );
}

UserData _watchUserData(
  EpisodeModel episode, {
  required Set<String> playedIds,
  SushiContinueEntry? resume,
}) {
  if (playedIds.contains(episode.id)) {
    return episode.userData.copyWith(
      played: true,
      progress: 0,
      playbackPositionTicks: 0,
    );
  }
  if (resume != null && !resume.isFinished && _resumeMatches(episode, resume)) {
    return episode.userData.copyWith(
      played: false,
      progress: resume.progressPct,
      playbackPositionTicks: resume.positionMs * 10000,
    );
  }
  return episode.userData;
}

SeriesModel sushiAttachResumeEpisode(SeriesModel series, SushiContinueEntry? resume) {
  if (resume == null || resume.isFinished) return series;
  final id = resume.episodeItemId;
  if (id == null || id.isEmpty) return series;
  if (series.availableEpisodes?.any((e) => e.id == id) == true) return series;
  final stub = EpisodeModel(
    seriesName: series.name,
    season: resume.season ?? 1,
    episode: resume.episode ?? 1,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'Episode ${resume.episode ?? 1}',
    id: id,
    overview: series.overview,
    parentId: series.id,
    playlistId: null,
    images: series.images,
    childCount: null,
    primaryRatio: 1.78,
    userData: const UserData(),
    parentImages: series.images,
    mediaStreams: MediaStreamsModel(versionStreams: const []),
    canDelete: false,
    canDownload: true,
    jellyType: BaseItemKind.episode,
  );
  return series.copyWith(
    availableEpisodes: [...?series.availableEpisodes, stub],
  );
}

bool _resumeMatches(EpisodeModel episode, SushiContinueEntry resume) {
  final episodeItemId = resume.episodeItemId;
  if (episodeItemId != null && episodeItemId.isNotEmpty) {
    return episode.id == episodeItemId;
  }
  final season = resume.season;
  final number = resume.episode;
  if (season != null && number != null) {
    return episode.season == season && episode.episode == number;
  }
  return false;
}
