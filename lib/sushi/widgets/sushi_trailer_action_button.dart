import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/sushi/providers/sushi_trailer_provider.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/widgets/sushi_trailer_player.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

/// Primary action plus the trailer, when the title is not watched.
/// Trailer is its own button. It does not depend on Play existing.
class SushiDetailPrimaryRow extends ConsumerWidget {
  final Widget? primary;
  final String itemId;
  final SushiKind kind;
  final String title;

  /// Same signal as the Resume label: playback progress or marked played.
  final bool engaged;

  const SushiDetailPrimaryRow({
    required this.itemId,
    required this.kind,
    required this.title,
    required this.primary,
    this.engaged = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sushiTrailerStateProvider((itemId: itemId, kind: kind))).valueOrNull;
    final beside = (state?.hasTrailer ?? false) && !(state?.watched ?? false) && !engaged;
    if (primary == null && !beside) return const SizedBox.shrink();
    if (!beside) return primary!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxWidth.isFinite;
        return Row(
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          spacing: 8,
          children: [
            if (primary != null)
              if (bounded) Flexible(child: primary!) else primary!,
            SushiTrailerActionButton(itemId: itemId, kind: kind, title: title),
          ],
        );
      },
    );
  }
}

/// Puts Trailer immediately above the last action (Movie info) once the title is watched or started.
List<ItemAction> sushiInsertWatchedTrailer(
  List<ItemAction> actions, {
  required SushiTrailerState? state,
  required void Function() onOpen,
  bool engaged = false,
}) {
  if (state == null || !state.hasTrailer || !(state.watched || engaged)) return actions;
  final trailer = ItemActionButton(
    icon: const Icon(IconsaxPlusLinear.video_play),
    label: const Text('Trailer'),
    action: onOpen,
  );
  if (actions.isEmpty) return [trailer];
  final next = [...actions];
  next.insert(next.length - 1, trailer);
  return next;
}

/// Shown beside Play only while the title is unwatched and a YouTube key exists.
class SushiTrailerActionButton extends ConsumerWidget {
  final String itemId;
  final SushiKind kind;
  final String title;

  const SushiTrailerActionButton({
    required this.itemId,
    required this.kind,
    required this.title,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailer = ref.watch(sushiTrailerStateProvider((itemId: itemId, kind: kind)));
    final state = trailer.valueOrNull;
    if (state == null || !state.showBesidePlay) return const SizedBox.shrink();
    return SelectableIconButton(
      selected: false,
      icon: IconsaxPlusLinear.video_play,
      label: 'Trailer',
      onPressed: () => SushiTrailerPlayer.open(
        context,
        youtubeKey: state.trailerKey,
        title: title,
      ),
    );
  }
}
