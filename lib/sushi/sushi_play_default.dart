import 'package:flutter/foundation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_transport.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_playback_resolver.dart';

/// Resolves the item's selected quality (docs/12 §5's pick-list, applied in
/// `sushi_item_adapter.dart`) to a playable [SushiPlaybackModel] via Sushi's own `/play` delivery
/// (docs/05) — entirely separate from Jellyfin's PlaybackInfo, which Sushi has none of.
///
/// Returns null when there's nothing to play (no file id picked yet, or the resolve failed) —
/// callers show the same "unable to play" state they already show for a null OXPlayer/Jellyfin
/// model.
///
/// Movies already carry `/files` on the model. Episodes fetch `/files` here if the pick-list is
/// still empty (user tapped a season/episode that was not the header play target).
Future<SushiPlaybackModel?> sushiBuildPlaybackModel(
  ItemBaseModel itemModel, {
  bool preferHttpBridge = false,
}) async {
  MediaStreamsModel? streams = itemModel.streamModel;
  var fileId = sushiFileIdFromVersionStreamId(streams?.currentVersionStream?.id);

  if (fileId == null && itemModel is EpisodeModel) {
    final episodeId = sushiEpisodeIdFromItemId(itemModel.id);
    if (episodeId == null) return null;
    final filesRes = await sushiFetchFiles(episodeId: episodeId);
    streams = sushiBuildMediaStreams(filesRes?.files ?? const []);
    fileId = sushiFileIdFromVersionStreamId(streams.currentVersionStream?.id);
  }

  if (itemModel is! MovieModel && itemModel is! EpisodeModel) return null;
  if (fileId == null) return null;

  // Never let this reject: the caller awaits it through CancelableOperation.valueOrCancellation,
  // which — unlike every sushiFetch*/sushiPlay call this resolver is built on — rethrows instead
  // of resolving to null, and would otherwise leave the "Loading" dialog stuck forever on a
  // delivery failure (confirmed live: a never-contacted delivery bot's 400 chat not found — now
  // avoided by pre-starting every delivery bot in the Assignment right after /initbot, see
  // sushi_initbot_transport.dart).
  try {
    final url = await sushiResolvePlaybackUrl(fileId: fileId, preferHttpBridge: preferHttpBridge);
    return SushiPlaybackModel(
      item: itemModel,
      media: Media(url: url),
      mediaStreams: streams ?? itemModel.streamModel,
    );
  } catch (e, st) {
    debugPrint('[sushi] play resolve failed: $e\n$st');
    return null;
  }
}
