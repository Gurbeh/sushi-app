import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/localization_helper.dart';

class SushiHelpContent extends StatelessWidget {
  const SushiHelpContent({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = SushiEnv.telegramBotOpenLink;
    final bot = SushiEnv.botUsername;
    final qrSize = (MediaQuery.sizeOf(context).shortestSide * 0.42).clamp(160.0, 220.0);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (embedded) ...[
          Text(
            context.localized.sushiHelpTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
        ],
        if (link != null) ...[
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrImageView(
                data: link,
                size: qrSize,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.localized.sushiHelpQrCaption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          context.localized.sushiHelpBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (link == null) ...[
          const SizedBox(height: 16),
          Text(
            context.localized.sushiHelpBotNotConfigured,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (link != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => launchUrl(context, link),
            icon: const Icon(Icons.telegram),
            label: Text(context.localized.sushiHelpOpenBot(bot ?? '')),
          ),
        ],
      ],
    );

    if (embedded) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: body);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: body,
    );
  }
}
