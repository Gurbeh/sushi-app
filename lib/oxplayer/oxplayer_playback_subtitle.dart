import 'package:collection/collection.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/playback/ox_persian_language.dart';

/// True when MediaSource / version label indicates burned-in (hard) subtitles.
bool oxplayerMediaSourceLooksHardSub(String? mediaSourceName) {
  final blob = (mediaSourceName ?? '').toLowerCase().trim();
  if (blob.isEmpty) return false;
  return RegExp(r'hard[\s_-]*sub').hasMatch(blob) ||
      blob.contains('hardsub') ||
      blob.contains('burned') ||
      blob.contains('زیرنویس چسبیده');
}

/// Resolves subtitle index when Fladder remembered Off / null but the server
/// (or preferred fa→en track) wants subtitles on.
///
/// Hardsub sources default to Off: enabling soft Persian on top of burn-in
/// stacks a second identical subtitle on Android ExoPlayer.
int? oxplayerResolveSubtitleStreamIndex({
  required int? selectedIndex,
  required int? serverDefaultIndex,
  required List<SubStreamModel>? subStreams,
  String? mediaSourceName,
}) {
  if (!OxplayerConfig.isEnabled) return selectedIndex;

  final selectedOn = selectedIndex != null &&
      selectedIndex != -1 &&
      subStreams?.any((s) => s.index == selectedIndex) == true;
  if (selectedOn) return selectedIndex;

  if (oxplayerMediaSourceLooksHardSub(mediaSourceName)) {
    return -1;
  }

  // Explicit server Off — do not force preferred fa/en over it.
  if (serverDefaultIndex == -1) {
    return -1;
  }

  if (serverDefaultIndex != null &&
      serverDefaultIndex != -1 &&
      subStreams?.any((s) => s.index == serverDefaultIndex) == true) {
    return serverDefaultIndex;
  }

  return oxplayerPreferredSubtitleStreamIndex(subStreams) ?? selectedIndex;
}

/// Muxed/external tracks have a codec and/or URL. Sushi `sub_langs` catalog
/// codes are empty-codec stubs — they are not a playable Farsi softsub.
bool oxplayerSubtitleTrackIsPlayable(SubStreamModel s) {
  if (s.index == -1) return false;
  final url = s.url?.trim() ?? '';
  if (url.isNotEmpty) return true;
  return s.codec.trim().isNotEmpty;
}

/// True when the container already has a playable Persian (Farsi) soft subtitle.
bool oxplayerHasPersianSoftSub(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return false;
  return subStreams.any((s) =>
      oxplayerSubtitleTrackIsPlayable(s) &&
      (OxPersianLanguage.isPersianLanguage(s.language) ||
          OxPersianLanguage.isPersianLanguage(s.displayTitle)));
}

/// What to apply at playback start. Previous title's AI / Automatic pick must not carry over.
enum SushiStartSubtitle { persianSoft, automaticOnline, off }

SushiStartSubtitle sushiStartSubtitleChoice({
  required bool hardSub,
  required bool hasPersianSoft,
  bool subtitleOff = false,
}) {
  if (hardSub) return SushiStartSubtitle.off;
  if (hasPersianSoft && !subtitleOff) return SushiStartSubtitle.persianSoft;
  return SushiStartSubtitle.automaticOnline;
}

/// Persian first, then English, else first real track.
int? oxplayerPreferredSubtitleStreamIndex(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final real = subStreams.where((s) => s.index != -1).toList();
  if (real.isEmpty) return null;

  final persian = real.firstWhereOrNull(
    (s) =>
        OxPersianLanguage.isPersianLanguage(s.language) ||
        OxPersianLanguage.isPersianLanguage(s.displayTitle),
  );
  if (persian != null) return persian.index;

  final english = real.firstWhereOrNull((s) {
    final lang = s.language.trim().toLowerCase();
    final title = s.displayTitle.trim().toLowerCase();
    return lang == 'en' ||
        lang == 'eng' ||
        lang.startsWith('en-') ||
        title.contains('english') ||
        title == 'en';
  });
  if (english != null) return english.index;

  return real.first.index;
}
