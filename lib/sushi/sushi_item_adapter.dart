import 'package:collection/collection.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';

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
  return base.copyWith(
    overview: base.overview.copyWith(
      summary: item.overview,
      yearAired: base.overview.yearAired ?? (item.releasedOn > 0 ? _yearFromUnixSeconds(item.releasedOn) : null),
    ),
    mediaStreams: sushiBuildMediaStreams(files),
  );
}

int _yearFromUnixSeconds(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true).year;
