import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';

void main() {
  const raw = '''1
00:00:01,000 --> 00:00:02,500
Hello
world

2
00:00:03,000 --> 00:00:04,000
Bye
''';

  test('parse/build round-trip keeps timing and text', () {
    final cues = sushiParseSrt(raw);
    expect(cues, hasLength(2));
    expect(cues[0].timing, '00:00:01,000 --> 00:00:02,500');
    expect(cues[0].text, 'Hello\nworld');
    expect(sushiParseSrt(sushiBuildSrt(cues)), hasLength(2));
    expect(sushiBuildSrt(cues), contains('Hello\nworld'));
  });

  test('batch splits when maxChars is small', () {
    final cues = sushiParseSrt(raw);
    final batches = sushiBatchSrtCues(cues, maxChars: 20);
    expect(batches, hasLength(2));
    expect(batches[0], hasLength(1));
  });

  test('default batch packs a short file into one request', () {
    final cues = List.generate(
      40,
      (i) => SushiSrtCue(
        index: i + 1,
        timing: '00:00:00,000 --> 00:00:01,000',
        text: 'Hi',
      ),
    );
    expect(sushiBatchSrtCues(cues), hasLength(1));
  });

  test('numbered payload maps translations back onto cues', () {
    final cues = sushiParseSrt(raw);
    final payload = sushiNumberedCuePayload(cues);
    expect(payload, contains('1. Hello | world'));
    expect(payload, contains('2. Bye'));
    final out = sushiApplyNumberedTranslations(cues, '1. سلام | دنیا\n2. خداحافظ\n');
    expect(out[0].text, 'سلام\nدنیا');
    expect(out[0].timing, cues[0].timing);
    expect(out[1].text, 'خداحافظ');
  });

  test('missing numbered lines keep the original text', () {
    final cues = sushiParseSrt(raw);
    final out = sushiApplyNumberedTranslations(cues, '2. فقط دومی');
    expect(out[0].text, cues[0].text);
    expect(out[1].text, 'فقط دومی');
  });

  test('split around playback takes nearby cues first', () {
    final cues = [
      for (var i = 0; i < 5; i++)
        SushiSrtCue(
          index: i + 1,
          timing: '00:0$i:00,000 --> 00:0$i:01,000',
          text: 'c$i',
        ),
    ];
    final w = sushiSplitCuesAroundPlayback(
      cues,
      const Duration(minutes: 2),
      ahead: const Duration(minutes: 2),
      behind: Duration.zero,
      maxNow: 10,
    );
    expect(w.now.map((c) => c.text).toList(), ['c2', 'c3']);
    expect(w.later.map((c) => c.text).toList(), ['c0', 'c1', 'c4']);
  });
}
