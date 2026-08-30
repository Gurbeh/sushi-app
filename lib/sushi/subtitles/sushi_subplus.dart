// PROTOTYPE — sushi/docs/15-subtitles.md §7.
//
// Direct client -> sub-plus.ir calls. Production moves the list + ranking server-side and
// delivers the file over the bot / clone channel (doc 15 §7); this file exists only so the
// Automatic/Online subtitle UX can be exercised on-device before slices 2-5 exist. Do not ship.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

const _apiRoot = 'https://sub-plus.ir/api.php';
const _defaultLang = 'persian';
const _timeout = Duration(seconds: 20);

/// One search hit from sub-plus: a ZIP bundle of subtitle files for a title.
class SubplusPack {
  const SubplusPack({
    required this.tag,
    required this.title,
    required this.imdb,
    required this.year,
    required this.series,
    required this.translator,
    required this.releases,
    required this.poster,
  });

  final String tag; // opaque; pass back to downloadUrl verbatim
  final String title;
  final String imdb;
  final String year;
  final bool series;
  final String translator;
  final List<String> releases;
  final String poster;

  /// A one-line hint for the list row: first release name, else the translator credit.
  String get hint => releases.isNotEmpty ? releases.first : translator.replaceAll('\n', ' ').trim();
}

/// One `.srt`/`.ass` pulled out of a pack ZIP, decoded to text with the sub-plus ad cue removed.
class SubplusSubFile {
  const SubplusSubFile({required this.name, required this.ext, required this.text});
  final String name;
  final String ext;
  final String text;
}

const _ordinalSeasons = {
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
  'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
};

/// Best-effort season/episode extraction from a release name, pack title or ZIP entry name.
/// Handles `S03E01`, `s3e1`, `3x01`, `Season 3` / `Season.03`, `Third Season`, and a bare
/// `E01` / `Episode 1` (episode only). Either field may be null.
({int? season, int? episode}) parseSeasonEpisode(String raw) {
  final s = raw.toLowerCase();
  final se = RegExp(r's(\d{1,2})[ ._-]?e(\d{1,3})').firstMatch(s);
  if (se != null) {
    return (season: int.tryParse(se.group(1)!), episode: int.tryParse(se.group(2)!));
  }
  final cross = RegExp(r'\b(\d{1,2})x(\d{1,3})\b').firstMatch(s);
  if (cross != null) {
    return (season: int.tryParse(cross.group(1)!), episode: int.tryParse(cross.group(2)!));
  }
  int? season;
  final seasonNum = RegExp(r'(?:\bs|season)[ ._-]?(\d{1,2})\b').firstMatch(s);
  if (seasonNum != null) season = int.tryParse(seasonNum.group(1)!);
  if (season == null) {
    for (final e in _ordinalSeasons.entries) {
      if (s.contains('${e.key} season') || s.contains('season ${e.key}')) {
        season = e.value;
        break;
      }
    }
  }
  int? episode;
  final epNum = RegExp(r'(?:\be|episode|قسمت|ep)[ ._-]?(\d{1,3})\b').firstMatch(s);
  if (epNum != null) episode = int.tryParse(epNum.group(1)!);
  return (season: season, episode: episode);
}

/// Picks the subtitle file for a specific [season]/[episode] out of a season pack. Falls back to
/// an episode-only match, then to the single file, then null.
SubplusSubFile? pickEpisodeFile(List<SubplusSubFile> files, int season, int episode) {
  if (files.isEmpty) return null;
  if (files.length == 1) return files.first;
  SubplusSubFile? epOnly;
  for (final f in files) {
    final se = parseSeasonEpisode(f.name);
    if (se.episode != episode) continue;
    if (se.season == season) return f;
    if (se.season == null) epOnly ??= f;
  }
  return epOnly;
}

/// How well a pack matches a target [season] (0 = unknown, positive = match, negative = mismatch).
/// Looks at the pack title and every release line.
int seasonMatchScore(SubplusPack pack, int season) {
  final texts = [pack.title, ...pack.releases];
  var best = 0;
  for (final t in texts) {
    final s = parseSeasonEpisode(t).season;
    if (s == season) {
      best = 1;
      break;
    }
    if (s != null) best = -1;
  }
  return best;
}

class SubplusException implements Exception {
  SubplusException(this.message);
  final String message;
  @override
  String toString() => 'SubplusException: $message';
}

class SushiSubplusClient {
  SushiSubplusClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Normalises an IMDb id ("tt123", "123", " TT123 ") to "tt123"; "" if not an IMDb id.
  static String imdbQuery(String id) {
    var s = id.trim().toLowerCase();
    if (s.startsWith('tt')) s = s.substring(2);
    if (s.isEmpty || !RegExp(r'^\d+$').hasMatch(s)) return '';
    return 'tt$s';
  }

  Future<List<SubplusPack>> search(String query, {String lang = _defaultLang}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final resp = await _client
        .post(
          Uri.parse(_apiRoot),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'q': q, 'l': lang},
        )
        .timeout(_timeout);
    final body = _decodeJson(resp.body);
    if (body['ok'] != true) {
      throw SubplusException((body['description'] as String?)?.trim() ?? 'search failed');
    }
    final result = (body['result'] as List?) ?? const [];
    final packs = <SubplusPack>[];
    for (final raw in result) {
      if (raw is! Map) continue;
      final tag = (raw['tag'] as String?)?.trim() ?? '';
      if (tag.isEmpty) continue;
      packs.add(SubplusPack(
        tag: tag,
        title: (raw['title'] as String?)?.trim() ?? '',
        imdb: (raw['imdb'] as String?)?.trim() ?? '',
        year: (raw['year'] as String?)?.trim() ?? '',
        series: raw['series'] == true,
        translator: (raw['comment'] as String?)?.trim() ?? '',
        releases: _splitLines(raw['info'] as String?),
        poster: (raw['pic'] as String?)?.trim() ?? '',
      ));
    }
    return packs;
  }

  Future<String> downloadUrl(String tag) async {
    final t = tag.trim();
    if (t.isEmpty) throw SubplusException('empty tag');
    final resp = await _client
        .post(
          Uri.parse(_apiRoot),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'dl': t},
        )
        .timeout(_timeout);
    final body = _decodeJson(resp.body);
    if (body['ok'] != true) {
      throw SubplusException((body['description'] as String?)?.trim() ?? 'download failed');
    }
    final link = (body['download'] as String?)?.trim() ?? '';
    if (!_validDownloadUrl(link)) {
      throw SubplusException('unusable link (bad tag?)');
    }
    return link;
  }

  Future<List<SubplusSubFile>> fetchSubs(String tag) async {
    final url = await downloadUrl(tag);
    final resp = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
      throw SubplusException('zip download HTTP ${resp.statusCode}');
    }
    return extractSubs(resp.bodyBytes);
  }

  void close() => _client.close();

  static Map<String, dynamic> _decodeJson(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } catch (_) {
      throw SubplusException('bad response');
    }
  }
}

/// Extracts the `.srt`/`.ass` files from a pack ZIP. The UTF-8-named variant is preferred (sub-plus
/// ships both an ANSI/CP1256 and a UTF-8 copy) so we can skip a codepage decoder for now — see
/// doc 15 §7. The leading advertisement cue is stripped from `.srt`.
List<SubplusSubFile> extractSubs(Uint8List zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final all = <SubplusSubFile>[];
  for (final f in archive) {
    if (!f.isFile) continue;
    final name = f.name;
    final lower = name.toLowerCase();
    final ext = lower.endsWith('.srt')
        ? '.srt'
        : lower.endsWith('.ass')
            ? '.ass'
            : '';
    if (ext.isEmpty) continue;
    final bytes = f.readBytes();
    if (bytes == null || bytes.isEmpty) continue;
    var text = _decodeText(bytes);
    if (ext == '.srt') text = _stripAdCue(text);
    all.add(SubplusSubFile(name: name, ext: ext, text: text));
  }
  // Prefer *_UTF-8.srt over *_ANSI.srt when a pack ships both.
  all.sort((a, b) {
    int score(SubplusSubFile s) {
      final n = s.name.toLowerCase();
      if (n.contains('utf-8') || n.contains('utf8')) return 0;
      if (n.contains('ansi')) return 2;
      return 1;
    }

    return score(a).compareTo(score(b));
  });
  return all;
}

String _decodeText(Uint8List bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    b = b.sublist(3);
  }
  // allowMalformed: an ANSI/CP1256 file decoded as UTF-8 comes out mojibake rather than throwing;
  // callers should pick the UTF-8 variant. TODO(sushi): real Windows-1256 decode (doc 15 §7).
  return utf8.decode(b, allowMalformed: true);
}

String _stripAdCue(String srt) {
  final norm = srt.replaceAll('\r\n', '\n');
  final i = norm.indexOf('\n\n');
  if (i < 0) return srt;
  final first = norm.substring(0, i).toLowerCase();
  final isAd = first.contains('sub-plus') ||
      first.contains('subplus') ||
      first.contains('sub plus') ||
      norm.substring(0, i).contains('ساب پلاس') ||
      norm.substring(0, i).contains('ساب‌پلاس');
  if (!isAd) return srt;
  return norm.substring(i + 2).replaceFirst(RegExp(r'^\n+'), '');
}

List<String> _splitLines(String? s) {
  if (s == null) return const [];
  return s
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
}

bool _validDownloadUrl(String link) {
  final u = Uri.tryParse(link);
  if (u == null || u.host.isEmpty) return false;
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  // Guard the doc 15 §6 bug: a bad tag returns a link with the server's absolute path.
  if (u.path.contains('//') || !u.path.startsWith('/download/')) return false;
  return u.path.toLowerCase().endsWith('.zip');
}
