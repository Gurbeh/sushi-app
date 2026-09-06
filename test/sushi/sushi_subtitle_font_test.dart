import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/playback/ox_subtitle_font.dart';

void main() {
  group('SushiSubtitleFont', () {
    test('detects Persian language tags', () {
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('fa'), isTrue);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('fas'), isTrue);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('per'), isTrue);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('en'), isFalse);
      expect(SushiSubtitleFont.isPersianOrArabicLanguage('Unknown'), isFalse);
    });

    test('detects Arabic script in subtitle text', () {
      expect(SushiSubtitleFont.textUsesArabicScript('سلام دنیا'), isTrue);
      expect(SushiSubtitleFont.textUsesArabicScript('Hello world'), isFalse);
      expect(SushiSubtitleFont.textUsesArabicScript('این یک Hello است'), isTrue);
    });

    test('prefers track language over script', () {
      expect(
        SushiSubtitleFont.shouldUsePersianFont(language: 'fa', text: 'Hello'),
        isTrue,
      );
    });

    test('default settings use white fill with thin black outline', () {
      expect(SushiSubtitleFont.defaultSettings.color, equals(Colors.white));
      expect(SushiSubtitleFont.defaultSettings.outlineSize, 1);
    });

    test('assForceStyle includes outline and Persian font name', () {
      final style = SushiSubtitleFont.assForceStyle(
        SushiSubtitleFont.defaultSettings,
        language: 'fa',
      );
      expect(style, contains('FontName=Vazirmatn'));
      expect(style, contains('Outline=1'));
      expect(style, contains('OutlineColour='));
    });
  });
}
