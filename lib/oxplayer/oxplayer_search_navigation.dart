import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/search/search_screen.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/sushi/sushi_config.dart';

/// OX default search: generic search (everything) so the user can search across all content types.
PageRouteInfo oxplayerDefaultSearchRoute({required bool seerrConfigured}) {
  if (OxplayerConfig.isEnabled && seerrConfigured) {
    return SeerrSearchRoute(mode: SeerrSearchMode.search);
  }
  return LibrarySearchRoute();
}

void oxplayerNavigateToSearch(
  BuildContext context, {
  required bool seerrConfigured,
}) {
  if (SushiConfig.isEnabled) {
    // Dedicated /search UI (docs/12 §6). LibrarySearchRoute would /list movies only.
    context.router.pushNativeRoute(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
    return;
  }
  context.router.navigate(oxplayerDefaultSearchRoute(seerrConfigured: seerrConfigured));
}
