import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/chapters_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_segments_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/trick_play_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/util/bitrate_helper.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

/// [PlaybackModel] for a file resolved through Sushi's own `/play` delivery (docs/05).
/// Continue-watching is stored locally first (R-WRITE-1); `/ev` prog is fire-and-forget.
class SushiPlaybackModel extends PlaybackModel {
  SushiPlaybackModel({
    required super.item,
    required super.media,
    super.mediaStreams,
    super.mediaSegments,
    super.chapters,
    super.trickPlay,
    super.queue,
    super.playbackQueue,
    super.queueSource,
    super.bitRateOptions,
    this.episodeId,
  }) : super(playbackInfo: null);

  /// Catalog episode id. Movies use S00E00; episodes parse from `sushi_ep_*`.
  final int? episodeId;

  DateTime? _lastProgAt;

  int? get resolvedEpisodeId => episodeId ?? sushiEpisodeIdFromItemId(item.id);

  @override
  String? playerKindLabel(BuildContext context) => PlaybackType.directStream.name(context);

  @override
  List<SubStreamModel> get subStreams => [SubStreamModel.no(), ...mediaStreams?.subStreams ?? []];

  @override
  List<AudioStreamModel> get audioStreams => [AudioStreamModel.no(), ...mediaStreams?.audioStreams ?? []];

  @override
  Future<SushiPlaybackModel> setSubtitle(SubStreamModel? model, MediaControlsWrapper player) async {
    final newIndex = await player.setSubtitleTrack(model, this);
    return copyWith(mediaStreams: () => mediaStreams?.copyWith(defaultSubStreamIndex: newIndex));
  }

  @override
  Future<SushiPlaybackModel>? setAudio(AudioStreamModel? model, MediaControlsWrapper player) async {
    final newIndex = await player.setAudioTrack(model, this);
    return copyWith(mediaStreams: () => mediaStreams?.copyWith(defaultAudioStreamIndex: newIndex));
  }

  @override
  Future<SushiPlaybackModel>? setQualityOption(Map<Bitrate, bool> map) async {
    return copyWith(bitRateOptions: map);
  }

  @override
  Future<PlaybackModel?> playbackStarted(Duration position, Ref ref) async {
    _sendProg(position, sushiEffectiveRunTime(player: Duration.zero, catalog: item.overview.runTime), ref);
    return null;
  }

  @override
  Future<PlaybackModel?> playbackStopped(Duration position, Duration? totalDuration, Ref ref) async {
    final duration = sushiEffectiveRunTime(
      player: totalDuration ?? Duration.zero,
      catalog: item.overview.runTime,
    );
    await sushiContinueRemember(item, position, duration, nextItem: nextVideo);
    _sendProg(position, duration, ref, force: true);
    return null;
  }

  @override
  Future<PlaybackModel?> updatePlaybackPosition(Duration position, bool isPlaying, Ref ref) async {
    final runTime = sushiEffectiveRunTime(player: Duration.zero, catalog: item.overview.runTime);
    if (_sendProg(position, runTime, ref)) {
      // Piggyback local Continue Watching persistence on the same ~30s throttle as the server
      // /ev ping, so progress survives a killed app or a native teardown that never reaches
      // stop() (see media_control_wrapper.dart's onPlaybackClosed) — not just the final position
      // saved at close.
      unawaited(sushiContinueRemember(item, position, runTime, nextItem: nextVideo));
    }
    return null;
  }

  /// Returns true when the ping actually went out (i.e. wasn't throttled), so callers can
  /// piggyback other periodic work on the same cadence instead of re-deriving it.
  bool _sendProg(Duration position, Duration duration, Ref ref, {bool force = false}) {
    final ep = resolvedEpisodeId;
    if (ep == null) return false;
    final now = DateTime.now();
    if (!force && _lastProgAt != null && now.difference(_lastProgAt!) < const Duration(seconds: 30)) {
      return false;
    }
    _lastProgAt = now;
    unawaited(sushiSendProgEvent(
      episodeId: ep,
      positionS: position.inSeconds,
      fileId: sushiFileIdFromVersionStreamId(mediaStreams?.currentVersionStream?.id) ?? 0,
      durationS: duration.inSeconds,
    ));
    // Mirrors the server's ≥90% rule (catalog.EpisodeWatched, be/internal/core/catalog/types.go)
    // so this device's own watched-state (and the trailer-button gate it feeds) does not wait on
    // the next cross-device sync round trip (docs/11 §6.1) just to reflect what it did itself.
    if (duration.inSeconds > 0 && position.inSeconds * 100 >= duration.inSeconds * 90) {
      unawaited(ref.read(sushiCatalogControllerProvider).markEpisodeWatchedLocally(ep, true));
    }
    return true;
  }

  @override
  SushiPlaybackModel? updateUserData(UserData userData) {
    return copyWith(item: item.copyWith(userData: userData));
  }

  @override
  SushiPlaybackModel updatePlaybackQueue(PlaybackQueueState newQueue) {
    return copyWith(playbackQueue: newQueue);
  }

  @override
  String toString() => 'SushiPlaybackModel(item: $item, media: $media)';

  @override
  @override
  SushiPlaybackModel copyWith({
    ItemBaseModel? item,
    ValueGetter<Media?>? media,
    ValueGetter<MediaStreamsModel?>? mediaStreams,
    ValueGetter<MediaSegmentsModel?>? mediaSegments,
    ValueGetter<List<Chapter>?>? chapters,
    ValueGetter<TrickPlayModel?>? trickPlay,
    List<ItemBaseModel>? queue,
    PlaybackQueueState? playbackQueue,
    PlaybackQueueSource? queueSource,
    Map<Bitrate, bool>? bitRateOptions,
    int? episodeId,
  }) {
    return SushiPlaybackModel(
      item: item ?? this.item,
      media: media != null ? media() : this.media,
      mediaStreams: mediaStreams != null ? mediaStreams() : this.mediaStreams,
      mediaSegments: mediaSegments != null ? mediaSegments() : this.mediaSegments,
      chapters: chapters != null ? chapters() : this.chapters,
      trickPlay: trickPlay != null ? trickPlay() : this.trickPlay,
      queue: queue ?? this.queue,
      playbackQueue: playbackQueue ?? this.playbackQueue,
      queueSource: queueSource ?? this.queueSource,
      bitRateOptions: bitRateOptions ?? this.bitRateOptions,
      episodeId: episodeId ?? this.episodeId,
    );
  }
}
