import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';

class SushiCachedHome {
  const SushiCachedHome({
    required this.slider,
    required this.mostWatched,
    required this.trending,
    required this.seriesMostWatched,
    required this.seriesTrending,
    required this.seq,
    required this.ttl,
    required this.fetchedAt,
  });

  final List<SushiRow> slider;
  final List<SushiRow> mostWatched;
  final List<SushiRow> trending;
  final List<SushiRow> seriesMostWatched;
  final List<SushiRow> seriesTrending;
  final int seq;
  final Duration ttl;
  final DateTime fetchedAt;

  bool get isEmpty =>
      slider.isEmpty &&
      mostWatched.isEmpty &&
      trending.isEmpty &&
      seriesMostWatched.isEmpty &&
      seriesTrending.isEmpty;
}

class SushiTitleSnapshot {
  const SushiTitleSnapshot({
    required this.page,
    required this.files,
    required this.fromCache,
    required this.lite,
  });

  final SushiItemRes? page;
  final List<SushiFile> files;
  final bool fromCache;
  final bool lite;
}

/// Persistence for the catalog cache. Drift is the production impl; tests use a fake.
abstract class SushiCatalogStore {
  Future<SushiItemRes?> readTitle(int tmdbId, int kind);
  Future<void> writeTitle(SushiItemRes page);
  Future<({List<SushiFile> files, DateTime fetchedAt})?> readFiles(int episodeId);
  Future<void> replaceFiles(int episodeId, List<SushiFile> files, DateTime at);
  Future<SushiCachedHome?> readHome();
  Future<void> writeHome(SushiCachedHome home);
}
