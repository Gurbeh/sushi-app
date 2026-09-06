import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/view_model.dart';

/// OX-facing library folder labels (server [jellyfin.VirtualTVViewName] is source of truth).
abstract final class SushiViewLabels {
  static const tvLibraryName = 'Series';

  static ViewModel apply(ViewModel view) {
    
    if (view.collectionType != CollectionType.tvshows) return view;
    if (view.name == tvLibraryName) return view;
    return view.copyWith(name: tvLibraryName);
  }

  static List<ViewModel> applyAll(List<ViewModel> views) => views.map(apply).toList();
}
