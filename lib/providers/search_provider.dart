import 'package:chopper/chopper.dart';
import 'package:fladder/models/search_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_search_transport.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchProvider = StateNotifierProvider<SearchNotifier, SearchModel>((ref) {
  return SearchNotifier(ref);
});

class SearchNotifier extends StateNotifier<SearchModel> {
  SearchNotifier(this.ref) : super(SearchModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<Response?> searchQuery() async {
    if (state.searchQuery.isEmpty) return null;
    state = state.copyWith(loading: true, failed: false);
    if (SushiConfig.isEnabled) {
      final q = state.searchQuery;
      final res = await sushiFetchSearch(query: q);
      if (state.searchQuery != q) return null;
      if (res == null) {
        state = state.copyWith(
          resultCount: 0,
          results: const {},
          missing: const [],
          loading: false,
          failed: true,
        );
        return null;
      }
      final items = res.rows.map(sushiRowToItemBaseModel).toList();
      final missing = res.missing.map(sushiRowToItemBaseModel).toList();
      state = state.copyWith(
        resultCount: items.length + missing.length,
        results: items.groupedItems,
        missing: missing,
        loading: false,
        failed: false,
      );
      return null;
    }
    final response = await api.itemsGet(
      recursive: true,
      searchTerm: state.searchQuery,
    );

    state = state.copyWith(
      resultCount: response.body?.totalRecordCount ?? 0,
      results: (response.body?.items)?.groupedItems,
      missing: const [],
      failed: false,
    );
    state = state.copyWith(loading: false);
    return response;
  }

  void setQuery(String searchQuery) {
    state = state.copyWith(searchQuery: searchQuery);
  }

  void clear() {
    state = SearchModel();
  }
}
