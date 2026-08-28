import 'package:flutter/foundation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_item_transport.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_playback_resolver.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

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
/// Compact list rows have no files. Same `/item` + `/files` fetch the detail page does.
Future<ItemBaseModel> _sushiHydrateForPlay(ItemBaseModel item) async {
  if (item is MovieModel) {
    if (sushiFileIdFromVersionStreamId(item.streamModel?.currentVersionStream?.id) != null) {
      return item;
    }
    final tmdbId = sushiTmdbIdFromItemId(item.id);
    if (tmdbId == null) return item;
    final itemRes = await sushiFetchItem(tmdbId: tmdbId, kind: 1);
    if (itemRes == null) return item;
    List<SushiFile> files = const [];
    final episodeId = itemRes.episodes.isEmpty ? null : itemRes.episodes.first.episodeId;
    if (episodeId != null) {
      final filesRes = await sushiFetchFiles(episodeId: episodeId);
      files = filesRes?.files ?? const [];
    }
    return sushiEnrichMovieModel(item, itemRes, files);
  }
  if (item is SeriesModel) {
    if (item.availableEpisodes?.isNotEmpty == true) return item;
    final tmdbId = sushiTmdbIdFromItemId(item.id);
    if (tmdbId == null) return item;
    final itemRes = await sushiFetchItem(tmdbId: tmdbId, kind: 2);
    if (itemRes == null) return item;
    return sushiEnrichSeriesModel(item, itemRes);
  }
  return item;
}

Future<SushiPlaybackModel?> sushiBuildPlaybackModel(
  ItemBaseModel itemModel, {
  bool preferHttpBridge = false,
}) async {
  var item = itemModel;
  if (item is SeriesModel ||
      (item is MovieModel &&
          sushiFileIdFromVersionStreamId(item.streamModel?.currentVersionStream?.id) == null)) {
    item = await _sushiHydrateForPlay(item);
  }

  if (item is SeriesModel) {
    final episode = item.nextUp ??
        (item.availableEpisodes == null || item.availableEpisodes!.isEmpty
            ? null
            : item.availableEpisodes!.first);
    if (episode == null) return null;
    item = episode;
  }

  MediaStreamsModel? streams = item.streamModel;
  var fileId = sushiFileIdFromVersionStreamId(streams?.currentVersionStream?.id);

  if (fileId == null && item is EpisodeModel) {
    final episodeId = sushiEpisodeIdFromItemId(item.id);
    if (episodeId == null) return null;
    final filesRes = await sushiFetchFiles(episodeId: episodeId);
    streams = sushiBuildMediaStreams(filesRes?.files ?? const []);
    fileId = sushiFileIdFromVersionStreamId(streams.currentVersionStream?.id);
  }

  if (item is! MovieModel && item is! EpisodeModel) return null;
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
      item: item,
      media: Media(url: url),
      mediaStreams: streams ?? item.streamModel,
    );
  } catch (e, st) {
    debugPrint('[sushi] play resolve failed: $e\n$st');
    return null;
  }
}
