import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/localization_helper.dart';

class SushiHelpHeaderIconButton extends StatelessWidget {
  const SushiHelpHeaderIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final buttonStyle = Theme.of(context).filledButtonTheme.style?.copyWith(
          backgroundColor: WidgetStatePropertyAll(surfaceColor.withValues(alpha: 0.8)),
        );
    return AspectRatio(
      aspectRatio: 1.0,
      child: IconButton.filledTonal(
        style: buttonStyle,
        tooltip: context.localized.sushiHelpNavLabel,
        onPressed: () => context.router.push(const SushiHelpRoute()),
        icon: const Icon(IconsaxPlusLinear.message_question),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
