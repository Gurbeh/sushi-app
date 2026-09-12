import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:flutter_test/flutter_test.dart';

VersionStreamModel _stream({
  required int index,
  required String name,
  int height = 1080,
  bool hasSubs = false,
}) {
  return VersionStreamModel(
    name: name,
    index: index,
    id: 'ms_$index',
    defaultAudioStreamIndex: 1,
    defaultSubStreamIndex: hasSubs ? 2 : -1,
    videoStreams: [
      VideoStreamModel(
        name: '',
        codec: 'h264',
        isDefault: true,
        isExternal: false,
        index: 0,
        videoDoViTitle: null,
        videoRangeType: null,
        bitRate: null,
        width: height == 1080 ? 1920 : 1280,
        height: height,
        frameRate: 24,
      ),
    ],
    audioStreams: const [],
    subStreams: const [],
  );
}

void main() {
  group('sushiPickVersionStreamIndex cold default', () {
    test('prefers 1080 soft sub', () {
      final streams = [
        _stream(index: 0, name: '720p Dub Persian', height: 720),
        _stream(index: 1, name: '1080p Dub Persian', height: 1080),
        _stream(index: 2, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
      ];
      expect(
        sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset),
        2,
      );
    });

    test('falls back to first 1080 when no soft sub', () {
      final streams = [
        _stream(index: 0, name: '720p English', height: 720),
        _stream(index: 1, name: '1080p English', height: 1080),
      ];
      expect(
        sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset),
        1,
      );
    });

    test('falls back to 720 tier when no 1080', () {
      final streams = [
        _stream(index: 0, name: '480p English', height: 480),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      expect(
        sushiPickVersionStreamIndex(streams, SushiMediaVariantPreference.unset),
        1,
      );
    });
  });

  group('sushiPickVersionStreamIndex user preference', () {
    test('remembers 720 quality', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      const pref = SushiMediaVariantPreference(qualityHeight: 720);
      expect(sushiPickVersionStreamIndex(streams, pref), 1);
    });

    test('remembers dubbed with fallback to soft sub at same tier', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p Dub Persian', height: 720),
      ];
      const pref = SushiMediaVariantPreference(
        qualityHeight: 1080,
        delivery: SushiStreamDelivery.dubbed,
      );
      expect(sushiPickVersionStreamIndex(streams, pref), 0);
    });

    test('carries dubbed preference to lower tier when preferred tier has no match', () {
      final streams = [
        _stream(index: 0, name: '720p Dub Persian', height: 720),
        _stream(index: 1, name: '1080p English', height: 1080),
      ];
      const pref = SushiMediaVariantPreference(
        qualityHeight: 1080,
        delivery: SushiStreamDelivery.dubbed,
      );
      expect(sushiPickVersionStreamIndex(streams, pref), 0);
    });
  });

  group('sushiClassifyVersionStream', () {
    test('detects dubbed from label', () {
      final meta = sushiClassifyVersionStream(_stream(index: 0, name: '1080p Dub Persian'));
      expect(meta.delivery, SushiStreamDelivery.dubbed);
      expect(meta.qualityHeight, 1080);
    });

    test('extracts resolution from an underscore-delimited raw filename', () {
      final meta = sushiClassifyVersionStream(_stream(
        index: 0,
        name: 'One_Night_Only_2026_1080p_10bit_WEB_DL_6CH_x265_SoftSub_DigiMovi.mkv',
      ));
      expect(meta.qualityHeight, 1080);
      expect(meta.delivery, SushiStreamDelivery.softSub);
    });
  });

  group('sushiFindVersionStreamIndexForPreference', () {
    test('returns null with no preference set', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      expect(
        sushiFindVersionStreamIndexForPreference(streams, SushiMediaVariantPreference.unset),
        isNull,
      );
    });

    test('returns null with fewer than two versions even if a preference is set', () {
      final streams = [_stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true)];
      const pref = SushiMediaVariantPreference(qualityHeight: 720);
      expect(sushiFindVersionStreamIndexForPreference(streams, pref), isNull);
    });

    test('finds the matching index when a preference matches', () {
      final streams = [
        _stream(index: 0, name: '1080p SoftSub Persian', height: 1080, hasSubs: true),
        _stream(index: 1, name: '720p SoftSub Persian', height: 720, hasSubs: true),
      ];
      const pref = SushiMediaVariantPreference(qualityHeight: 720);
      expect(sushiFindVersionStreamIndexForPreference(streams, pref), 1);
    });
  });
}
