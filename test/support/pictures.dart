import 'package:flutter/painting.dart';
import 'package:hotlayout_flutter/src/render/picture_image.dart';

/// The address behind the provider a picture is drawn with: the package wraps every network picture in a
/// `ResizeImage` over its own `NetworkPicture`.
String pictureUrlOf(ImageProvider provider) {
  final inner = provider is ResizeImage ? provider.imageProvider : provider;
  return (inner as NetworkPicture).url;
}
