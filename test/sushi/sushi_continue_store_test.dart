import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';

void main() {
  test('sushiPosterKeyFromImageUrl strips TMDB size path', () {
    expect(
      sushiPosterKeyFromImageUrl('https://image.tmdb.org/t/p/w500/abc123.jpg'),
      'abc123',
    );
    expect(sushiPosterKeyFromImageUrl(''), isEmpty);
  });

  test('continue identity uses TMDB id on a movie card', () {
    final movie = MovieModel(
      name: 'Tenet',
      id: 'sushi_tmdb_27205',
      images: ImagesData(primary: ImageData(path: 'https://image.tmdb.org/t/p/w500/tenet.jpg', key: 'k')),
      originalTitle: 'Tenet',
      premiereDate: DateTime(2020),
      sortName: 'Tenet',
      status: 'Released',
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      overview: const OverviewModel(yearAired: 2020, communityRating: 7.4),
      parentId: null,
      playlistId: null,
      childCount: null,
      primaryRatio: 0.7,
      userData: const UserData(),
      canDelete: false,
      canDownload: false,
    );
    final id = sushiContinueIdentity(movie);
    expect(id?.tmdbId, 27205);
    expect(id?.kind, SushiKind.movie);
    expect(id?.poster, 'tenet');
  });

  test('continue identity maps an episode onto its series', () {
    final ep = EpisodeModel(
      seriesName: 'Breaking Bad',
      season: 1,
      episode: 1,
      episodeEnd: null,
      name: 'Pilot',
      id: 'sushi_ep_99',
      overview: const OverviewModel(),
      parentId: 'sushi_tmdb_1396',
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: 1.78,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDelete: false,
      canDownload: false,
    );
    final id = sushiContinueIdentity(ep);
    expect(id?.tmdbId, 1396);
    expect(id?.kind, SushiKind.series);
    expect(id?.title, 'Breaking Bad');
  });

  test('finished entries (>=90%) are not continue-watching', () {
    const e = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.movie,
      title: 'X',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 95 * 60 * 1000,
      durationMs: 100 * 60 * 1000,
      atMs: 1,
    );
    expect(e.isFinished, isTrue);
    expect(e.isStarted, isTrue);
  });
}
