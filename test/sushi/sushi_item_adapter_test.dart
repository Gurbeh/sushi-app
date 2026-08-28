import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
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
    expect(enriched.availableEpisodes!.first, isA<EpisodeModel>());
    expect(enriched.availableEpisodes!.first.playAble, isTrue);
    expect(enriched.availableEpisodes!.first.season, 1);
    expect(sushiEpisodeIdFromItemId(enriched.availableEpisodes!.first.id), 10);
    expect(enriched.nextUp, isNotNull);
    expect(enriched.seasons!.first.episodes, hasLength(2));
    expect(enriched.images?.logo?.path, contains('/original/bb_logo.png'));
    expect(enriched.seasons!.first.parentImages?.logo?.path, contains('/original/bb_logo.png'));
    expect(enriched.availableEpisodes!.first.parentImages?.logo?.path, contains('/original/bb_logo.png'));
  });
}
