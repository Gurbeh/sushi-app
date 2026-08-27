import 'package:collection/collection.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/person_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

const _sushiFileIdPrefix = 'sushi_file_';

/// Recovers the file id from a [VersionStreamModel.id] built by [sushiBuildMediaStreams] — the
/// reverse of that id's `'sushi_file_$fileId'`, needed once the user has picked a quality and
/// pressed play (docs/05 §3's `/play <fileId>`).
int? sushiFileIdFromVersionStreamId(String? versionStreamId) {
  if (versionStreamId == null || !versionStreamId.startsWith(_sushiFileIdPrefix)) return null;
  return int.tryParse(versionStreamId.substring(_sushiFileIdPrefix.length));
}

/// Builds the [MediaStreamsModel] Fladder's play button / quality picker read
/// (`oxMovieHasPlayableMedia`/`oxplayerShowMediaStreamHelper` both just check
/// `versionStreams.isNotEmpty`) from Sushi's compact [SushiFile] pick-list. Each file becomes one
/// version/quality choice; `audio_langs`/`sub_langs` are comma-separated ISO 639-1 codes
/// (catalog.NormalizeLangs, docs/12 §5.1) — there is no richer per-track metadata on the wire, so
/// one synthetic audio/sub stream per language code is all there is to build.
///
/// Only `state == ready` files are offered — `pending`/`unavailable` have nothing to play yet.
MediaStreamsModel sushiBuildMediaStreams(List<SushiFile> files) {
  final ready = files.where((f) => f.state == SushiFileState.ready).toList();
  if (ready.isEmpty) {
    return MediaStreamsModel(versionStreams: const []);
  }

  final versions = ready.mapIndexed((index, file) {
    final audioCodes = file.audioLangs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final subCodes = file.subLangs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final audioStreams = audioCodes.isEmpty
        ? [AudioStreamModel.no()]
        : audioCodes.mapIndexed((i, code) {
            return AudioStreamModel(
              displayTitle: code.toUpperCase(),
              name: code.toUpperCase(),
              language: code,
              codec: '',
              channelLayout: '',
              sampleRate: null,
              channels: null,
              bitRate: null,
              bitDepth: null,
              profile: null,
              spatialFormat: null,
              isDefault: i == 0,
              isExternal: false,
              index: i,
            );
          }).toList();

    final subStreams = subCodes.mapIndexed((i, code) {
      return SubStreamModel(
        name: code.toUpperCase(),
        id: 'sushi_sub_${file.fileId}_$i',
        title: code.toUpperCase(),
        displayTitle: code.toUpperCase(),
        language: code,
        codec: '',
        isDefault: i == 0,
        isExternal: false,
        index: i,
      );
    }).toList();

    return VersionStreamModel(
      name: file.qualityLabel,
      index: index,
      id: 'sushi_file_${file.fileId}',
      defaultAudioStreamIndex: audioStreams.isEmpty ? -1 : 0,
      defaultSubStreamIndex: subStreams.isEmpty ? -1 : 0,
      videoStreams: [
        VideoStreamModel(
          name: file.qualityLabel,
          codec: '',
          isDefault: true,
          isExternal: false,
          index: 0,
          videoDoViTitle: null,
          videoRangeType: null,
          bitRate: null,
          width: 0,
          height: file.height,
          frameRate: 24,
        ),
      ],
      audioStreams: audioStreams,
      subStreams: subStreams,
    );
  }).toList();

  return MediaStreamsModel(versionStreamIndex: 0, versionStreams: versions);
}

/// Merges a fetched [SushiItemRes] (overview) and its files (mediaStreams) into an already-shown
/// [MovieModel] — called after the home-rail placeholder is on screen, same "paint first, enrich
/// after" shape `movies_details_provider.dart` already uses for OXPlayer.
MovieModel sushiEnrichMovieModel(MovieModel base, SushiItemRes item, List<SushiFile> files) {
  final genreNames = item.genres
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final people = [
    for (var i = 0; i < item.people.length; i++)
      Person(
        id: item.people[i].tmdbId > 0
            ? 'sushi_person_${item.people[i].tmdbId}'
            : 'sushi_person_${item.row.tmdbId}_$i',
        name: item.people[i].name,
        role: item.people[i].role,
        image: sushiTmdbImage(
          item.people[i].profile,
          key: item.people[i].tmdbId > 0
              ? 'sushi_person_${item.people[i].tmdbId}'
              : 'sushi_person_${item.row.tmdbId}_$i',
          size: 'w185',
        ),
      ),
  ];
  final related = item.related.map(sushiRowToItemBaseModel).toList();
  sushiRememberCollection(base.id, item.collectionName, item.collection.map(sushiRowToItemBaseModel).toList());

  return base.copyWith(
    images: ImagesData(
      primary: base.images?.primary ?? sushiTmdbImage(item.row.poster, key: base.id),
      // Title logos are wide PNGs; w500 crops poorly in MediaHeader — use original.
      logo: sushiTmdbImage(item.logo, key: '${base.id}_logo', size: 'original', extension: 'png') ??
          base.images?.logo,
      backDrop: item.backdrop.isEmpty
          ? base.images?.backDrop
          : [sushiTmdbImage(item.backdrop, key: '${base.id}_bd', size: 'w780')!],
    ),
    overview: base.overview.copyWith(
      summary: item.overview,
      yearAired: base.overview.yearAired ?? (item.releasedOn > 0 ? _yearFromUnixSeconds(item.releasedOn) : null),
      runTime: item.runtimeS > 0 ? Duration(seconds: item.runtimeS) : base.overview.runTime,
      genres: genreNames.isEmpty ? base.overview.genres : genreNames,
      genreItems: genreNames.isEmpty
          ? base.overview.genreItems
          : [
              for (final name in genreNames) GenreItems(id: name, name: name),
            ],
      people: people.isEmpty ? base.overview.people : people,
    ),
    mediaStreams: sushiBuildMediaStreams(files),
    related: related,
  );
}

SeriesModel sushiEnrichSeriesModel(SeriesModel base, SushiItemRes item) {
  final genreNames = item.genres
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final people = [
    for (var i = 0; i < item.people.length; i++)
      Person(
        id: item.people[i].tmdbId > 0
            ? 'sushi_person_${item.people[i].tmdbId}'
            : 'sushi_person_${item.row.tmdbId}_$i',
        name: item.people[i].name,
        role: item.people[i].role,
        image: sushiTmdbImage(
          item.people[i].profile,
          key: item.people[i].tmdbId > 0
              ? 'sushi_person_${item.people[i].tmdbId}'
              : 'sushi_person_${item.row.tmdbId}_$i',
          size: 'w185',
        ),
      ),
  ];
  final related = item.related.map(sushiRowToItemBaseModel).toList();
  sushiRememberCollection(base.id, item.collectionName, item.collection.map(sushiRowToItemBaseModel).toList());

  return base.copyWith(
    images: ImagesData(
      primary: base.images?.primary ?? sushiTmdbImage(item.row.poster, key: base.id),
      logo: sushiTmdbImage(item.logo, key: '${base.id}_logo', size: 'original', extension: 'png') ??
          base.images?.logo,
      backDrop: item.backdrop.isEmpty
          ? base.images?.backDrop
          : [sushiTmdbImage(item.backdrop, key: '${base.id}_bd', size: 'w780')!],
    ),
    overview: base.overview.copyWith(
      summary: item.overview,
      yearAired: base.overview.yearAired ?? (item.releasedOn > 0 ? _yearFromUnixSeconds(item.releasedOn) : null),
      runTime: item.runtimeS > 0 ? Duration(seconds: item.runtimeS) : base.overview.runTime,
      genres: genreNames.isEmpty ? base.overview.genres : genreNames,
      genreItems: genreNames.isEmpty
          ? base.overview.genreItems
          : [
              for (final name in genreNames) GenreItems(id: name, name: name),
            ],
      people: people.isEmpty ? base.overview.people : people,
    ),
    related: related,
  );
}

final Map<String, ({String name, List<ItemBaseModel> items})> _sushiCollections = {};

void sushiRememberCollection(String itemId, String name, List<ItemBaseModel> items) {
  if (items.isEmpty) {
    _sushiCollections.remove(itemId);
    return;
  }
  _sushiCollections[itemId] = (name: name, items: items);
}

({String name, List<ItemBaseModel> items})? sushiCollectionFor(String itemId) =>
    _sushiCollections[itemId];

/// Cast tap uses TMDB person id when present (`sushi_person_{tmdbId}`).
PersonModel sushiPersonModel(Person person, {SushiPersonRes? page}) {
  final movies = page?.movies.map(sushiRowToItemBaseModel).toList() ?? const <ItemBaseModel>[];
  final series = page?.series.map(sushiRowToItemBaseModel).toList() ?? const <ItemBaseModel>[];
  return PersonModel(
    name: page?.name.isNotEmpty == true ? page!.name : person.name,
    id: person.id,
    birthPlace: const [],
    movies: movies.whereType<MovieModel>().toList(),
    series: series.whereType<SeriesModel>().toList(),
    overview: OverviewModel(
      summary: page?.biography.isNotEmpty == true ? page!.biography : person.role,
    ),
    parentId: null,
    playlistId: null,
    images: ImagesData(
      primary: page != null && page.profile.isNotEmpty
          ? sushiTmdbImage(page.profile, key: person.id, size: 'w185')
          : person.image,
    ),
    childCount: movies.length + series.length,
    primaryRatio: 0.667,
    userData: const UserData(),
  );
}

int? sushiPersonTmdbIdFromId(String id) {
  const prefix = 'sushi_person_';
  if (!id.startsWith(prefix)) return null;
  final rest = id.substring(prefix.length);
  if (rest.contains('_')) return null; // legacy index-based id
  return int.tryParse(rest);
}

int _yearFromUnixSeconds(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true).year;
