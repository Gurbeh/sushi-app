import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

const _prefsKey = 'sushi_continue_v1';
const _maxItems = 10;

/// Continue-watching is client-owned (docs/12 §2) — never a home rail on the wire.
class SushiContinueEntry {
  const SushiContinueEntry({
    required this.tmdbId,
    required this.kind,
    required this.title,
    required this.year,
    required this.rating,
    required this.poster,
    required this.positionMs,
    required this.durationMs,
    required this.atMs,
  });

  final int tmdbId;
  final SushiKind kind;
  final String title;
  final int year;
  final int rating;
  final String poster;
  final int positionMs;
  final int durationMs;
  final int atMs;

  double get progressPct {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs * 100).clamp(0, 100);
  }

  bool get isFinished => progressPct >= 90;
  bool get isStarted => durationMs <= 0 || progressPct >= 5;

  Map<String, Object?> toJson() => {
        'tmdbId': tmdbId,
        'kind': kind == SushiKind.series ? 2 : 1,
        'title': title,
        'year': year,
        'rating': rating,
        'poster': poster,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'atMs': atMs,
      };

  static SushiContinueEntry? fromJson(Map<String, dynamic> json) {
    final tmdbId = json['tmdbId'] as int? ?? 0;
    if (tmdbId == 0) return null;
    return SushiContinueEntry(
      tmdbId: tmdbId,
      kind: json['kind'] == 2 ? SushiKind.series : SushiKind.movie,
      title: json['title'] as String? ?? '',
      year: json['year'] as int? ?? 0,
      rating: json['rating'] as int? ?? 0,
      poster: json['poster'] as String? ?? '',
      positionMs: json['positionMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      atMs: json['atMs'] as int? ?? 0,
    );
  }

  ItemBaseModel toItem() {
    final row = SushiRow(
      tmdbId: tmdbId,
      kind: kind,
      title: title,
      year: year,
      rating: rating,
      poster: poster,
    );
    final ticks = positionMs * 10000;
    return sushiRowToItemBaseModel(row).copyWith(
      userData: UserData(
        playbackPositionTicks: ticks,
        progress: progressPct,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(atMs),
      ),
    );
  }
}

({int tmdbId, SushiKind kind, String title, int year, int rating, String poster})? sushiContinueIdentity(ItemBaseModel item) {
  if (item is EpisodeModel) {
    final tmdb = sushiTmdbIdFromItemId(item.parentId ?? '');
    if (tmdb == null) return null;
    return (
      tmdbId: tmdb,
      kind: SushiKind.series,
      title: item.seriesName?.isNotEmpty == true ? item.seriesName! : item.name,
      year: item.overview.yearAired ?? 0,
      rating: ((item.overview.communityRating ?? 0) * 10).round(),
      poster: sushiPosterKeyFromImageUrl(item.images?.primary?.path ?? item.parentImages?.primary?.path ?? ''),
    );
  }
  final tmdb = sushiTmdbIdFromItemId(item.id);
  if (tmdb == null) return null;
  return (
    tmdbId: tmdb,
    kind: item is SeriesModel ? SushiKind.series : SushiKind.movie,
    title: item.name,
    year: item.overview.yearAired ?? 0,
    rating: ((item.overview.communityRating ?? 0) * 10).round(),
    poster: sushiPosterKeyFromImageUrl(item.images?.primary?.path ?? ''),
  );
}

String sushiPosterKeyFromImageUrl(String path) {
  if (path.isEmpty) return '';
  final file = path.split('/').last;
  return file.replaceAll(RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false), '');
}

Future<void> sushiContinueRemember(ItemBaseModel item, Duration position, Duration duration) async {
  final id = sushiContinueIdentity(item);
  if (id == null) return;
  final entry = SushiContinueEntry(
    tmdbId: id.tmdbId,
    kind: id.kind,
    title: id.title,
    year: id.year,
    rating: id.rating,
    poster: id.poster,
    positionMs: position.inMilliseconds,
    durationMs: duration.inMilliseconds,
    atMs: DateTime.now().millisecondsSinceEpoch,
  );
  final existing = await _readAll();
  final next = [
    if (!entry.isFinished && entry.isStarted) entry,
    ...existing.where((e) => e.tmdbId != entry.tmdbId || e.kind != entry.kind),
  ];
  await _writeAll(next.take(_maxItems).toList());
}

/// Menu-driven "Add to Continue Watching" (poster overflow menu on the home rows). Unlike
/// [sushiContinueRemember] — which is playback telling the store where the user stopped — this
/// just pins the title to the top of the rail at 0% progress. Re-adding an existing title moves
/// it to the top and resets its progress.
Future<void> sushiContinueAdd(ItemBaseModel item) async {
  final id = sushiContinueIdentity(item);
  if (id == null) return;
  final entry = SushiContinueEntry(
    tmdbId: id.tmdbId,
    kind: id.kind,
    title: id.title,
    year: id.year,
    rating: id.rating,
    poster: id.poster,
    positionMs: 0,
    durationMs: 0,
    atMs: DateTime.now().millisecondsSinceEpoch,
  );
  final existing = await _readAll();
  final next = [
    entry,
    ...existing.where((e) => e.tmdbId != entry.tmdbId || e.kind != entry.kind),
  ];
  await _writeAll(next.take(_maxItems).toList());
}

/// Menu-driven "Remove from Continue Watching" — drops the matching entry, if any.
Future<void> sushiContinueForget(ItemBaseModel item) async {
  final id = sushiContinueIdentity(item);
  if (id == null) return;
  final existing = await _readAll();
  final next = existing.where((e) => e.tmdbId != id.tmdbId || e.kind != id.kind).toList();
  if (next.length == existing.length) return;
  await _writeAll(next);
}

Future<List<ItemBaseModel>> sushiContinueLoad() async {
  final entries = await _readAll();
  return [for (final e in entries) e.toItem()];
}

Future<List<SushiContinueEntry>> _readAll() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final row in list)
        if (SushiContinueEntry.fromJson(Map<String, dynamic>.from(row as Map)) case final e?) e,
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> _writeAll(List<SushiContinueEntry> entries) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, jsonEncode([for (final e in entries) e.toJson()]));
}
