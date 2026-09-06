import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/sushi/sushi_hero_image.dart';
import 'package:fladder/sushi/sushi_image_log.dart';

/// Home slider is landscape; prefer backdrop over the 600px primary poster.
ImageData? sushiSliderImage(ItemBaseModel item) {
  
  final image = sushiHeroImage(
    item.images?.backDrop?.firstOrNull ??
        item.getPosters?.backDrop?.firstOrNull ??
        item.bannerImage,
  );
  SushiImageLog.event('slider', fields: {
    'item': item.id,
    'path': image?.path ?? '(none)',
  });
  return image;
}
