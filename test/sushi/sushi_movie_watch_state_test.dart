import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_movie_watch_state.dart';
import 'package:flutter_test/flutter_test.dart';

MovieModel _movie({UserData userData = const UserData()}) {
  return MovieModel(
    name: 'Tenet',
    id: 'sushi_tmdb_27205',
    originalTitle: 'Tenet',
    premiereDate: DateTime(2020),
    sortName: 'Tenet',
    status: 'Released',
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: const []),
    overview: const OverviewModel(yearAired: 2020),
    parentId: null,
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: 0.7,
    userData: userData,
    canDelete: false,
    canDownload: false,
  );
}

void main() {
  test('continue resume paints progress onto a 0% catalog movie', () {
    const resume = SushiContinueEntry(
      tmdbId: 27205,
      kind: SushiKind.movie,
      title: 'Tenet',
      year: 2020,
      rating: 74,
      poster: 'p',
      positionMs: 10 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
    );

    final painted = sushiPaintMovieWatchState(_movie(), resume: resume);

    expect(painted.userData.progress, closeTo(25, 0.1));
    expect(painted.userData.played, isFalse);
    expect(painted.userData.playbackPositionTicks, 10 * 60 * 1000 * 10000);
  });

  test('played flag wins over resume progress', () {
    const resume = SushiContinueEntry(
      tmdbId: 27205,
      kind: SushiKind.movie,
      title: 'Tenet',
      year: 2020,
      rating: 74,
      poster: 'p',
      positionMs: 10 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
    );

    final painted = sushiPaintMovieWatchState(
      _movie(),
      playedIds: {'sushi_tmdb_27205'},
      resume: resume,
    );

    expect(painted.userData.played, isTrue);
    expect(painted.userData.progress, 0);
    expect(painted.userData.playbackPositionTicks, 0);
  });

  test('no resume keeps existing userData (patched progress survives enrich)', () {
    final painted = sushiPaintMovieWatchState(
      _movie(
        userData: const UserData(
          progress: 42,
          playbackPositionTicks: 42 * 10000,
        ),
      ),
    );

    expect(painted.userData.progress, 42);
  });
}
