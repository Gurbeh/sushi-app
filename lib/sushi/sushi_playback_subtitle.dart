import 'package:collection/collection.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';

/// True when MediaSource / version label indicates burned-in (hard) subtitles.
bool sushiMediaSourceLooksHardSub(String? mediaSourceName) {
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
int? sushiResolveSubtitleStreamIndex({
  required int? selectedIndex,
  required int? serverDefaultIndex,
  required List<SubStreamModel>? subStreams,
  String? mediaSourceName,
}) {
  

  final selectedOn = selectedIndex != null &&
      selectedIndex != -1 &&
      subStreams?.any((s) => s.index == selectedIndex) == true;
  if (selectedOn) return selectedIndex;

  if (sushiMediaSourceLooksHardSub(mediaSourceName)) {
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

  return sushiPreferredSubtitleStreamIndex(subStreams) ?? selectedIndex;
}

/// Muxed/external tracks have a codec and/or URL. Sushi `sub_langs` catalog
/// codes are empty-codec stubs — they are not a playable Farsi softsub.
bool sushiSubtitleTrackIsPlayable(SubStreamModel s) {
  if (s.index == -1) return false;
  final url = s.url?.trim() ?? '';
  if (url.isNotEmpty) return true;
  return s.codec.trim().isNotEmpty;
}

/// True when the container already has a playable Persian (Farsi) soft subtitle.
bool sushiHasPersianSoftSub(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return false;
  return subStreams.any((s) =>
      sushiSubtitleTrackIsPlayable(s) &&
      (SushiPersianLanguage.isPersianLanguage(s.language) ||
          SushiPersianLanguage.isPersianLanguage(s.displayTitle)));
}

/// What to apply at playback start. Previous title's AI / Automatic pick must not carry over.
enum SushiStartSubtitle { persianSoft, automaticOnline, off }

/// True when a track's language/title codes read as English ('en', 'eng', 'en-*', or a title
/// that says so). Same rule [sushiPreferredSubtitleStreamIndex] uses to spot an English track.
bool sushiIsEnglishLanguage(String? language) {
  final lang = (language ?? '').trim().toLowerCase();
  return lang == 'en' || lang == 'eng' || lang.startsWith('en-');
}

/// Hardsub sources default to Off (stacking soft Persian on top of burn-in duplicates the
/// subtitle on Android ExoPlayer) — except an English hardsub print, which still has no Persian
/// on screen, so Automatic (online) still runs.
SushiStartSubtitle sushiStartSubtitleChoice({
  required bool hardSub,
  required bool hasPersianSoft,
  bool subtitleOff = false,
  bool isEnglishAudio = false,
}) {
  if (hardSub) return isEnglishAudio ? SushiStartSubtitle.automaticOnline : SushiStartSubtitle.off;
  if (hasPersianSoft && !subtitleOff) return SushiStartSubtitle.persianSoft;
  return SushiStartSubtitle.automaticOnline;
}

/// Persian first, then English, else first real track.
int? sushiPreferredSubtitleStreamIndex(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final real = subStreams.where((s) => s.index != -1).toList();
  if (real.isEmpty) return null;

  final persian = real.firstWhereOrNull(
    (s) =>
        SushiPersianLanguage.isPersianLanguage(s.language) ||
        SushiPersianLanguage.isPersianLanguage(s.displayTitle),
  );
  if (persian != null) return persian.index;

  final english = real.firstWhereOrNull((s) {
    final title = s.displayTitle.trim().toLowerCase();
    return sushiIsEnglishLanguage(s.language) || title.contains('english') || title == 'en';
  });
  if (english != null) return english.index;

  return real.first.index;
}
