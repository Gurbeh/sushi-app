import 'package:collection/collection.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';

/// True when MediaSource / version label indicates burned-in (hard) subtitles.
///
/// `زیرنویس چسبیده` is only a claim. The container decides: a playable srt/ass track means
/// softsub; no playable track plus that claim means hardsub.
bool sushiMediaSourceLooksHardSub(String? mediaSourceName, {List<SubStreamModel>? subStreams}) {
  // Catalog `sub_langs` stubs have an index and no codec. That is still a muxed track.
  if (subStreams != null && subStreams.any((s) => s.index != -1)) {
    return false;
  }
  final blob = (mediaSourceName ?? '').toLowerCase().trim();
  if (blob.isEmpty) return false;
  final explicit = RegExp(r'hard[\s_-]*sub').hasMatch(blob) ||
      blob.contains('hardsub') ||
      blob.contains('burned') ||
      blob.contains('هاردساب') ||
      blob.contains('هارد ساب') ||
      RegExp(r'(^|[^a-z])hdts([^a-z]|$)').hasMatch(blob) ||
      blob.contains('hdcam');
  if (explicit) return true;
  final claimed = blob.contains('چسبیده') || blob.contains('زیرنویس') || blob.contains('سافت');
  return claimed && !sushiHasPlayableSub(subStreams);
}

bool sushiHasPlayableSub(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return false;
  return subStreams.any(sushiSubtitleTrackIsPlayable);
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
  bool isPersianTrack(int? index) {
    if (index == null || index == -1) return false;
    final track = subStreams?.firstWhereOrNull((s) => s.index == index);
    if (track == null) return false;
    return SushiPersianLanguage.isPersianLanguage(track.language) ||
        SushiPersianLanguage.isPersianLanguage(track.displayTitle);
  }

  final persianIndex = sushiPreferredPersianStreamIndex(subStreams);

  final selectedOn = selectedIndex != null &&
      selectedIndex != -1 &&
      subStreams?.any((s) => s.index == selectedIndex) == true;
  if (selectedOn) {
    // A Persian soft track exists but the current pick isn't it — prefer Persian.
    if (persianIndex != null && !isPersianTrack(selectedIndex)) {
      return persianIndex;
    }
    return selectedIndex;
  }

  if (sushiMediaSourceLooksHardSub(mediaSourceName, subStreams: subStreams)) {
    return -1;
  }

  // Server default Off — still prefer an available Persian soft track over staying off.
  if (serverDefaultIndex == -1) {
    return persianIndex ?? -1;
  }

  if (serverDefaultIndex != null &&
      serverDefaultIndex != -1 &&
      subStreams?.any((s) => s.index == serverDefaultIndex) == true) {
    if (persianIndex != null && !isPersianTrack(serverDefaultIndex)) {
      return persianIndex;
    }
    return serverDefaultIndex;
  }

  return persianIndex ?? sushiPreferredSubtitleStreamIndex(subStreams) ?? selectedIndex;
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
enum SushiStartSubtitle { persianSoft, sniffEmbedded, automaticOnline, off }

/// What to select at playback start, and which follow-up to run.
class SushiStartSubtitlePlan {
  const SushiStartSubtitlePlan({required this.choice, required this.index});

  final SushiStartSubtitle choice;

  /// Track index to select. -1 leaves subtitles off.
  final int index;
}

/// `fa` label wins. `en` / empty / und gets a text sniff before online. Anything else goes online.
SushiStartSubtitlePlan sushiPlanStartSubtitle({
  required List<SubStreamModel>? subStreams,
  String? mediaSourceName,
  bool isIranian = false,
}) {
  final hardSub = sushiMediaSourceLooksHardSub(mediaSourceName, subStreams: subStreams);
  final persianIndex = sushiPreferredPersianStreamIndex(subStreams);
  final sniffIndex = sushiScriptSniffSubtitleIndex(subStreams);
  final choice = sushiStartSubtitleChoice(
    hardSub: hardSub,
    hasPersianSoft: persianIndex != null,
    needsScriptSniff: sniffIndex != null,
    isIranian: isIranian,
  );
  final index = switch (choice) {
    SushiStartSubtitle.persianSoft => persianIndex ?? -1,
    SushiStartSubtitle.sniffEmbedded => sniffIndex ?? -1,
    SushiStartSubtitle.automaticOnline || SushiStartSubtitle.off => -1,
  };
  return SushiStartSubtitlePlan(choice: choice, index: index);
}

/// English, empty, or undetermined container tags. A real `fa` label is not sniffed.
bool sushiSubtitleLanguageNeedsScriptSniff(String? language) {
  if (SushiPersianLanguage.isPersianLanguage(language)) return false;
  final lang = (language ?? '').trim().toLowerCase();
  if (lang.isEmpty || lang == 'und' || lang == 'unknown' || lang == 'mul') return true;
  return sushiIsEnglishLanguage(language);
}

/// First muxed track whose label is English or unknown. Null when a Persian label exists.
int? sushiScriptSniffSubtitleIndex(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  if (sushiPreferredPersianStreamIndex(subStreams) != null) return null;
  final track = subStreams.where((s) => s.index != -1).firstWhereOrNull(
        (s) => sushiSubtitleLanguageNeedsScriptSniff(s.language),
      );
  return track?.index;
}

/// Ordered start pipeline for a non-hard-sub item. Hard-sub is always empty (Off) —
/// burn-in must not get Automatic / AI / muxed Farsi stacked on top, including English-audio
/// prints (doc 15 §7: Persian-scene hardsub of an English movie already has Farsi on screen).
enum SushiStartSubtitleStep { automaticOnline, aiTranslate, persianSoft }

/// True when a track's language/title codes read as English ('en', 'eng', 'en-*', or a title
/// that says so). Same rule [sushiPreferredSubtitleStreamIndex] uses to spot an English track.
bool sushiIsEnglishLanguage(String? language) {
  final lang = (language ?? '').trim().toLowerCase();
  return lang == 'en' || lang == 'eng' || lang.startsWith('en-');
}

/// `fa` label is the whole chain (select that track, stop). Otherwise Automatic, then AI.
/// Hard-sub skips the chain (Off). English audio does not reopen it.
List<SushiStartSubtitleStep> sushiStartSubtitleSteps({
  required bool hardSub,
  required bool hasPersianSoft,
  required bool aiSet,
}) {
  if (hardSub) return const [];
  if (hasPersianSoft) return const [SushiStartSubtitleStep.persianSoft];
  return [
    SushiStartSubtitleStep.automaticOnline,
    if (aiSet) SushiStartSubtitleStep.aiTranslate,
  ];
}

/// `fa` label selects that track and stops. English or unknown labels sniff cue text first.
/// Hardsub stays Off. English audio does not change that (doc 15 §7).
///
/// Iranian content is skipped entirely: it's already Persian, so auto subtitle search has
/// nothing useful to look for.
SushiStartSubtitle sushiStartSubtitleChoice({
  required bool hardSub,
  required bool hasPersianSoft,
  bool needsScriptSniff = false,
  bool subtitleOff = false,
  bool isEnglishAudio = false,
  bool isIranian = false,
}) {
  if (isIranian) return SushiStartSubtitle.off;
  if (hardSub) return SushiStartSubtitle.off;
  if (hasPersianSoft) return SushiStartSubtitle.persianSoft;
  if (needsScriptSniff) return SushiStartSubtitle.sniffEmbedded;
  return SushiStartSubtitle.automaticOnline;
}

/// First playable Persian (Farsi) track, or null when none is available.
int? sushiPreferredPersianStreamIndex(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final real = subStreams.where((s) => s.index != -1).toList();
  if (real.isEmpty) return null;

  final persian = real.firstWhereOrNull(
    (s) =>
        SushiPersianLanguage.isPersianLanguage(s.language) ||
        SushiPersianLanguage.isPersianLanguage(s.displayTitle),
  );
  return persian?.index;
}

/// Persian first, then English, else first real track.
int? sushiPreferredSubtitleStreamIndex(List<SubStreamModel>? subStreams) {
  if (subStreams == null || subStreams.isEmpty) return null;
  final real = subStreams.where((s) => s.index != -1).toList();
  if (real.isEmpty) return null;

  final persianIndex = sushiPreferredPersianStreamIndex(subStreams);
  if (persianIndex != null) return persianIndex;

  final english = real.firstWhereOrNull((s) {
    final title = s.displayTitle.trim().toLowerCase();
    return sushiIsEnglishLanguage(s.language) || title.contains('english') || title == 'en';
  });
  if (english != null) return english.index;

  return real.first.index;
}

/// Rewrite one muxed track's label to Persian after a text sniff.
MediaStreamsModel? sushiRelabelSubtitleAsPersian(MediaStreamsModel? streams, int index) {
  if (streams == null || index < 0) return streams;
  final current = streams.currentVersionStream;
  if (current == null) return streams;
  final versions = [
    for (final version in streams.versionStreams)
      identical(version, current)
          ? VersionStreamModel(
              name: version.name,
              index: version.index,
              id: version.id,
              defaultAudioStreamIndex: version.defaultAudioStreamIndex,
              defaultSubStreamIndex: index,
              videoStreams: version.videoStreams,
              audioStreams: version.audioStreams,
              subStreams: [
                for (final sub in version.subStreams)
                  sub.index == index
                      ? sub.copyWith(language: 'fa', displayTitle: 'FA', name: 'FA', title: 'FA')
                      : sub,
              ],
            )
          : version,
  ];
  return streams.copyWith(defaultSubStreamIndex: index, versionStreams: versions);
}
