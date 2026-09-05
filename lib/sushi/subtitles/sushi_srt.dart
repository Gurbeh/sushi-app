/// Minimal SRT cue parser / writer for Sushi translate.
///
/// Timestamps stay local. Only [SushiSrtCue.text] is sent to Gemini.

class SushiSrtCue {
  const SushiSrtCue({required this.index, required this.timing, required this.text});

  final int index;
  final String timing;
  final String text;
}

final _cueSplit = RegExp(r'\n\s*\n');
final _indexLine = RegExp(r'^\d+\s*$');

List<SushiSrtCue> sushiParseSrt(String raw) {
  final norm = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (norm.isEmpty) return const [];
  final out = <SushiSrtCue>[];
  var n = 1;
  for (final block in norm.split(_cueSplit)) {
    final lines = block.split('\n').map((l) => l.trimRight()).toList();
    if (lines.isEmpty) continue;
    var i = 0;
    if (_indexLine.hasMatch(lines.first.trim())) i = 1;
    if (i >= lines.length) continue;
    final timing = lines[i].trim();
    if (!timing.contains('-->')) continue;
    final text = lines.skip(i + 1).join('\n').trim();
    if (text.isEmpty) continue;
    out.add(SushiSrtCue(index: n, timing: timing, text: text));
    n++;
  }
  return out;
}

String sushiBuildSrt(List<SushiSrtCue> cues) {
  final buf = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    buf
      ..writeln('${i + 1}')
      ..writeln(c.timing)
      ..writeln(c.text);
    if (i != cues.length - 1) buf.writeln();
  }
  return buf.toString();
}

/// Packs cue texts into batches under [maxChars] for one Gemini call each.
List<List<SushiSrtCue>> sushiBatchSrtCues(List<SushiSrtCue> cues, {int maxChars = 24000}) {
  if (cues.isEmpty) return const [];
  final batches = <List<SushiSrtCue>>[];
  var cur = <SushiSrtCue>[];
  var size = 0;
  for (final c in cues) {
    final add = c.text.length + 8;
    if (cur.isNotEmpty && size + add > maxChars) {
      batches.add(cur);
      cur = <SushiSrtCue>[];
      size = 0;
    }
    cur.add(c);
    size += add;
  }
  if (cur.isNotEmpty) batches.add(cur);
  return batches;
}

/// `1. line` numbered payload Gemini is asked to translate, one cue per line.
String sushiNumberedCuePayload(List<SushiSrtCue> cues) {
  final buf = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final flat = cues[i].text.replaceAll('\n', ' | ');
    buf.writeln('${i + 1}. $flat');
  }
  return buf.toString();
}

/// Maps numbered reply lines back onto [cues]. Missing lines keep the original text.
List<SushiSrtCue> sushiApplyNumberedTranslations(List<SushiSrtCue> cues, String reply) {
  final map = <int, String>{};
  for (final raw in reply.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = RegExp(r'^(\d+)\.\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    final i = int.tryParse(m.group(1)!);
    if (i == null) continue;
    var text = m.group(2)!.trim();
    if (text.isEmpty) continue;
    text = text.replaceAll(' | ', '\n');
    map[i] = text;
  }
  return [
    for (var i = 0; i < cues.length; i++)
      SushiSrtCue(
        index: cues[i].index,
        timing: cues[i].timing,
        text: map[i + 1] ?? cues[i].text,
      ),
  ];
}

Duration? sushiSrtCueStart(SushiSrtCue cue) {
  final m = RegExp(r'^(\d+):(\d{2}):(\d{2})[,.](\d+)').firstMatch(cue.timing.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  var ms = int.parse(m.group(4)!);
  switch (m.group(4)!.length) {
    case 1:
      ms *= 100;
    case 2:
      ms *= 10;
  }
  return Duration(hours: h, minutes: min, seconds: sec, milliseconds: ms);
}

class SushiSrtWindow {
  const SushiSrtWindow({required this.now, required this.later});
  final List<SushiSrtCue> now;
  final List<SushiSrtCue> later;
}

/// Cues around [position] for a first Gemini call. Rest can translate in the background.
SushiSrtWindow sushiSplitCuesAroundPlayback(
  List<SushiSrtCue> cues,
  Duration position, {
  Duration ahead = const Duration(minutes: 12),
  Duration behind = const Duration(seconds: 20),
  int maxNow = 150,
}) {
  if (cues.isEmpty) return const SushiSrtWindow(now: [], later: []);
  final start = position < behind ? Duration.zero : position - behind;
  final end = position + ahead;
  final now = <SushiSrtCue>[];
  final later = <SushiSrtCue>[];
  for (final c in cues) {
    final t = sushiSrtCueStart(c) ?? Duration.zero;
    if (t >= start && t < end && now.length < maxNow) {
      now.add(c);
    } else {
      later.add(c);
    }
  }
  if (now.isNotEmpty) return SushiSrtWindow(now: now, later: later);
  final after = [for (final c in cues) if ((sushiSrtCueStart(c) ?? Duration.zero) >= position) c];
  final pick = (after.isNotEmpty ? after : cues).take(maxNow).toList();
  final picked = pick.map((c) => c.timing).toSet();
  return SushiSrtWindow(
    now: pick,
    later: [for (final c in cues) if (!picked.contains(c.timing)) c],
  );
}

String sushiMergeSrtByTiming(List<SushiSrtCue> a, List<SushiSrtCue> b) {
  final all = [...a, ...b]..sort((x, y) {
        final dx = sushiSrtCueStart(x) ?? Duration.zero;
        final dy = sushiSrtCueStart(y) ?? Duration.zero;
        return dx.compareTo(dy);
      });
  return sushiBuildSrt(all);
}
