import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/subtitles/sushi_subtitle_actions.dart';

void main() {
  test('Automatic tries at most three ranked packs', () {
    expect(sushiAutoSubtitlePackAttempts, 3);
    expect(sushiSubtitlePackAttemptWindow([1, 2]), [1, 2]);
    expect(sushiSubtitlePackAttemptWindow([1, 2, 3]), [1, 2, 3]);
    expect(sushiSubtitlePackAttemptWindow([1, 2, 3, 4, 5]), [1, 2, 3]);
    expect(sushiSubtitlePackAttemptWindow(<int>[]), isEmpty);
  });
}
