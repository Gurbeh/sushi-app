import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand-decode/encode of `sushi.v1.ItemReq`/`ItemRes`/`FilesReq`/`FilesRes`/`Episode`/`File`
/// (proto/sushi/v1/item.proto, proto/sushi/v1/catalog.proto) — opening a title (docs/12 §4) and
/// its pick-list (docs/12 §5). Same style as sushi_home_pb.dart.

/// Mirrors `sushi.v1.FileState`.
enum SushiFileState { unspecified, ready, pending, unavailable }

SushiFileState _fileStateFromWire(int v) => switch (v) {
      1 => SushiFileState.ready,
      2 => SushiFileState.pending,
      3 => SushiFileState.unavailable,
      _ => SushiFileState.unspecified,
    };

/// One entry of a title's season/episode tree. A movie gets exactly one, season 0 episode 0
/// (catalog.proto's convention) — the id `files()` is keyed on, movie or series alike.
class SushiEpisode {
  const SushiEpisode({
    required this.episodeId,
    required this.seasonNo,
    required this.episodeNo,
    required this.title,
  });

  final int episodeId;
  final int seasonNo;
  final int episodeNo;
  final String title;

  static SushiEpisode decode(Uint8List bytes) {
    var episodeId = 0;
    var seasonNo = 0;
    var episodeNo = 0;
    var title = '';
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          episodeId = v.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          seasonNo = v.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          episodeNo = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          title = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiEpisode(episodeId: episodeId, seasonNo: seasonNo, episodeNo: episodeNo, title: title);
  }
}

/// One playable encoding of one episode (the pick-list, docs/12 §5).
class SushiFile {
  const SushiFile({
    required this.fileId,
    required this.qualityLabel,
    required this.height,
    required this.audioLangs,
    required this.subLangs,
    required this.sizeBytes,
    required this.durationS,
    required this.state,
  });

  final int fileId;
  final String qualityLabel;
  final int height;
  final String audioLangs;
  final String subLangs;
  final int sizeBytes;
  final int durationS;
  final SushiFileState state;

  static SushiFile decode(Uint8List bytes) {
    var fileId = 0;
    var qualityLabel = '';
    var height = 0;
    var audioLangs = '';
    var subLangs = '';
    var sizeBytes = 0;
    var durationS = 0;
    var state = 0;
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          fileId = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          qualityLabel = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          height = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          audioLangs = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          subLangs = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 6:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          sizeBytes = v.value;
        case 7:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          durationS = v.value;
        case 8:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          state = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiFile(
      fileId: fileId,
      qualityLabel: qualityLabel,
      height: height,
      audioLangs: audioLangs,
      subLangs: subLangs,
      sizeBytes: sizeBytes,
      durationS: durationS,
      state: _fileStateFromWire(state),
    );
  }
}

class SushiPerson {
  const SushiPerson({required this.name, required this.role, required this.profile});

  final String name;
  final String role;
  final String profile;

  static SushiPerson decode(Uint8List bytes) {
    var name = '';
    var role = '';
    var profile = '';
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          name = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          role = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          profile = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPerson(name: name, role: role, profile: profile);
  }
}

/// Decoded `sushi.v1.ItemRes` — the title page (docs/12 §4).
class SushiItemRes {
  const SushiItemRes({
    required this.row,
    required this.overview,
    required this.releasedOn,
    required this.episodes,
    this.logo = '',
    this.backdrop = '',
    this.genres = '',
    this.runtimeS = 0,
    this.people = const [],
    this.related = const [],
    this.collectionName = '',
    this.collection = const [],
  });

  final SushiRow row;
  final String overview;
  final int releasedOn;
  final List<SushiEpisode> episodes;
  final String logo;
  final String backdrop;
  final String genres;
  final int runtimeS;
  final List<SushiPerson> people;
  final List<SushiRow> related;
  final String collectionName;
  final List<SushiRow> collection;

  static SushiItemRes decode(Uint8List bytes) {
    SushiRow row = const SushiRow(tmdbId: 0, kind: SushiKind.unspecified, title: '', year: 0, rating: 0, poster: '');
    var overview = '';
    var releasedOn = 0;
    final episodes = <SushiEpisode>[];
    var logo = '';
    var backdrop = '';
    var genres = '';
    var runtimeS = 0;
    final people = <SushiPerson>[];
    final related = <SushiRow>[];
    var collectionName = '';
    final collection = <SushiRow>[];
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      switch (field) {
        case 1:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          row = SushiRow.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          overview = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          releasedOn = v.value;
        case 4:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          episodes.add(SushiEpisode.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 5:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          logo = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 6:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          backdrop = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 7:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          genres = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 8:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          runtimeS = v.value;
        case 9:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          people.add(SushiPerson.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 10:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          related.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 11:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          collectionName = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 12:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          collection.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiItemRes(
      row: row,
      overview: overview,
      releasedOn: releasedOn,
      episodes: List.unmodifiable(episodes),
      logo: logo,
      backdrop: backdrop,
      genres: genres,
      runtimeS: runtimeS,
      people: List.unmodifiable(people),
      related: List.unmodifiable(related),
      collectionName: collectionName,
      collection: List.unmodifiable(collection),
    );
  }
}

/// Decoded `sushi.v1.FilesRes`.
class SushiFilesRes {
  const SushiFilesRes({required this.files});

  final List<SushiFile> files;

  static SushiFilesRes decode(Uint8List bytes) {
    final files = <SushiFile>[];
    var i = 0;
    while (i < bytes.length) {
      final tagR = sushiReadVarint(bytes, i);
      i = tagR.next;
      final field = tagR.value >> 3;
      final wire = tagR.value & 0x7;
      if (field == 1) {
        final lenR = sushiReadVarint(bytes, i);
        i = lenR.next;
        files.add(SushiFile.decode(bytes.sublist(i, i + lenR.value)));
        i += lenR.value;
      } else {
        i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiFilesRes(files: List.unmodifiable(files));
  }
}

/// Encodes a `sushi.v1.ItemReq`: field 1 `tmdb_id` (varint), field 2 `kind` (varint enum).
Uint8List sushiEncodeItemReq({required int tmdbId, required int kind}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  if (tmdbId != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(tmdbId));
  }
  if (kind != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(kind));
  }
  return out.toBytes();
}

/// Encodes a `sushi.v1.FilesReq`: field 1 `episode_id` (varint).
Uint8List sushiEncodeFilesReq({required int episodeId}) {
  final out = BytesBuilder();
  if (episodeId != 0) {
    out.add(sushiUvarint((1 << 3) | 0));
    out.add(sushiUvarint(episodeId));
  }
  return out.toBytes();
}
