import 'dart:convert';
import 'dart:typed_data';

import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_wire.dart';

/// Hand codecs for `sushi.v1.ListReq` / `ListRes` (ADR 0009).

enum SushiListScope {
  unspecified,
  movies,
  series,
  boxsets,
  favorites,
  later,
  playlists,
  playlist,
}

enum SushiListSort { unspecified, name, year, rating, added }

int _scopeWire(SushiListScope s) => switch (s) {
      SushiListScope.movies => 1,
      SushiListScope.series => 2,
      SushiListScope.boxsets => 3,
      SushiListScope.favorites => 4,
      SushiListScope.later => 5,
      SushiListScope.playlists => 6,
      SushiListScope.playlist => 7,
      _ => 0,
    };

SushiListScope _scopeFromWire(int v) => switch (v) {
      1 => SushiListScope.movies,
      2 => SushiListScope.series,
      3 => SushiListScope.boxsets,
      4 => SushiListScope.favorites,
      5 => SushiListScope.later,
      6 => SushiListScope.playlists,
      7 => SushiListScope.playlist,
      _ => SushiListScope.unspecified,
    };

int _sortWire(SushiListSort s) => switch (s) {
      SushiListSort.name => 1,
      SushiListSort.year => 2,
      SushiListSort.rating => 3,
      SushiListSort.added => 4,
      _ => 0,
    };

class SushiPlaylistMeta {
  const SushiPlaylistMeta({required this.playlistId, required this.name, required this.itemCount});
  final int playlistId;
  final String name;
  final int itemCount;

  static SushiPlaylistMeta decode(Uint8List bytes) {
    var playlistId = 0;
    var name = '';
    var itemCount = 0;
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
          playlistId = v.value;
        case 2:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          name = utf8.decode(bytes.sublist(i, i + lenR.value));
          i += lenR.value;
        case 3:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          itemCount = v.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiPlaylistMeta(playlistId: playlistId, name: name, itemCount: itemCount);
  }
}

class SushiListRes {
  const SushiListRes({required this.rows, required this.cursor, this.playlists = const []});
  final List<SushiRow> rows;
  final int cursor;
  final List<SushiPlaylistMeta> playlists;

  static SushiListRes decode(Uint8List bytes) {
    final rows = <SushiRow>[];
    var cursor = 0;
    final playlists = <SushiPlaylistMeta>[];
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
          rows.add(SushiRow.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        case 2:
          final v = sushiReadVarint(bytes, i);
          i = v.next;
          cursor = v.value;
        case 3:
          final lenR = sushiReadVarint(bytes, i);
          i = lenR.next;
          playlists.add(SushiPlaylistMeta.decode(bytes.sublist(i, i + lenR.value)));
          i += lenR.value;
        default:
          i = sushiSkipField(bytes, i, wire);
      }
    }
    return SushiListRes(
      rows: List.unmodifiable(rows),
      cursor: cursor,
      playlists: List.unmodifiable(playlists),
    );
  }
}

Uint8List sushiEncodeListReq({
  required SushiListScope scope,
  SushiListSort sort = SushiListSort.name,
  bool sortDesc = false,
  String genre = '',
  int year = 0,
  String q = '',
  int cursor = 0,
  int playlistId = 0,
}) {
  final out = BytesBuilder();
  void writeTag(int field, int wire) => out.add(sushiUvarint((field << 3) | wire));
  final sw = _scopeWire(scope);
  if (sw != 0) {
    writeTag(1, 0);
    out.add(sushiUvarint(sw));
  }
  final sortW = _sortWire(sort);
  if (sortW != 0) {
    writeTag(2, 0);
    out.add(sushiUvarint(sortW));
  }
  if (sortDesc) {
    writeTag(3, 0);
    out.add(sushiUvarint(1));
  }
  if (genre.isNotEmpty) {
    writeTag(4, 2);
    final b = utf8.encode(genre);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  if (year != 0) {
    writeTag(5, 0);
    out.add(sushiUvarint(year));
  }
  if (q.isNotEmpty) {
    writeTag(6, 2);
    final b = utf8.encode(q);
    out.add(sushiUvarint(b.length));
    out.add(b);
  }
  if (cursor != 0) {
    writeTag(7, 0);
    out.add(sushiUvarint(cursor));
  }
  if (playlistId != 0) {
    writeTag(8, 0);
    out.add(sushiUvarint(playlistId));
  }
  return out.toBytes();
}

// silence unused warning for scope decode helper used by tests later
SushiListScope sushiListScopeFromWire(int v) => _scopeFromWire(v);
