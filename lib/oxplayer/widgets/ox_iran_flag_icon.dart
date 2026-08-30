import 'package:flutter/material.dart';

/// Small Iran flag for metadata rows and subtitle pickers ([iran_splash_256.png]).
class OxIranFlagIcon extends StatelessWidget {
  final double size;

  const OxIranFlagIcon({this.size = 22, super.key});

  static const assetPath = 'assets/oxplayer/flags/iran_splash_256.png';

  @override
  Widget build(BuildContext context) {
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 96);
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      // A decorative flag must never take down a Row's layout: if the asset is
      // missing (e.g. dropped from pubspec), collapse to empty space instead of
      // Flutter's oversized error box.
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
}
