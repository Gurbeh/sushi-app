import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';

SubStreamModel _sub({
  required int index,
  required String language,
  String displayTitle = '',
}) {
  return SubStreamModel(
    name: displayTitle,
    id: '$index',
    title: displayTitle,
    displayTitle: displayTitle.isEmpty ? language : displayTitle,
    language: language,
    codec: 'subrip',
    isDefault: false,
    isExternal: false,
    index: index,
  );
}

void main() {
  test('hardsub media source defaults subtitle Off', () {
    final streams = [
      SubStreamModel.no(),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '1080p - hard sub (Persian)',
      ),
      -1,
    );
  });

  test('چسبیده without muxed srt is treated as hardsub at playback', () {
    expect(
      sushiMediaSourceLooksHardSub('720p HDTS زیرنویس_فارسی_چسبیده', subStreams: [SubStreamModel.no()]),
      isTrue,
    );
  });

  test('چسبیده with a muxed srt is not hardsub', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(sushiMediaSourceLooksHardSub('زیرنویس_فارسی_چسبیده', subStreams: streams), isFalse);
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '720p HDTS زیرنویس_فارسی_چسبیده',
      ),
      2,
    );
  });

  test('softsub still prefers Persian when no selection', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: null,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      3,
    );
  });

  test('server Off is overridden by an available Persian softsub', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      2,
    );
  });

  test('server Off with no Persian available stays Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      -1,
    );
  });

  test('server default is non-Persian (English) but Persian available -> Persian wins', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: 2,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      3,
    );
  });

  test('explicit user selection wins over hardsub Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      sushiResolveSubtitleStreamIndex(
        selectedIndex: 2,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p HardSub',
      ),
      2,
    );
  });

  test('english-only softsub is not treated as Farsi', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
    ];
    expect(sushiHasPersianSoftSub(streams), isFalse);
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false),
      SushiStartSubtitle.automaticOnline,
    );
  });

  test('non-hard-sub always starts Automatic; Farsi soft is last fallback', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true),
      SushiStartSubtitle.automaticOnline,
    );
    expect(
      sushiStartSubtitleSteps(hardSub: false, hasPersianSoft: true, aiSet: false),
      [SushiStartSubtitleStep.automaticOnline, SushiStartSubtitleStep.persianSoft],
    );
    expect(
      sushiStartSubtitleSteps(hardSub: false, hasPersianSoft: true, aiSet: true),
      [
        SushiStartSubtitleStep.automaticOnline,
        SushiStartSubtitleStep.aiTranslate,
        SushiStartSubtitleStep.persianSoft,
      ],
    );
    expect(
      sushiStartSubtitleSteps(hardSub: false, hasPersianSoft: false, aiSet: true),
      [SushiStartSubtitleStep.automaticOnline, SushiStartSubtitleStep.aiTranslate],
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: true),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleSteps(hardSub: true, hasPersianSoft: true, aiSet: true),
      isEmpty,
    );
    expect(sushiHasPersianSoftSub([_sub(index: 3, language: 'fa', displayTitle: 'Persian')]), isTrue);
    expect(sushiHasPersianSoftSub([SubStreamModel.no()]), isFalse);
  });

  test('catalog-only fa lang code is not a playable Farsi softsub', () {
    final stub = SubStreamModel(
      name: 'FA',
      id: 'sushi_sub_1_0',
      title: 'FA',
      displayTitle: 'FA',
      language: 'fa',
      codec: '',
      isDefault: true,
      isExternal: false,
      index: 0,
    );
    expect(sushiSubtitleTrackIsPlayable(stub), isFalse);
    expect(sushiHasPersianSoftSub([SubStreamModel.no(), stub]), isFalse);
    expect(
      sushiStartSubtitleChoice(
        hardSub: false,
        hasPersianSoft: sushiHasPersianSoftSub([SubStreamModel.no(), stub]),
      ),
      SushiStartSubtitle.automaticOnline,
    );
    expect(
      sushiStartSubtitleSteps(
        hardSub: false,
        hasPersianSoft: sushiHasPersianSoftSub([SubStreamModel.no(), stub]),
        aiSet: false,
      ),
      [SushiStartSubtitleStep.automaticOnline],
    );
  });

  test('Off selection still runs Automatic even if a Farsi track exists', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true, subtitleOff: true),
      SushiStartSubtitle.automaticOnline,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: true, subtitleOff: true),
      SushiStartSubtitle.off,
    );
  });

  test('English hardsub stays Off; audio language does not reopen Automatic', () {
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false, isEnglishAudio: true),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleSteps(
        hardSub: true,
        hasPersianSoft: true,
        aiSet: true,
      ),
      isEmpty,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false, isEnglishAudio: false),
      SushiStartSubtitle.off,
    );
  });

  test('bare 720p label is unknown, not hardsub', () {
    expect(sushiMediaSourceLooksHardSub('720p'), isFalse);
  });

  test('HDTS filename is treated as hardsub', () {
    expect(
      sushiMediaSourceLooksHardSub(
        'Spider_Man_Brand_New_Day_2026_720P_Hdts_MyMoviz_video_converter.mp4',
      ),
      isTrue,
    );
  });

  test('Iranian content skips auto subtitle entirely, even with hardsub off', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false, isIranian: true),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true, isEnglishAudio: true, isIranian: true),
      SushiStartSubtitle.off,
    );
  });

  test('sushiIsEnglishLanguage matches en/eng/en-* only', () {
    expect(sushiIsEnglishLanguage('en'), isTrue);
    expect(sushiIsEnglishLanguage('eng'), isTrue);
    expect(sushiIsEnglishLanguage('en-US'), isTrue);
    expect(sushiIsEnglishLanguage('fa'), isFalse);
    expect(sushiIsEnglishLanguage(null), isFalse);
  });
}
