import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';

/// Home identity for R-RAIL-1. TMDB+kind, not [ItemBaseModel.id] — that id drops kind, so
/// movie 550 and series 550 would collapse.
String sushiHomeItemKey(ItemBaseModel item) {
  final identity = sushiContinueIdentity(item);
  if (identity != null) {
    return '${identity.tmdbId}:${sushiKindToWire(identity.kind)}';
  }
  return item.id;
}

String sushiHomeRowKey(SushiRow row) => '${row.tmdbId}:${sushiKindToWire(row.kind)}';

/// First occurrence wins. Mutates [seen]. Stops at [limit] so leftovers stay available for later rails.
List<ItemBaseModel> sushiTakeUnseenHomeItems(
  Iterable<ItemBaseModel> items,
  Set<String> seen, {
  int? limit,
}) {
  final out = <ItemBaseModel>[];
  for (final item in items) {
    if (limit != null && out.length >= limit) break;
    if (seen.add(sushiHomeItemKey(item))) out.add(item);
  }
  return out;
}

/// Personalized [base] first, then [fillers] (most watched / trending) up to [limit]. Mutates [seen].
List<ItemBaseModel> sushiFillHomeRail({
  required Iterable<ItemBaseModel> base,
  required Iterable<ItemBaseModel> fillers,
  required Set<String> seen,
  required int limit,
}) {
  final out = sushiTakeUnseenHomeItems(base, seen, limit: limit);
  if (out.length >= limit) return out;
  out.addAll(sushiTakeUnseenHomeItems(fillers, seen, limit: limit - out.length));
  return out;
}

List<ItemBaseModel> sushiUniqueHomeItems(Iterable<ItemBaseModel> items) {
  return sushiTakeUnseenHomeItems(items, <String>{});
}

List<SushiRow> sushiUniqueRows(Iterable<SushiRow> rows) {
  final seen = <String>{};
  final out = <SushiRow>[];
  for (final row in rows) {
    if (seen.add(sushiHomeRowKey(row))) out.add(row);
  }
  return out;
}

/// Banner list. Unique across sources (resume + slider). Carousel viewport clones stay in the
/// widget, not here.
List<ItemBaseModel> sushiAssembleHomeCarousel({
  required HomeCarouselSettings settings,
  required List<ItemBaseModel> nextUp,
  required List<ItemBaseModel> resume,
}) {
  final raw = switch (settings) {
    HomeCarouselSettings.nextUp => nextUp,
    HomeCarouselSettings.combined => [...resume, ...nextUp],
    HomeCarouselSettings.cont => resume,
  };
  return sushiUniqueHomeItems(raw);
}
