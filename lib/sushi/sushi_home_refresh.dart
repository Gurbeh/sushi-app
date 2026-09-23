import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';

/// OX home refresh: one batched Home/Feed request (parallel server-side queries).
abstract final class SushiHomeRefresh {
  /// Refetch home data without clearing visible shelves or showing skeletons.
  static Future<void> refresh(WidgetRef ref) async {
    await ref.read(userProvider.notifier).updateInformation();
    await ref.read(viewsProvider.notifier).fetchViews(background: true);
    // Cross-device watched-state sync (docs/11 §6.1). Independent of the home/views calls above
    // and never blocks them on failure -- a device that cannot reach the sync command this once
    // just tries again on the next launch.
    unawaited(ref.read(sushiCatalogControllerProvider).refreshWatchedState());
  }
}
