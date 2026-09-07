import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/items/series_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/sushi_library_detail_labels.dart';
import 'package:fladder/sushi/sushi_detail_loading.dart';
import 'package:fladder/sushi/sushi_media_streams.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';
import 'package:fladder/sushi/widgets/sushi_detail_action_layout.dart';
import 'package:fladder/sushi/widgets/sushi_series_detail_play_buttons.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_flags.dart';
import 'package:fladder/sushi/sushi_playable.dart';
import 'package:fladder/sushi/sushi_request_button.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/episode_posters.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/media/season_row.dart';
import 'package:fladder/screens/shared/media/special_features_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const SeriesDetailScreen({required this.item, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  AutoDisposeStateNotifierProvider<SeriesDetailViewNotifier, SeriesModel?> get providerId =>
      seriesDetailsProvider(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final detailsRaw = ref.watch(providerId);
    final playedIds = ref.watch(sushiCatalogItemFlagsProvider.select((s) => s.playedIds));
    final details = detailsRaw == null
        ? null
        : sushiPaintSeriesWatchState(detailsRaw, playedIds: playedIds);
    final wrapAlignment =
        AdaptiveLayout.viewSizeOf(context) != ViewSize.phone ? WrapAlignment.start : WrapAlignment.center;

    final currentEpisode = sushiSeriesDetailPlayTarget(details);
    final sushiHasPlayback = details != null && sushiItemHasPlaybackActions(details);
    // Only after /item has resolved (sushiTitleResolved) — the cached-page paint can populate
    // availableEpisodes before files land, so key off the network-refresh completion instead.
    // Until then, no Play and no Request (ADR 0014 §D2).
    final sushiResolved = sushiTitleResolved(ref, details?.id, sushiEnabled: true);
    final sushiSeriesRequestTmdb = details != null && sushiResolved && !sushiHasPlayback
        ? sushiTmdbIdFromItemId(details.id)
        : null;

    return DetailScaffold(
      label: details?.name ?? "",
      item: details,
      actions: (context) => details?.generateActions(
        context,
        ref,
        exclude: {
          ItemActions.play,
          ItemActions.playFromStart,
          ItemActions.details,
        },
        onDeleteSuccesFully: (item) {
          if (context.mounted) {
            context.router.popBack();
          }
        },
      ),
      onRefresh: () => ref.read(providerId.notifier).fetchDetails(widget.item),
      backDrops: details?.images,
      content: (detailsContext, padding) => details != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OverviewHeader(
                    name: details.name,
                    image: details.images,
                    mainButton: currentEpisode != null && sushiHasPlayback
                        ? SushiSeriesDetailPlayButtons(
                            series: details,
                            episode: currentEpisode,
                            onPlay: (restart) async {
                              await currentEpisode.play(
                                detailsContext,
                                ref,
                                startPosition: restart ? Duration.zero : null,
                              );
                              if (!mounted) return;
                              ref.read(providerId.notifier).fetchDetails(widget.item);
                            },
                            onLongPlay: (restart) async {
                              await currentEpisode.play(
                                detailsContext,
                                ref,
                                showPlaybackOption: true,
                                startPosition: restart ? Duration.zero : null,
                              );
                              if (!mounted) return;
                              ref.read(providerId.notifier).fetchDetails(widget.item);
                            },
                            onEpisodePlayed: () {
                              if (!mounted) return;
                              ref.read(providerId.notifier).fetchDetails(widget.item);
                            },
                          )
                        : sushiSeriesRequestTmdb != null
                            ? SushiRequestButton(
                                tmdbId: sushiSeriesRequestTmdb,
                                kind: 2,
                                prominent: true,
                                onAlreadyAvailable: () =>
                                    ref.read(providerId.notifier).fetchDetails(widget.item),
                              )
                            : null,
                    centerButtons: SushiDetailActionLayout(
                      alignment: wrapAlignment,
                      children: [
                        Consumer(
                          builder: (context, ref, _) {
                            final flags = ref.watch(sushiItemFlagsProvider)[details.id] ??
                                const SushiItemFlags();
                            return SelectableIconButton(
                              onPressed: () async {
                                await ref
                                    .read(sushiItemFlagsProvider.notifier)
                                    .setWatchLater(details, !flags.watchLater);
                              },
                              selected: flags.watchLater,
                              selectedIcon: IconsaxPlusBold.clock,
                              icon: IconsaxPlusLinear.clock,
                            );
                          },
                        ),
                        // Follow the series for new-episode notifications (ADR 0014 §D3).
                        Consumer(
                          builder: (context, ref, _) {
                            final flags = ref.watch(sushiItemFlagsProvider)[details.id] ??
                                const SushiItemFlags();
                            return SelectableIconButton(
                              onPressed: () async {
                                await ref
                                    .read(sushiItemFlagsProvider.notifier)
                                    .setFollowing(details, !flags.following);
                              },
                              selected: flags.following,
                              selectedIcon: IconsaxPlusBold.notification,
                              icon: IconsaxPlusLinear.notification,
                              label: flags.following
                                  ? context.localized.sushiFollowing
                                  : context.localized.sushiFollow,
                            );
                          },
                        ),
                        SelectableIconButton(
                          onPressed: () async {
                            final target = currentEpisode;
                            final markId = target?.id ?? details.id;
                            final played = target?.userData.played ?? details.userData.played;
                            await ref.read(userProvider.notifier).markAsPlayed(!played, markId);
                          },
                          selected: currentEpisode?.userData.played ?? details.userData.played,
                          selectedIcon: IconsaxPlusBold.tick_circle,
                          icon: IconsaxPlusLinear.tick_circle,
                        ),
                        SelectableIconButton(
                          onPressed: () {
                            showBottomSheetPill(
                              context: detailsContext,
                              item: details,
                              content: (context, scrollController) => ListView(
                                controller: scrollController,
                                shrinkWrap: true,
                                children: details.generateActions(detailsContext, ref, exclude: {
                                  ItemActions.openParent,
                                  ItemActions.details,
                                  if (!sushiHasPlayback) ...{
                                    ItemActions.play,
                                    ItemActions.playFromStart,
                                    ItemActions.download,
                                  },
                                }).listTileItems(context, useIcons: true),
                              ),
                            );
                          },
                          selected: false,
                          refreshOnEnd: false,
                          icon: IconsaxPlusLinear.more,
                        ),
                      ],
                    ),
                    padding: padding,
                    originalTitle: details.originalTitle,
                    productionYear: details.overview.yearAired.toString(),
                    runTime: details.overview.runTime,
                    studios: details.overview.studios,
                    officialRating: details.overview.parentalRating,
                    genres: details.overview.genreItems,
                    communityRating: details.overview.communityRating,
                    contentTags: details.overview.tags,
                    additionalLabels: sushiLibraryDetailLabels(
                      context,
                      ref,
                      widget.item.id,
                      details.overview,
                    ),
                    mediaStreamHelper: currentEpisode != null &&
                            sushiShowMediaStreamHelper(currentEpisode.mediaStreams)
                        ? MediaStreamHelper(
                            mediaStream: currentEpisode.mediaStreams,
                            onItemChanged: (changed) {
                              sushiOnUserMediaStreamsChanged(
                                ref,
                                changed,
                                itemId: currentEpisode.id,
                              );
                              final updateEpisode = currentEpisode.copyWith(
                                mediaStreams: changed,
                              );
                              ref.read(providerId.notifier).updateEpisodeInfo(updateEpisode);
                            },
                          )
                        : null,
                  ),
                  if (details.overview.summary.isNotEmpty)
                    Padding(
                      padding: padding,
                      child: Builder(builder: (context) {
                        return ExpandingText(
                          text: details.overview.summary,
                          onFocusChange: (onFocus) {
                            if (onFocus) {
                              context.ensureVisible(alignment: 1);
                            }
                          },
                        );
                      }),
                    ),
                  if (details.availableEpisodes?.isNotEmpty ?? false)
                    Builder(builder: (context) {
                      return EpisodePosters(
                        contentPadding: padding,
                        selectedEpisode: currentEpisode,
                        seasons: details.seasons ?? [],
                        titleActionsPosition:
                            AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad ? null : VerticalDirection.down,
                        label: context.localized.episode(details.availableEpisodes?.length ?? 2),
                        onFocused: (episode) {
                          context.ensureVisible(alignment: 0.8);
                        },
                        onEpisodeTap: (action, episode) async {
                          action();
                        },
                        playEpisode: (episode) async {
                          await episode.play(
                            context,
                            ref,
                          );
                          if (!mounted) return;
                          ref.read(providerId.notifier).fetchDetails(widget.item);
                        },
                        episodes: details.availableEpisodes ?? [],
                      );
                    }),
                  if (details.seasons?.isNotEmpty ?? false)
                    SeasonsRow(
                      contentPadding: padding,
                      seasons: details.seasons,
                    ),
                  if (details.overview.people.isNotEmpty)
                    PeopleRow(
                      people: details.overview.people,
                      contentPadding: padding,
                    ),
                  if (details.specialFeatures?.isNotEmpty ?? false)
                    SpecialFeaturesRow(
                        contentPadding: padding,
                        label: detailsContext.localized.specialFeature(details.specialFeatures?.length ?? 2),
                        specialFeatures: details.specialFeatures ?? []),
                  if (details.related.isNotEmpty)
                    PosterRow(
                      posters: details.related,
                      contentPadding: padding,
                      label: detailsContext.localized.related,
                      sushiDetailBadges: true,
                    ),
                  if (sushiCollectionFor(details.id)?.items.isNotEmpty ?? false)
                    PosterRow(
                      posters: sushiCollectionFor(details.id)!.items,
                      contentPadding: padding,
                      label: () {
                        final name = sushiCollectionFor(details.id)!.name;
                        return name.isEmpty ? 'Collection' : name;
                      }(),
                      sushiDetailBadges: false,
                    ),
                  if (details.overview.externalUrls?.isNotEmpty == true)
                    Padding(
                      padding: padding,
                      child: ExternalUrlsRow(
                        urls: details.overview.externalUrls,
                      ),
                    )
                ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
              ),
            )
          : SushiDetailLoadingContent(item: widget.item, padding: padding),
    );
  }
}
