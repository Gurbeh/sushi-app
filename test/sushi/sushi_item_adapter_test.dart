import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_playable.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';

void main() {
  test('series enrich maps season index and play-target only', () {
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

    const row = SushiRow(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
    );
    final enriched = sushiEnrichSeriesModel(
      base,
      const SushiItemRes(
        row: row,
        overview: 'A teacher cooks.',
        releasedOn: 0,
        logo: 'bb_logo',
        backdrop: 'bb_bd',
        episodes: [
          SushiEpisode(episodeId: 10, seasonNo: 1, episodeNo: 1, title: 'Pilot'),
        ],
        seasons: [
          SushiSeason(seasonNo: 1, episodeCount: 2),
          SushiSeason(seasonNo: 2, episodeCount: 1),
        ],
      ),
    );

    expect(enriched.availableEpisodes, hasLength(1));
    expect(enriched.seasons, hasLength(2));
    expect(enriched.childCount, 3);
    expect(enriched.seasons!.first.episodeCount, 2);
    expect(enriched.seasons!.first.episodes, hasLength(1));
    expect(enriched.canDownload, isFalse);
    expect(sushiItemHasPlaybackActions(enriched), isFalse);
    expect(enriched.availableEpisodes!.first.playAble, isTrue);
    expect(sushiEpisodeIdFromItemId(enriched.availableEpisodes!.first.id), 10);
    expect(enriched.nextUp, isNotNull);
    expect(enriched.images?.logo?.path, contains('/w780/bb_logo.png'));

    final merged = sushiMergeSeasonEpisodes(
      enriched,
      1,
      sushiEpisodesFromWire(enriched, const [
        SushiEpisode(episodeId: 10, seasonNo: 1, episodeNo: 1, title: 'Pilot'),
        SushiEpisode(episodeId: 11, seasonNo: 1, episodeNo: 2, title: "Cat's in the Bag"),
      ]),
    );
    expect(merged.seasons!.first.episodes, hasLength(2));
    expect(merged.availableEpisodes, hasLength(2));

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
    expect(ready.availableEpisodes!.first.overview.runTime, const Duration(seconds: 1));
  });

  test('series files stay on wired episode when resume nextUp is a later stub', () {
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
      const SushiItemRes(
        row: SushiRow(
          tmdbId: 1396,
          kind: SushiKind.series,
          title: 'Breaking Bad',
          year: 2008,
          rating: 90,
          poster: 'bb',
        ),
        overview: 'A teacher cooks.',
        releasedOn: 0,
        episodes: [
          SushiEpisode(episodeId: 10, seasonNo: 1, episodeNo: 1, title: 'Pilot'),
        ],
        seasons: [
          SushiSeason(seasonNo: 1, episodeCount: 13),
        ],
      ),
    );
    expect(sushiSeriesPlayFilesEpisodeId(enriched), 10);

    const resume = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 10 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_99',
      season: 1,
      episode: 13,
    );
    final painted = sushiPaintSeriesWatchState(enriched, resume: resume);
    expect(painted.nextUp?.id, 'sushi_ep_99');
    expect(painted.nextUp?.episode, 13);
    expect(sushiSeriesPlayFilesEpisodeId(painted), 99);

    const e1Files = [
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
    ];
    final glued = sushiApplySeriesFiles(painted, e1Files, filesEpisodeId: 10);
    expect(glued.nextUp?.id, 'sushi_ep_99');
    expect(glued.nextUp?.mediaStreams.versionStreams, isEmpty);
    expect(glued.availableEpisodes!.first.mediaStreams.versionStreams, isNotEmpty);
    expect(sushiEpisodeIdFromItemId(glued.availableEpisodes!.first.id), 10);

    const e13Files = [
      SushiFile(
        fileId: 42,
        qualityLabel: '1080p',
        height: 1080,
        audioLangs: 'en',
        subLangs: '',
        sizeBytes: 1,
        durationS: 50,
        state: SushiFileState.ready,
      ),
    ];
    final resumeFiles = sushiApplySeriesFiles(painted, e13Files, filesEpisodeId: 99);
    expect(resumeFiles.nextUp?.mediaStreams.versionStreams, isNotEmpty);
    expect(
      sushiFileIdFromVersionStreamId(resumeFiles.nextUp!.mediaStreams.currentVersionStream?.id),
      42,
    );
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

  test('season index means the series is carried, even without ready files', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 37854,
        kind: SushiKind.series,
        title: 'One Piece',
        year: 1999,
        rating: 90,
        poster: 'op',
      ),
    ) as SeriesModel;
    final enriched = sushiEnrichSeriesModel(
      base,
      const SushiItemRes(
        row: SushiRow(
          tmdbId: 37854,
          kind: SushiKind.series,
          title: 'One Piece',
          year: 1999,
          rating: 90,
          poster: 'op',
        ),
        overview: '',
        releasedOn: 0,
        episodes: [
          SushiEpisode(episodeId: 50, seasonNo: 1, episodeNo: 50, title: 'Ready'),
        ],
        seasons: [SushiSeason(seasonNo: 1, episodeCount: 1000)],
      ),
    );
    expect(sushiSeriesCarried(enriched), isTrue);
    expect(sushiItemHasPlaybackActions(enriched), isFalse);
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

  test('preferredFileId selects that version', () {
    final streams = sushiBuildMediaStreams(
      const [
        SushiFile(
          fileId: 1,
          qualityLabel: '1080p',
          height: 1080,
          audioLangs: 'en',
          subLangs: '',
          sizeBytes: 1,
          durationS: 1,
          state: SushiFileState.ready,
        ),
        SushiFile(
          fileId: 2,
          qualityLabel: '720p',
          height: 720,
          audioLangs: 'en',
          subLangs: '',
          sizeBytes: 1,
          durationS: 1,
          state: SushiFileState.ready,
        ),
      ],
      preferredFileId: 2,
    );
    expect(streams.currentVersionStream?.id, 'sushi_file_2');
  });

  test('series enrich copies TMDB runtime onto episodes', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 97546,
        kind: SushiKind.series,
        title: 'Ted Lasso',
        year: 2020,
        rating: 80,
        poster: 'tl',
      ),
    ) as SeriesModel;
    final enriched = sushiEnrichSeriesModel(
      base,
      const SushiItemRes(
        row: SushiRow(
          tmdbId: 97546,
          kind: SushiKind.series,
          title: 'Ted Lasso',
          year: 2020,
          rating: 80,
          poster: 'tl',
        ),
        overview: 'Football.',
        releasedOn: 0,
        runtimeS: 30 * 60,
        episodes: [
          SushiEpisode(episodeId: 1, seasonNo: 1, episodeNo: 1, title: 'Pilot'),
        ],
      ),
    );
    expect(enriched.overview.runTime, const Duration(minutes: 30));
    expect(enriched.availableEpisodes!.first.overview.runTime, const Duration(minutes: 30));
  });

  test('home card picks up title-page backdrop for the slider', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 550,
        kind: SushiKind.movie,
        title: 'Fight Club',
        year: 1999,
        rating: 80,
        poster: 'fc_poster',
      ),
    );
    const page = SushiItemRes(
      row: SushiRow(
        tmdbId: 550,
        kind: SushiKind.movie,
        title: 'Fight Club',
        year: 1999,
        rating: 80,
        poster: 'fc_poster',
      ),
      overview: '',
      releasedOn: 0,
      episodes: [],
      backdrop: 'fc_bd',
      logo: 'fc_logo',
    );
    final attached = sushiAttachTitleImages(base, page);
    expect(attached.images?.backDrop?.first.path, contains('/w780/fc_bd.jpg'));
    final patched = sushiPatchHomeItemImages([base], page);
    expect(patched.single.images?.backDrop?.first.path, contains('/w780/fc_bd.jpg'));
  });
}
