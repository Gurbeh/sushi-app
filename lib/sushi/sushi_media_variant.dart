import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_playback_prefetch.dart';
import 'package:fladder/sushi/sushi_share.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';

/// Delivery / track flavor for a file variant (soft sub, dubbed, etc.).
enum SushiStreamDelivery {
  softSub,
  dubbed,
  hardSub,
  original,
  unknown,
}

/// User's last explicit version pick (persisted locally).
class SushiMediaVariantPreference {
  const SushiMediaVariantPreference({
    this.qualityHeight,
    this.delivery,
  });

  /// Normalized height tier: 2160, 1080, 720, …
  final int? qualityHeight;
  final SushiStreamDelivery? delivery;

  bool get hasUserChoice => qualityHeight != null || delivery != null;

  static const unset = SushiMediaVariantPreference();

  static const _qualityKey = 'ox_media_variant_quality_height';
  static const _deliveryKey = 'ox_media_variant_delivery';

  static Future<SushiMediaVariantPreference> load(SharedPreferences prefs) async {
    final height = prefs.getInt(_qualityKey);
    final deliveryRaw = prefs.getString(_deliveryKey);
    return SushiMediaVariantPreference(
      qualityHeight: height,
      delivery: deliveryRaw == null ? null : SushiStreamDelivery.values.byName(deliveryRaw),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    if (qualityHeight != null) {
      await prefs.setInt(_qualityKey, qualityHeight!);
    } else {
      await prefs.remove(_qualityKey);
    }
    if (delivery != null) {
      await prefs.setString(_deliveryKey, delivery!.name);
    } else {
      await prefs.remove(_deliveryKey);
    }
  }

  SushiMediaVariantPreference copyWith({
    int? qualityHeight,
    SushiStreamDelivery? delivery,
    bool clearQuality = false,
    bool clearDelivery = false,
  }) {
    return SushiMediaVariantPreference(
      qualityHeight: clearQuality ? null : (qualityHeight ?? this.qualityHeight),
      delivery: clearDelivery ? null : (delivery ?? this.delivery),
    );
  }
}

final sushiMediaVariantPreferenceProvider =
    NotifierProvider<SushiMediaVariantPreferenceNotifier, SushiMediaVariantPreference>(
  SushiMediaVariantPreferenceNotifier.new,
);

class SushiMediaVariantPreferenceNotifier extends Notifier<SushiMediaVariantPreference> {
  SharedPreferences? _prefs;

  @override
  SushiMediaVariantPreference build() {
    Future.microtask(_loadFromDisk);
    return SushiMediaVariantPreference.unset;
  }

  Future<void> _loadFromDisk() async {
    _prefs ??= await SharedPreferences.getInstance();
    final loaded = await SushiMediaVariantPreference.load(_prefs!);
    state = loaded;
  }

  Future<void> rememberStream(VersionStreamModel stream) async {
    
    final meta = sushiClassifyVersionStream(stream);
    final next = SushiMediaVariantPreference(
      qualityHeight: meta.qualityHeight,
      delivery: meta.delivery == SushiStreamDelivery.unknown ? null : meta.delivery,
    );
    state = next;
    _prefs ??= await SharedPreferences.getInstance();
    await next.save(_prefs!);
  }
}

class SushiVersionStreamMeta {
  const SushiVersionStreamMeta({
    required this.qualityHeight,
    required this.delivery,
  });

  final int? qualityHeight;
  final SushiStreamDelivery delivery;
}

const _defaultQualityTiers = [1080, 720, 576, 480, 360, 2160, 1440];

SushiVersionStreamMeta sushiClassifyVersionStream(VersionStreamModel stream) {
  final blob = '${stream.name} ${stream.detailedResolutionLabel}'.toLowerCase();
  final delivery = _deliveryFromLabel(blob, stream);
  final qualityHeight = _qualityHeightFromLabel(blob) ?? _qualityHeightFromVideo(stream);
  return SushiVersionStreamMeta(qualityHeight: qualityHeight, delivery: delivery);
}

SushiStreamDelivery _deliveryFromLabel(String blob, VersionStreamModel stream) {
  if (RegExp(r'soft[\s_-]*sub').hasMatch(blob) || blob.contains('softsub')) {
    return SushiStreamDelivery.softSub;
  }
  if (RegExp(r'hard[\s_-]*sub').hasMatch(blob) || blob.contains('hardsub')) {
    return SushiStreamDelivery.hardSub;
  }
  if (RegExp(r'\bdub(?:bed)?\b').hasMatch(blob) || blob.contains('دوبله') || blob.contains('🎙')) {
    return SushiStreamDelivery.dubbed;
  }
  if (RegExp(r'soft\s+sub').hasMatch(blob)) {
    return SushiStreamDelivery.softSub;
  }
  if (RegExp(r'hard\s+sub').hasMatch(blob)) {
    return SushiStreamDelivery.hardSub;
  }
  if (stream.subStreams.isNotEmpty) {
    return SushiStreamDelivery.softSub;
  }
  if (blob.contains('original')) {
    return SushiStreamDelivery.original;
  }
  return SushiStreamDelivery.original;
}

int? _qualityHeightFromLabel(String blob) {
  final match = RegExp(r'\b(2160|1440|1080|720|576|480|360)p?\b').firstMatch(blob);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

int? _qualityHeightFromVideo(VersionStreamModel stream) {
  final height = stream.videoStreams.firstOrNull?.height;
  if (height == null || height <= 0) return null;
  return sushiNormalizeQualityHeight(height);
}

int sushiNormalizeQualityHeight(int height) {
  if (height >= 1900) return 2160;
  if (height >= 1200) return 1440;
  if (height >= 900) return 1080;
  if (height >= 600) return 720;
  if (height >= 510) return 576;
  if (height >= 420) return 480;
  if (height >= 330) return 360;
  return height;
}

/// Pick a [versionStreams] index using saved preference or cold-start defaults.
int sushiPickVersionStreamIndex(
  List<VersionStreamModel> streams,
  SushiMediaVariantPreference preference,
) {
  if (streams.isEmpty) return 0;
  if (streams.length == 1) return streams.first.index;

  final classified = streams
      .map((stream) => (stream: stream, meta: sushiClassifyVersionStream(stream)))
      .toList();

  if (preference.hasUserChoice) {
    return _pickWithPreference(classified, preference);
  }
  return _pickColdDefault(classified);
}

int _pickColdDefault(List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> classified) {
  for (final tier in const [1080, 720]) {
    final soft = classified.firstWhereOrNull(
      (e) => e.meta.qualityHeight == tier && e.meta.delivery == SushiStreamDelivery.softSub,
    );
    if (soft != null) return soft.stream.index;

    final any = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (any != null) return any.stream.index;
  }

  for (final tier in _defaultQualityTiers) {
    if (tier == 1080 || tier == 720) continue;
    final match = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (match != null) return match.stream.index;
  }

  return classified.first.stream.index;
}

int _pickWithPreference(
  List<({VersionStreamModel stream, SushiVersionStreamMeta meta})> classified,
  SushiMediaVariantPreference preference,
) {
  final tiers = _qualityTiersToTry(preference.qualityHeight);
  final preferredDelivery = preference.delivery;

  if (preference.qualityHeight != null) {
    final tier = preference.qualityHeight!;
    for (final delivery in _deliveryFallbacks(preferredDelivery, includeOriginal: false)) {
      final match = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == delivery,
      );
      if (match != null) return match.stream.index;
    }
    if (preferredDelivery == null) {
      final anyAtTier = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
      if (anyAtTier != null) return anyAtTier.stream.index;
    }
  }

  for (final tier in tiers) {
    if (tier == preference.qualityHeight) continue;
    if (preferredDelivery != null) {
      final dubbedMatch = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == preferredDelivery,
      );
      if (dubbedMatch != null) return dubbedMatch.stream.index;
    }
    for (final delivery in _deliveryFallbacks(preferredDelivery)) {
      final match = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == delivery,
      );
      if (match != null) return match.stream.index;
    }
    final anyAtTier = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (anyAtTier != null) return anyAtTier.stream.index;
  }

  for (final delivery in _deliveryFallbacks(preferredDelivery)) {
    final match = classified.firstWhereOrNull((e) => e.meta.delivery == delivery);
    if (match != null) return match.stream.index;
  }

  return classified.first.stream.index;
}

List<int> _qualityTiersToTry(int? preferred) {
  if (preferred == null) return _defaultQualityTiers;
  final rest = _defaultQualityTiers.where((t) => t != preferred).toList();
  return [preferred, ...rest];
}

List<SushiStreamDelivery> _deliveryFallbacks(
  SushiStreamDelivery? preferred, {
  bool includeOriginal = true,
}) {
  const core = [
    SushiStreamDelivery.softSub,
    SushiStreamDelivery.dubbed,
    SushiStreamDelivery.hardSub,
  ];
  final base = preferred == null
      ? core
      : [preferred, ...core.where((d) => d != preferred)];
  if (!includeOriginal) return base;
  return [...base, SushiStreamDelivery.original, SushiStreamDelivery.unknown];
}

MediaStreamsModel sushiApplyPreferredVersionStream(
  Ref ref,
  MediaStreamsModel streams,
) {
  if (streams.versionStreams.length <= 1) {
    return streams;
  }
  final pref = ref.read(sushiMediaVariantPreferenceProvider);
  final idx = sushiPickVersionStreamIndex(streams.versionStreams, pref);
  if (idx == (streams.versionStreamIndex ?? 0)) return streams;
  return streams.copyWith(versionStreamIndex: idx);
}

void sushiRememberMediaStreamsSelection(WidgetRef ref, MediaStreamsModel streams) {
  
  final current = streams.currentVersionStream;
  if (current == null) return;
  ref.read(sushiMediaVariantPreferenceProvider.notifier).rememberStream(current);
}

MediaStreamsModel sushiOnUserMediaStreamsChanged(
  WidgetRef ref,
  MediaStreamsModel changed, {
  String? itemId,
}) {
  sushiRememberMediaStreamsSelection(ref, changed);
  
    sushiPlayWarmup.scheduleFromStreams(changed);
  
  if (itemId != null && itemId.isNotEmpty) {
    final msId = changed.currentVersionStream?.id;
    if (msId != null && msId.isNotEmpty) {
      SushiPlaybackPrefetch.scheduleForItem(ref.read, itemId, mediaSourceId: msId);
    }
  }
  return changed;
}

MovieModel? sushiPrepareMovieMediaStreams(MovieModel? movie, Ref ref) {
  if (movie == null) return movie;
  var item = sushiApplyShareMediaSourceToMovie(movie, ref) ?? movie;
  final streams = sushiApplyPreferredVersionStream(ref, item.mediaStreams);
  if (streams == item.mediaStreams) return item;
  return item.copyWith(mediaStreams: streams);
}

EpisodeModel? sushiPrepareEpisodeMediaStreams(EpisodeModel? episode, Ref ref) {
  if (episode == null) return episode;
  var item = sushiApplyShareMediaSourceToEpisode(episode, ref) ?? episode;
  final streams = sushiApplyPreferredVersionStream(ref, item.mediaStreams);
  if (streams == item.mediaStreams) return item;
  return item.copyWith(mediaStreams: streams);
}

List<EpisodeModel> sushiPrepareEpisodeListMediaStreams(Ref ref, List<EpisodeModel> episodes) {
  if (episodes.isEmpty) return episodes;
  return episodes
      .map((episode) => sushiPrepareEpisodeMediaStreams(episode, ref) ?? episode)
      .toList();
}
