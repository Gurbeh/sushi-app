import 'package:auto_route/auto_route.dart';
import 'package:fladder/providers/search_provider.dart';
import 'package:fladder/screens/shared/media/poster_grid.dart';
import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/debouncer.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@RoutePage()
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  final Debouncer searchDebouncer = Debouncer(const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(searchProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchProvider);
    final query = searchResults.searchQuery.trim();
    final showFirstLoad = searchResults.loading && !searchResults.hasAnyResults;
    final showEmpty = !searchResults.loading &&
        !searchResults.failed &&
        query.isNotEmpty &&
        !searchResults.hasAnyResults;
    final padding = AdaptiveLayout.adaptivePadding(context);

    return Scaffold(
      appBar: AppBar(
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: AnimatedOpacity(
            opacity: searchResults.loading ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: const LinearProgressIndicator(minHeight: 2),
          ),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.localized.search,
            border: InputBorder.none,
          ),
          onSubmitted: (value) {
            ref.read(searchProvider.notifier).searchQuery();
          },
          onChanged: (query) {
            ref.read(searchProvider.notifier).setQuery(query);
            searchDebouncer.run(() {
              ref.read(searchProvider.notifier).searchQuery();
            });
          },
        ),
      ),
      body: showFirstLoad
          ? const Center(child: CircularProgressIndicator())
          : searchResults.failed
              ? Center(child: Text(context.localized.somethingWentWrong))
              : showEmpty
                  ? Center(child: Text(context.localized.noResults))
                  : ListView(
                      padding: EdgeInsets.only(
                        left: padding.left,
                        right: padding.right,
                        bottom: 24,
                      ),
                      children: [
                        ...searchResults.results.entries.map(
                          (e) => PosterGrid(
                            stickyHeader: false,
                            name: e.key.name.capitalize(),
                            posters: e.value,
                          ),
                        ),
                        if (searchResults.missing.isNotEmpty)
                          PosterGrid(
                            stickyHeader: false,
                            name: context.localized.moreFromTmdb,
                            posters: searchResults.missing,
                            itemBuilder: (context, index) {
                              final poster = searchResults.missing[index];
                              return PosterWidget(
                                poster: poster,
                                subTitle: Text(
                                  context.localized.unavailable,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
    );
  }
}
