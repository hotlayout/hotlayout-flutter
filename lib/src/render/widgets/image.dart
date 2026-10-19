/// Images and icons: the box, loading and broken states, alternative text.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../model/bindable.dart';
import '../../model/icon_from_data.dart';
import '../../model/node.dart';
import '../../model/tokens.dart';
import '../icon_box.dart';
import '../icon_glyph.dart';
import '../image_frame.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import '../picture_image.dart';
import '../picture_policy.dart' show pictureReportAddress;
import '../svg_image.dart';

extension ImageWidgets on NodeRenderer {
  Widget buildImage(ImageNode node) => _withAlt(
    node.alt,
    image: true,
    // The rounding comes from `style.radius` and is clipped by the shared box: an image without
    // a style has square corners. The box is the node's box (schema 9.9.0): a named height beats
    // the aspect ratio, and height limits also clamp a height derived from the ratio; see
    // [ImageFrame].
    ImageFrame(
      ratio: node.aspectRatio.ratio,
      child: imageContent(node.source, fit: node.fit),
    ),
  );

  /// The content of an image without a frame or aspect ratio.
  ///
  /// Separate from [buildImage] because the same `ImageSource` also appears in `ListTile.leading`:
  /// a record's photo works in a row not because the row learned networking, but because the
  /// contract has one source type.
  ///
  /// [compact] is an icon-sized thumbnail: neither the error caption nor a normal-size indicator
  /// fits there.
  ///
  /// Data substitution (schema 8.1.0) is done HERE, with a single `resolve` call, so a bound
  /// address works in `Image` and `ListTile.leading` alike: there is one place where a source
  /// becomes pixels.
  ///
  /// [fit] is the fitting mode (schema 8.11.0). The default `cover` is deliberate: the contract
  /// gives `ListTile.leading` no fitting mode at all, since the frame there is square and always
  /// filled.
  Widget imageContent(
    ImageSource source, {
    bool compact = false,
    ImageFitToken fit = ImageFitToken.cover,
  }) => switch (source.resolve(data)) {
    ImageAsset(:final asset) => _assetPlaceholder(asset, compact: compact),
    ImageUrl(:final url) => _pictureFrom(url, fit: fit, compact: compact, fromData: source is! UrlImageSource),
  };

  /// A network or `data:` picture, after the host's address policy. A refused address draws the broken-image
  /// placeholder and makes no request.
  Widget _pictureFrom(String url, {required ImageFitToken fit, required bool compact, required bool fromData}) {
    final isData = _isDataImage(url);
    final approved = pictures.approve(url, isData: isData);
    if (approved == null) {
      if (kDebugMode) debugPrint('[hotlayout] picture refused: ${pictureReportAddress(url, fromData: fromData)}');
      return _brokenImage(url, compact: compact);
    }
    // SVG is the same image with the same states, only drawn by a different decoder: the
    // framework's raster codec does not read vectors at all.
    if (!isData && isSvgUrl(approved)) {
      return NetworkSvg(
        url: approved,
        fit: _boxFit(fit),
        policy: pictures,
        loading: _imageLoading(compact: compact),
        error: _brokenImage(url, compact: compact),
      );
    }
    // A `data:` address (data dictionary samples carry them) is not read by `HttpClient`. `UriData`
    // parses the body and hands the bytes to the same codec that draws a network image, with the
    // same "broken" states and no network request. If it cannot be parsed, it is a broken image.
    if (isData) return _dataImage(approved, fit: fit, compact: compact);
    return BoundedImage(
      provider: NetworkPicture(approved, policy: pictures),
      fit: _boxFit(fit),
      // A broken URL must be visible: an empty space would look like "all fine" to the author.
      errorBuilder: (_, _, _) => _brokenImage(url, compact: compact),
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous ? _imageLoading(compact: compact) : child,
    );
  }

  static bool _isDataImage(String url) => url.length > 11 && url.substring(0, 11).toLowerCase() == 'data:image/';

  Widget _dataImage(String url, {required ImageFitToken fit, required bool compact}) {
    // The text is checked BEFORE it is decoded: base64 is 4/3 of the bytes it carries, and a body above the cap
    // is not worth decoding to find that out.
    if (url.length > pictures.maxDownloadBytes * 4 ~/ 3 + 1024) return _brokenImage(url, compact: compact);
    final Uint8List bytes;
    try {
      bytes = UriData.parse(url).contentAsBytes();
    } on FormatException {
      return _brokenImage(url, compact: compact);
    } on ArgumentError {
      return _brokenImage(url, compact: compact);
    }
    if (bytes.length > pictures.maxDownloadBytes) return _brokenImage(url, compact: compact);
    return BoundedImage(
      provider: MemoryImage(bytes),
      fit: _boxFit(fit),
      errorBuilder: (_, _, _) => _brokenImage(url, compact: compact),
    );
  }

  /// One place for both decoders: a `fit` that raster handles and SVG does not (or vice versa)
  /// cannot appear here.
  BoxFit _boxFit(ImageFitToken fit) => switch (fit) {
    ImageFitToken.cover => BoxFit.cover,
    ImageFitToken.contain => BoxFit.contain,
  };

  /// The image is still loading. Shared by raster and SVG for the same reason as [_brokenImage]:
  /// two "loading" states would drift apart on the first edit.
  Widget _imageLoading({bool compact = false}) => ColoredBox(
    color: theme.color(ColorToken.secondary),
    child: Center(
      child: compact
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const CircularProgressIndicator(),
    ),
  );

  /// The contract provides an asset token, not a file, so the reader draws a placeholder: a
  /// gradient or flat fill with an icon, the same as the other readers.
  Widget _assetPlaceholder(AssetToken asset, {bool compact = false}) {
    final (Gradient? gradient, Color background, IconToken icon) = switch (asset) {
      AssetToken.logo => (
        LinearGradient(
          colors: [theme.color(ColorToken.primary), const Color(0xFF007A54)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        theme.color(ColorToken.primary),
        IconToken.parse('landmark'),
      ),
      AssetToken.banner => (
        LinearGradient(
          colors: [theme.color(ColorToken.accent), theme.color(ColorToken.primary)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        theme.color(ColorToken.accent),
        IconToken.parse('megaphone'),
      ),
      AssetToken.placeholder => (null, const Color(0xFFE5E7EB), IconToken.parse('image')),
    };
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient, color: gradient == null ? background : null),
      child: Center(
        child: IconGlyph(
          icon,
          size: compact ? 20 : 32,
          color: gradient == null
              ? theme.color(ColorToken.muted)
              : theme.color(ColorToken.onPrimary),
        ),
      ),
    );
  }

  Widget _brokenImage(String url, {bool compact = false}) => ColoredBox(
    color: theme.color(ColorToken.secondary),
    child: compact
        // The caption does not fit in a thumbnail, and a crossed-out image reads fine without it.
        ? Center(
            child: IconGlyph(
              IconToken.parse('image'),
              size: 20,
              color: theme.color(ColorToken.muted),
            ),
          )
        : Center(
      child: Padding(
        padding: theme.padding(SpacingToken.sm),
        child: QuietColumn(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconGlyph(IconToken.parse('image'), size: 24, color: theme.color(ColorToken.muted)),
            SizedBox(height: theme.space(SpacingToken.xs)),
            Text(
              labels.imageUnavailable,
              textAlign: TextAlign.center,
              style: theme
                  .text(TypographyToken.caption)
                  .copyWith(color: theme.color(ColorToken.muted)),
            ),
            if (kDebugMode)
              Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme
                    .text(TypographyToken.caption)
                    .copyWith(color: theme.color(ColorToken.muted)),
              ),
          ],
        ),
      ),
    ),
  );

  Widget buildIcon(IconNode node) {
    // The icon from data (9.19.0): the name under `iconPath` when the data has one; a name that is not in the set,
    // or a value that is not a string, is an empty box of the same size.
    final name = resolveIconToken(node.name, node.iconPath, data.lookup)!;
    return _withAlt(
    node.alt,
    // The glyph grows with the system font scale, like text (`iconGlyphMeasure:
    // 'typography-font-size'`); the box is a token's line height. The color is inherited: an icon
    // reads it the same way as text. With a numeric `glyphSize` (schema 9.16.0) the box is a
    // square of that number, and the font scale does not multiply it.
    node.glyphSize == null
        ? buildIconBox(node.size, name, currentForeground.color)
        : OwnGlyphBox(side: node.glyphSize!.toDouble(), icon: name, color: currentForeground.color),
    );
  }

  /// The icon box in a layout: font size × the token's line height, the glyph centered. Used for
  /// `Icon` and the icon parts of `ListTile` (`listTileIconSizes`); the chevron, the selection
  /// circle and the `AppBar` arrow have no such box.
  ///
  /// An icon the reader cannot draw ([IconToken.unknown]) gives the same box without a picture:
  /// the layout does not jump just because the reader is a minor version behind (`unknownIcon:
  /// 'empty-box-same-size'`).
  Widget buildIconBox(IconSizeToken size, IconToken icon, Color color) =>
      IconBox(box: theme.iconBox(size), icon: icon, color: color);

  /// The contract's `alt` becomes the accessible label: a string of the document, translated, with the data put in
  /// and its spaces collapsed like any shown text. Without it, or when what is shown is empty, the node stays purely
  /// decorative and does not enter the semantics tree.
  Widget _withAlt(BindableString? alt, Widget child, {bool image = false}) {
    final shown = alt == null ? '' : text(alt);
    return shown.isEmpty ? child : Semantics(label: shown, image: image, child: child);
  }
}
