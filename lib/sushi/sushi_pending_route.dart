import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_share.dart';
import 'package:fladder/sushi/sushi_share_deep_link.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';

/// Holds a deep-link destination until the user finishes OX login.
final sushiPendingRouteProvider = StateProvider<String?>((ref) => null);

String? _bufferedPendingPath;

bool get sushiHasBufferedPendingPath =>
    _bufferedPendingPath != null && _bufferedPendingPath!.isNotEmpty;

/// Called from [deepLinkBuilder] before auth is available (no [WidgetRef]).
void sushiBufferPendingPath(String path) {
  if (path.isEmpty || path == '/' || path.startsWith('/splash') || path.startsWith('/sushi-login')) {
    return;
  }
  _bufferedPendingPath = path;
}

void sushiFlushBufferedPendingPath(WidgetRef ref) {
  final path = _bufferedPendingPath;
  if (path == null) return;
  _bufferedPendingPath = null;
  ref.read(sushiPendingRouteProvider.notifier).state = path;
  sushiFlushBufferedShareMediaSource(ref);
}

void sushiSetPendingRoute(WidgetRef ref, String path) {
  if (path.isEmpty || path == '/' || path.startsWith('/splash') || path.startsWith('/sushi-login')) {
    return;
  }
  ref.read(sushiPendingRouteProvider.notifier).state = path;
}

/// Post-login navigation: pending deep link or dashboard.
Future<void> sushiNavigateAfterLogin(BuildContext context, WidgetRef ref) async {
  ref.read(lockScreenActiveProvider.notifier).update((state) => false);
  if (!context.mounted) return;

  final pending = SushiEnv.isEnabled ? ref.read(sushiPendingRouteProvider) : null;
  if ((pending != null && pending.isNotEmpty) || sushiHasBufferedPendingPath) {
    await sushiReconcilePendingShareNavigation(context, ref, force: true);
    return;
  }

  await context.router.replaceAll([const DashboardRoute()]);
}
