import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/providers/items/person_details_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:fladder/util/widget_extensions.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

class PersonDetailScreen extends ConsumerStatefulWidget {
  final Person person;
  const PersonDetailScreen({required this.person, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  late final providerID = personDetailsProvider(widget.person.id);
  var _sushiFetchDone = false;

  @override
  void initState() {
    super.initState();
    if (SushiConfig.isEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(providerID.notifier).fetchPerson(widget.person);
        if (mounted) setState(() => _sushiFetchDone = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = SushiConfig.isEnabled
        ? (ref.watch(providerID) ?? sushiPersonModel(widget.person))
        : ref.watch(providerID);
    final face = details?.images?.primary ?? widget.person.image;
    return DetailScaffold(
      label: (details?.name.isNotEmpty ?? false) ? details!.name : widget.person.name,
      item: details,
      onRefresh: () async {
        await ref.read(providerID.notifier).fetchPerson(widget.person);
        if (mounted && SushiConfig.isEnabled) setState(() => _sushiFetchDone = true);
      },
      backDrops: SushiConfig.isEnabled && face != null
          ? ImagesData(primary: face, backDrop: [face])
          : [...?details?.movies, ...?details?.series].random().firstOrNull?.images,
      content: (context, padding) => Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: MediaQuery.of(context).size.height / 6),
          Padding(
            padding: padding,
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.spaceEvenly,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 32,
              spacing: 32,
              children: [
                Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  width: AdaptiveLayout.viewSizeOf(context) == ViewSize.phone
                      ? MediaQuery.of(context).size.width
                      : MediaQuery.of(context).size.width / 3.5,
                  child: AspectRatio(
                    aspectRatio: 0.70,
                    child: FladderImage(
                      fit: BoxFit.cover,
                      placeHolder: placeHolder(
                          (details?.name.isNotEmpty ?? false) ? details!.name : widget.person.name),
                      image: details?.images?.primary ?? widget.person.image,
                    ),
                  ),
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                              child: Text(
                            (details?.name.isNotEmpty ?? false) ? details!.name : widget.person.name,
                            style: Theme.of(context).textTheme.displaySmall,
                          )),
                          if (!SushiConfig.isEnabled) ...[
                            const SizedBox(width: 15),
                            SelectableIconButton(
                              onPressed: () => ref.read(providerID.notifier).toggleFavorite(),
                              selected: (details?.userData.isFavourite ?? false),
                              selectedIcon: Icons.favorite_rounded,
                              icon: Icons.favorite_border_rounded,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (SushiConfig.isEnabled && (details?.overview.summary.isNotEmpty ?? false))
                      Text(details!.overview.summary),
                    if (details?.dateOfBirth != null)
                      Text(context.localized.personBirthday(
                          DateFormat.yMEd(context.localized.localeName).format(details!.dateOfBirth!).toString())),
                    if (details?.age != null) Text(context.localized.personAge(details!.age!)),
                    if (details?.birthPlace.isEmpty == false)
                      Text(context.localized.personBirthPlace(details!.birthPlace.join(", "))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (SushiConfig.isEnabled &&
              _sushiFetchDone &&
              (details?.movies.isEmpty ?? true) &&
              (details?.series.isEmpty ?? true))
            Padding(
              padding: padding,
              child: Text(context.localized.noOverviewAvailable),
            ),
          if (details?.movies.isNotEmpty ?? false)
            PosterRow(
              contentPadding: padding,
              posters: details?.movies ?? [],
              label: context.localized.mediaTypeMovie(details?.movies.length ?? 2),
            ),
          if (details?.series.isNotEmpty ?? false)
            PosterRow(
              contentPadding: padding,
              posters: details?.series ?? [],
              label: context.localized.mediaTypeSeries(details?.series.length ?? 2),
            ),
          if (details?.seerrMovies.isNotEmpty ?? false)
            SeerrPosterRow(
              contentPadding: padding,
              posters: details?.seerrMovies ?? [],
              label: context.localized.seerrMovies,
            ),
          if (details?.seerrSeries.isNotEmpty ?? false)
            SeerrPosterRow(
              contentPadding: padding,
              posters: details?.seerrSeries ?? [],
              label: context.localized.seerrSeries,
            ),
          if (details?.overview.externalUrls?.isNotEmpty ?? false)
            ExternalUrlsRow(
              urls: details?.overview.externalUrls,
            ).padding(padding),
        ],
      ),
    );
  }

  Widget placeHolder(String name) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: FractionallySizedBox(
        widthFactor: 0.4,
        child: Card(
          shape: const CircleBorder(),
          child: Center(
              child: Text(
            name.getInitials(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          )),
        ),
      ),
    );
  }
}
