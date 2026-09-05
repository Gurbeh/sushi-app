import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_playable.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

void main() {
  test('series enrich maps ItemRes.episodes into playable seasons and episodes', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 1396,
        kind: SushiKind.series,
        title: 'Breaking Bad',
        year: 2008,
        rating: 90,
        poster: 'bb',
      ),
    ) as SeriesModel;

    final enriched = sushiEnrichSeriesModel(
      base,
      SushiItemRes(
        row: base.overview.yearAired == null
            ? const SushiRow(
                tmdbId: 1396,
                kind: SushiKind.series,
                title: 'Breaking Bad',
                year: 2008,
                rating: 90,
                poster: 'bb',
              )
            : const SushiRow(
                tmdbId: 1396,
                kind: SushiKind.series,
                title: 'Breaking Bad',
                year: 2008,
                rating: 90,
                poster: 'bb',
              ),
        overview: 'A teacher cooks.',
        releasedOn: 0,
        logo: 'bb_logo',
        backdrop: 'bb_bd',
        episodes: const [
          SushiEpisode(episodeId: 10, seasonNo: 1, episodeNo: 1, title: 'Pilot'),
          SushiEpisode(episodeId: 11, seasonNo: 1, episodeNo: 2, title: 'Cat\'s in the Bag'),
          SushiEpisode(episodeId: 12, seasonNo: 2, episodeNo: 1, title: 'Seven Thirty-Seven'),
        ],
      ),
    );

    expect(enriched.availableEpisodes, hasLength(3));
    expect(enriched.seasons, hasLength(2));
    expect(enriched.canDownload, isFalse);
    expect(sushiItemHasPlaybackActions(enriched), isFalse);
    expect(sushiItemHasPlaybackActions(base), isFalse);
    expect(enriched.availableEpisodes!.first, isA<EpisodeModel>());
    expect(enriched.availableEpisodes!.first.playAble, isTrue);
    expect(enriched.availableEpisodes!.first.canDownload, isTrue);
    expect(enriched.availableEpisodes!.first.season, 1);
    expect(sushiEpisodeIdFromItemId(enriched.availableEpisodes!.first.id), 10);
    expect(enriched.nextUp, isNotNull);
    expect(enriched.seasons!.first.episodes, hasLength(2));
    expect(enriched.images?.logo?.path, contains('/w780/bb_logo.png'));
    expect(enriched.seasons!.first.parentImages?.logo?.path, contains('/w780/bb_logo.png'));
    expect(enriched.availableEpisodes!.first.parentImages?.logo?.path, contains('/w780/bb_logo.png'));

    final pending = sushiApplySeriesFiles(enriched, const [
      SushiFile(
        fileId: 9,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 1,
        durationS: 1,
        state: SushiFileState.pending,
      ),
    ]);
    expect(sushiItemHasPlaybackActions(pending), isFalse);

    final ready = sushiApplySeriesFiles(enriched, const [
      SushiFile(
        fileId: 9,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 1,
        durationS: 1,
        state: SushiFileState.ready,
      ),
    ]);
    expect(ready.canDownload, isTrue);
    expect(sushiItemHasPlaybackActions(ready), isTrue);
  });

  test('series enrich with no episodes hides Play/Sync', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 1396,
        kind: SushiKind.series,
        title: 'Missing Show',
        year: 2008,
        rating: 90,
        poster: 'bb',
      ),
    ) as SeriesModel;
    expect(sushiItemHasPlaybackActions(base), isFalse);

    final enriched = sushiEnrichSeriesModel(
      base,
      const SushiItemRes(
        row: SushiRow(
          tmdbId: 1396,
          kind: SushiKind.series,
          title: 'Missing Show',
          year: 2008,
          rating: 90,
          poster: 'bb',
        ),
        overview: 'Not in catalog.',
        releasedOn: 0,
        episodes: [],
      ),
    );

    expect(enriched.availableEpisodes, isEmpty);
    expect(enriched.canDownload, isFalse);
    expect(sushiItemHasPlaybackActions(enriched), isFalse);
  });

  test('movie enrich with no ready file hides Play/Sync', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 550,
        kind: SushiKind.movie,
        title: 'Fight Club',
        year: 1999,
        rating: 84,
        poster: 'fc',
      ),
    ) as MovieModel;
    expect(base.canDownload, isTrue);
    expect(sushiItemHasPlaybackActions(base), isFalse);

    const row = SushiRow(
      tmdbId: 550,
      kind: SushiKind.movie,
      title: 'Fight Club',
      year: 1999,
      rating: 84,
      poster: 'fc',
    );
    const page = SushiItemRes(
      row: row,
      overview: 'A soap.',
      releasedOn: 0,
      episodes: [SushiEpisode(episodeId: 1, seasonNo: 0, episodeNo: 0, title: '')],
    );

    final empty = sushiEnrichMovieModel(base, page, const []);
    expect(empty.mediaStreams.versionStreams, isEmpty);
    expect(empty.canDownload, isFalse);
    expect(sushiItemHasPlaybackActions(empty), isFalse);

    final pendingOnly = sushiEnrichMovieModel(base, page, const [
      SushiFile(
        fileId: 9,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 1,
        durationS: 1,
        state: SushiFileState.pending,
      ),
    ]);
    expect(pendingOnly.canDownload, isFalse);
    expect(sushiItemHasPlaybackActions(pendingOnly), isFalse);

    final ready = sushiEnrichMovieModel(base, page, const [
      SushiFile(
        fileId: 9,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 1,
        durationS: 1,
        state: SushiFileState.ready,
      ),
    ]);
    expect(ready.mediaStreams.versionStreams, isNotEmpty);
    expect(ready.canDownload, isTrue);
    expect(sushiItemHasPlaybackActions(ready), isTrue);
  });

  test('empty audioLangs still exposes a playable default audio index', () {
    final streams = sushiBuildMediaStreams(const [
      SushiFile(
        fileId: 31360,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: '',
        subLangs: 'fa',
        sizeBytes: 1,
        durationS: 1,
        state: SushiFileState.ready,
      ),
    ]);
    final version = streams.versionStreams.single;
    expect(version.audioStreams, hasLength(1));
    expect(version.audioStreams.single.index, 0);
    expect(version.audioStreams.single.displayTitle, 'Default');
    expect(version.defaultAudioStreamIndex, 0);
  });
}
