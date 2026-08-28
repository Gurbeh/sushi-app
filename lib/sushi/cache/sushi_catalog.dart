import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fladder/sushi/cache/sushi_catalog_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';

part 'sushi_catalog.g.dart';

class CatalogItems extends Table {
  IntColumn get tmdbId => integer()();
  IntColumn get kind => integer()();
  TextColumn get title => text()();
  IntColumn get year => integer()();
  IntColumn get rating => integer()();
  TextColumn get poster => text()();

  @override
  Set<Column<Object>> get primaryKey => {tmdbId, kind};
}

class ItemPages extends Table {
  IntColumn get tmdbId => integer()();
  IntColumn get kind => integer()();
  BlobColumn get wire => blob()();

  @override
  Set<Column<Object>> get primaryKey => {tmdbId, kind};
}

class EpisodeFileLists extends Table {
  IntColumn get episodeId => integer()();
  TextColumn get filesJson => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {episodeId};
}

class HomeSnapshots extends Table {
  IntColumn get id => integer()();
  IntColumn get seq => integer()();
  IntColumn get ttlMs => integer()();
  DateTimeColumn get fetchedAt => dateTime()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [CatalogItems, ItemPages, EpisodeFileLists, HomeSnapshots])
class SushiCatalogDatabase extends _$SushiCatalogDatabase implements SushiCatalogStore {
  SushiCatalogDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'sushi_catalog',
      native: DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
    );
  }

  @override
  Future<SushiItemRes?> readTitle(int tmdbId, int kind) async {
    final row = await (select(itemPages)
          ..where((t) => t.tmdbId.equals(tmdbId) & t.kind.equals(kind)))
        .getSingleOrNull();
    if (row == null) return null;
    return SushiItemRes.decode(Uint8List.fromList(row.wire));
  }

  @override
  Future<void> writeTitle(SushiItemRes page) async {
    final wire = page.wire;
    if (wire == null || wire.isEmpty) return;
    final kind = sushiKindToWire(page.row.kind);
    await into(itemPages).insertOnConflictUpdate(
      ItemPagesCompanion(
        tmdbId: Value(page.row.tmdbId),
        kind: Value(kind),
        wire: Value(wire),
      ),
    );
    await _upsertItem(page.row);
  }

  @override
  Future<({List<SushiFile> files, DateTime fetchedAt})?> readFiles(int episodeId) async {
    final row = await (select(episodeFileLists)..where((t) => t.episodeId.equals(episodeId))).getSingleOrNull();
    if (row == null) return null;
    final list = jsonDecode(row.filesJson) as List<dynamic>;
    final files = <SushiFile>[
      for (final entry in list) SushiFile.fromJson(Map<String, dynamic>.from(entry as Map)),
    ];
    return (files: files, fetchedAt: row.fetchedAt);
  }

  @override
  Future<void> replaceFiles(int episodeId, List<SushiFile> files, DateTime at) async {
    await into(episodeFileLists).insertOnConflictUpdate(
      EpisodeFileListsCompanion(
        episodeId: Value(episodeId),
        filesJson: Value(jsonEncode([for (final f in files) f.toJson()])),
        fetchedAt: Value(at),
      ),
    );
  }

  @override
  Future<SushiCachedHome?> readHome() async {
    final row = await (select(homeSnapshots)..where((t) => t.id.equals(1))).getSingleOrNull();
    if (row == null) return null;
    final map = jsonDecode(row.payload) as Map<String, dynamic>;
    List<SushiRow> rail(String key) {
      final list = map[key] as List<dynamic>? ?? const [];
      return [for (final entry in list) SushiRow.fromJson(Map<String, dynamic>.from(entry as Map))];
    }

    return SushiCachedHome(
      slider: rail('slider'),
      mostWatched: rail('mostWatched'),
      trending: rail('trending'),
      seriesMostWatched: rail('seriesMostWatched'),
      seriesTrending: rail('seriesTrending'),
      seq: row.seq,
      ttl: Duration(milliseconds: row.ttlMs),
      fetchedAt: row.fetchedAt,
    );
  }

  @override
  Future<void> writeHome(SushiCachedHome home) async {
    await into(homeSnapshots).insertOnConflictUpdate(
      HomeSnapshotsCompanion(
        id: const Value(1),
        seq: Value(home.seq),
        ttlMs: Value(home.ttl.inMilliseconds),
        fetchedAt: Value(home.fetchedAt),
        payload: Value(
          jsonEncode({
            'slider': [for (final r in home.slider) r.toJson()],
            'mostWatched': [for (final r in home.mostWatched) r.toJson()],
            'trending': [for (final r in home.trending) r.toJson()],
            'seriesMostWatched': [for (final r in home.seriesMostWatched) r.toJson()],
            'seriesTrending': [for (final r in home.seriesTrending) r.toJson()],
          }),
        ),
      ),
    );
    for (final row in [
      ...home.slider,
      ...home.mostWatched,
      ...home.trending,
      ...home.seriesMostWatched,
      ...home.seriesTrending,
    ]) {
      await _upsertItem(row);
    }
  }

  Future<void> _upsertItem(SushiRow row) async {
    if (row.tmdbId == 0) return;
    await into(catalogItems).insertOnConflictUpdate(
      CatalogItemsCompanion(
        tmdbId: Value(row.tmdbId),
        kind: Value(sushiKindToWire(row.kind)),
        title: Value(row.title),
        year: Value(row.year),
        rating: Value(row.rating),
        poster: Value(row.poster),
      ),
    );
  }
}
