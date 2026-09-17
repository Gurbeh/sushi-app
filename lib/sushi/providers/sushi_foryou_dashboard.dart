import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

export 'package:fladder/sushi/sushi_home_unique.dart' show sushiHomeForYouLimit;

class SushiForYouDashboardData {
  const SushiForYouDashboardData({this.items = const []});

  final List<ItemBaseModel> items;

  static const empty = SushiForYouDashboardData();
}

/// Followed/favourited series with a new or unfinished episode (LIST_SCOPE_FOR_YOU). Unlike
/// Home's rails this is per-viewer, so it rides its own lazy fetch rather than the shared,
/// cacheable home answer (docs/11 §2).
final sushiForYouDashboardProvider = FutureProvider<SushiForYouDashboardData>((ref) async {
  final res = await sushiFetchList(scope: SushiListScope.forYou);
  final items = res?.rows.take(sushiHomeForYouLimit).map(sushiRowToItemBaseModel).toList() ??
      const <ItemBaseModel>[];
  if (items.isEmpty) return SushiForYouDashboardData.empty;
  return SushiForYouDashboardData(items: items);
});
