import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_playback_subtitle.dart';

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
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '1080p - hard sub (Persian)',
      ),
      -1,
    );
  });

  test('softsub still prefers Persian when no selection', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: null,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      3,
    );
  });

  test('server Off is respected (no forced Persian)', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      -1,
    );
  });

  test('explicit user selection wins over hardsub Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
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
    expect(oxplayerHasPersianSoftSub(streams), isFalse);
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: false),
      SushiStartSubtitle.automaticOnline,
    );
  });

  test('Farsi softsub wins; hardsub stays Off; no softsub runs Automatic', () {
    expect(
      sushiStartSubtitleChoice(hardSub: false, hasPersianSoft: true),
      SushiStartSubtitle.persianSoft,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: false),
      SushiStartSubtitle.off,
    );
    expect(
      sushiStartSubtitleChoice(hardSub: true, hasPersianSoft: true),
      SushiStartSubtitle.off,
    );
    expect(oxplayerHasPersianSoftSub([_sub(index: 3, language: 'fa', displayTitle: 'Persian')]), isTrue);
    expect(oxplayerHasPersianSoftSub([SubStreamModel.no()]), isFalse);
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
    expect(oxplayerSubtitleTrackIsPlayable(stub), isFalse);
    expect(oxplayerHasPersianSoftSub([SubStreamModel.no(), stub]), isFalse);
    expect(
      sushiStartSubtitleChoice(
        hardSub: false,
        hasPersianSoft: oxplayerHasPersianSoftSub([SubStreamModel.no(), stub]),
      ),
      SushiStartSubtitle.automaticOnline,
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
}
