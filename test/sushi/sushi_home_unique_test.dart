import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

SushiRow _row(int tmdbId, {SushiKind kind = SushiKind.movie, String title = ''}) => SushiRow(
      tmdbId: tmdbId,
      kind: kind,
      title: title.isEmpty ? '$tmdbId' : title,
      year: 2020,
      rating: 1,
      poster: '',
    );

ItemBaseModel _item(int tmdbId, {SushiKind kind = SushiKind.movie, String title = ''}) =>
    sushiRowToItemBaseModel(_row(tmdbId, kind: kind, title: title));

void main() {
  test('combined carousel drops slider copies of resume titles', () {
    final resume = [_item(1, title: 'A'), _item(2, title: 'B')];
    final slider = [_item(1, title: 'A'), _item(2, title: 'B'), _item(3, title: 'C')];
    final items = sushiAssembleHomeCarousel(
      settings: HomeCarouselSettings.combined,
      nextUp: slider,
      resume: resume,
    );
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['1:1', '2:1', '3:1']);
  });

  test('same TMDB movie and series stay both', () {
    final items = sushiUniqueHomeItems([
      _item(550, kind: SushiKind.movie, title: 'Fight Club'),
      _item(550, kind: SushiKind.series, title: 'Fight Club TV'),
    ]);
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['550:1', '550:2']);
  });

  test('later rail drops titles already on the banner', () {
    final banner = [_item(1), _item(2), _item(3)];
    final seen = <String>{};
    sushiTakeUnseenHomeItems(banner, seen);
    final leftover = sushiTakeUnseenHomeItems(
      [_item(1), _item(2), _item(4)],
      seen,
    );
    expect(leftover.map(sushiHomeItemKey).toList(), ['4:1']);
  });

  test('banner cap does not hide overflow slider titles on the next rail', () {
    final slider = [_item(1), _item(2), _item(3), _item(4), _item(5), _item(6)];
    final banner = slider.take(5).toList();
    final seen = <String>{};
    sushiTakeUnseenHomeItems(banner, seen);
    final leftover = sushiTakeUnseenHomeItems(slider, seen);
    expect(leftover.map(sushiHomeItemKey).toList(), ['6:1']);
  });

  test('for you pads from most watched then trending up to limit', () {
    final seen = <String>{};
    sushiTakeUnseenHomeItems([_item(1)], seen);
    final filled = sushiFillHomeRail(
      base: [_item(10), _item(1)],
      fillers: [_item(10), _item(20), _item(21), _item(30)],
      seen: seen,
      limit: 4,
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['10:1', '20:1', '21:1', '30:1']);
  });

  test('empty for you still fills from rails', () {
    final seen = <String>{};
    final filled = sushiFillHomeRail(
      base: const [],
      fillers: [_item(2), _item(3)],
      seen: seen,
      limit: 16,
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['2:1', '3:1']);
  });

  test('fill does not consume leftover fillers into seen', () {
    final seen = <String>{};
    final fillers = [_item(1), _item(2), _item(3), _item(4), _item(5)];
    final filled = sushiFillHomeRail(
      base: const [],
      fillers: fillers,
      seen: seen,
      limit: 2,
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['1:1', '2:1']);
    expect(sushiTakeUnseenHomeItems(fillers, seen).map(sushiHomeItemKey).toList(), ['3:1', '4:1', '5:1']);
  });

  test('row unique across movie+series slider concat', () {
    final rows = sushiUniqueRows([
      _row(1),
      _row(2),
      _row(2),
      _row(2, kind: SushiKind.series),
      _row(3, kind: SushiKind.series),
    ]);
    expect(rows.map(sushiHomeRowKey).toList(), ['1:1', '2:1', '2:2', '3:2']);
  });
}
