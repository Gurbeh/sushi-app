import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

bool sushiIsFollowableItem(ItemBaseModel item) {
  return item is SeriesModel || item is MovieModel;
}

List<ItemAction> sushiFollowActions(BuildContext context, WidgetRef ref, ItemBaseModel item) {
  if (!sushiIsFollowableItem(item)) return const [];

  final following = ref.watch(sushiCatalogItemFlagsProvider.select((s) => s.isFollowing(item.id)));

  return [
    ItemActionButton(
      selected: following,
      icon: Icon(following ? IconsaxPlusLinear.notification_bing : IconsaxPlusLinear.notification),
      label: Text(following ? context.localized.sushiUnfollow : context.localized.sushiFollow),
      action: () => _toggleFollow(context, ref, item.id),
    ),
  ];
}

Future<void> _toggleFollow(BuildContext context, WidgetRef ref, String catalogId) async {
  final loc = context.localized;
  final wasFollowing = ref.read(sushiCatalogItemFlagsProvider).isFollowing(catalogId);
  final ok = await ref.read(sushiCatalogItemFlagsProvider.notifier).toggleFollowing(catalogId);
  if (!ok) {
    FladderSnack.show(loc.sushiFollowFailed);
    return;
  }
  FladderSnack.show(!wasFollowing ? loc.sushiFollowAdded : loc.sushiFollowRemoved);
}
