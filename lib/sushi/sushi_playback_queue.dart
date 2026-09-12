import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_play_default.dart';

/// Fladder [PlaybackModelHelper.loadNewVideo] reuses [oldModel.playbackQueue] without
/// updating [PlaybackQueueState.mainQueueCurrentId], so after auto-next from ep1→ep2
/// the "next episode" anchor stays on ep1 and suggests ep2 again.
class SushiPlaybackModelHelper extends PlaybackModelHelper {
  const SushiPlaybackModelHelper({required super.ref});

  @override
  Future<PlaybackModel?> loadNewVideo(ItemBaseModel newItem) async {
    return _loadNewSushiVideo(newItem);
  }

  /// Sushi has no Jellyfin PlaybackInfo, so next/previous-episode navigation resolves the new
  /// file through Sushi's own `/play` delivery. The series queue is re-anchored on the new
  /// episode so the player's next/previous buttons keep working without another catalog fetch.
  Future<PlaybackModel?> _loadNewSushiVideo(ItemBaseModel newItem) async {
    ref.read(videoPlayerProvider).pause();
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: true));
    final currentModel = ref.read(playBackModel);
    final preferHttpBridge =
        ref.read(videoPlayerSettingsProvider).wantedPlayer != PlayerOptions.nativePlayer;
    final newModel = await sushiBuildPlaybackModel(
      newItem,
      catalog: ref.read(sushiCatalogControllerProvider),
      preferHttpBridge: preferHttpBridge,
      sync: ref.read(syncProvider.notifier),
      playedIds: ref.read(sushiCatalogItemFlagsProvider).playedIds,
    );
    if (newModel == null) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: false));
      return null;
    }
    final anchored = (currentModel != null && currentModel.playbackQueue.queue.length > 1)
        ? newModel.updatePlaybackQueue(currentModel.playbackQueue.jumpToItem(newItem.id))
        : newModel;
    ref.read(videoPlayerProvider.notifier).loadPlaybackItem(anchored, Duration.zero);
    return anchored;
  }
}

final sushiPlaybackModelHelper = Provider<PlaybackModelHelper>((ref) {
  return SushiPlaybackModelHelper(ref: ref);
});
