import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';

/// The three Sushi home rails (docs/12 §2), already adapted to Fladder's poster model. Rendered
/// directly by `dashboard_screen.dart` as their own `PosterRow`s — deliberately not `ViewModel`s,
/// since there's no Jellyfin folder behind them for "see all" to navigate to.
class SushiHomeRailsData {
  const SushiHomeRailsData({
    this.slider = const [],
    this.mostWatched = const [],
    this.trending = const [],
  });

  final List<ItemBaseModel> slider;
  final List<ItemBaseModel> mostWatched;
  final List<ItemBaseModel> trending;

  static const empty = SushiHomeRailsData();
}

final sushiHomeRailsProvider = StateProvider<SushiHomeRailsData>((ref) => SushiHomeRailsData.empty);

void oxApplySushiHomeRailsRef(Ref ref, SushiHomeRailsData data) {
  ref.read(sushiHomeRailsProvider.notifier).state = data;
}
