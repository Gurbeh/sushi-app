import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:fladder/sushi/widgets/sushi_series_episode_picker_icon_button.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/sushi/sushi_config.dart';

class SushiSeriesDetailPlayButtons extends ConsumerWidget {
  final SeriesModel series;
  final EpisodeModel episode;
  final Future<void> Function(bool restart) onPlay;
  final Future<void> Function(bool restart)? onLongPlay;
  final VoidCallback? onEpisodePlayed;

  const SushiSeriesDetailPlayButtons({
    required this.series,
    required this.episode,
    required this.onPlay,
    this.onLongPlay,
    this.onEpisodePlayed,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickerSeasons = sushiSeriesPickerSeasons(series);
    final episodeCount = pickerSeasons.fold<int>(0, (sum, season) => sum + (season.episodeCount > 0 ? season.episodeCount : season.episodes.length));
    final showEpisodePicker = episodeCount > 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: MediaPlayButton(
            item: episode,
            onPressed: onPlay,
            onLongPressed: onLongPlay,
          ),
        ),
        if (showEpisodePicker) ...[
          const SizedBox(width: 4),
          SushiSeriesEpisodePickerIconButton(
            series: series,
            onEpisodePlayed: onEpisodePlayed,
          ),
        ],
      ],
    );
  }
}
