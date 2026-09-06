import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:flutter_test/flutter_test.dart';
EpisodeModel _episode({required String id, required int episode}) {
  return EpisodeModel(
    seriesName: 'Show',
    season: 1,
    episode: episode,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'Ep $episode',
    id: id,
    overview: const OverviewModel(),
    parentId: 'series-1',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: null,
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

SeriesModel _series({EpisodeModel? selected, List<EpisodeModel>? episodes}) {
  return SeriesModel(
    originalTitle: '',
    sortName: '',
    status: '',
    name: 'Show',
    id: 'series-1',
    playlistId: null,
    overview: const OverviewModel(),
    parentId: null,
    images: null,
    childCount: null,
    primaryRatio: null,
    userData: const UserData(),
    selectedEpisode: selected,
    availableEpisodes: episodes,
  );
}

void main() {
  test('sushiSeriesDetailPlayTarget prefers selectedEpisode over next up', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep18 = _episode(id: 'ep-18', episode: 18);
    final series = _series(
      selected: ep18,
      episodes: [ep1, ep18],
    );

    expect(sushiSeriesDetailPlayTarget(series, selectedEpisode: ep18)?.id, 'ep-18');
  });

  test('sushiSeriesDetailPlayTarget falls back to next up when none selected', () {
    final ep1 = _episode(id: 'ep-1', episode: 1).copyWith(
      userData: const UserData(progress: 50),
    );
    final ep18 = _episode(id: 'ep-18', episode: 18);
    final series = _series(episodes: [ep1, ep18]);

    expect(sushiSeriesDetailPlayTarget(series)?.id, 'ep-1');
  });

  test('sushiSeriesDetailPlayTarget skips fully watched selected episode', () {
    final ep1 = _episode(id: 'ep-1', episode: 1).copyWith(
      userData: const UserData(played: true),
    );
    final ep2 = _episode(id: 'ep-2', episode: 2);
    final series = _series(selected: ep1, episodes: [ep1, ep2]);

    expect(sushiSeriesDetailPlayTarget(series, selectedEpisode: ep1)?.id, 'ep-2');
  });

  test('sushiSeriesDetailPlayTarget keeps in-progress selected episode', () {
    final ep1 = _episode(id: 'ep-1', episode: 1).copyWith(
      userData: const UserData(progress: 40),
    );
    final ep2 = _episode(id: 'ep-2', episode: 2);
    final series = _series(selected: ep1, episodes: [ep1, ep2]);

    expect(sushiSeriesDetailPlayTarget(series, selectedEpisode: ep1)?.id, 'ep-1');
  });

  test('sushiSeriesDetailPlayTarget returns null until user picks on fresh series', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep2 = _episode(id: 'ep-2', episode: 2);
    final series = _series(episodes: [ep1, ep2]);

    expect(sushiSeriesNeedsEpisodePick(series), isTrue);
    expect(sushiSeriesDetailPlayTarget(series), isNull);
    expect(sushiSeriesDetailPlayTarget(series, selectedEpisode: ep2)?.id, 'ep-2');
  });

  test('sushiSeriesPickerSeasons groups episodes by season', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep2 = _episode(id: 'ep-2', episode: 1).copyWith(season: 2);
    final series = _series(episodes: [ep1, ep2]);

    final seasons = sushiSeriesPickerSeasons(series);
    expect(seasons.length, 2);
    expect(seasons.first.seasonNumber, 1);
    expect(seasons.last.seasonNumber, 2);
  });

  test('sushiSeriesPickerSeasons omits seasons without playable episodes', () {
    final playable = _episode(id: 'ep-1', episode: 1);
    final missing = _episode(id: 'ep-2', episode: 1).copyWith(
      season: 2,
      location: ItemLocation.virtual,
    );
    final series = _series(episodes: [playable, missing]);

    final seasons = sushiSeriesPickerSeasons(series);
    expect(seasons.length, 1);
    expect(seasons.single.seasonNumber, 1);
  });
}
