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
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
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
    _sendProg(position, item.overview.runTime ?? Duration.zero);
    return null;
  }

  @override
  Future<PlaybackModel?> playbackStopped(Duration position, Duration? totalDuration, Ref ref) async {
    final duration = totalDuration ?? item.overview.runTime ?? Duration.zero;
    await sushiContinueRemember(item, position, duration);
    _sendProg(position, duration, force: true);
    return null;
  }

  @override
  Future<PlaybackModel?> updatePlaybackPosition(Duration position, bool isPlaying, Ref ref) async {
    _sendProg(position, item.overview.runTime ?? Duration.zero);
    return null;
  }

  void _sendProg(Duration position, Duration duration, {bool force = false}) {
    final ep = resolvedEpisodeId;
    if (ep == null) return;
    final now = DateTime.now();
    if (!force && _lastProgAt != null && now.difference(_lastProgAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastProgAt = now;
    unawaited(sushiSendProgEvent(
      episodeId: ep,
      positionS: position.inSeconds,
      fileId: sushiFileIdFromVersionStreamId(mediaStreams?.currentVersionStream?.id) ?? 0,
      durationS: duration.inSeconds,
    ));
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
