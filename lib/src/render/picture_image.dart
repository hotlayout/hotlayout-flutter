/// Raster pictures with a bounded body and a bounded decode.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'picture_fetch.dart';
import 'picture_policy.dart';

/// A raster picture from a network address: the framework's `NetworkImage` replaced by a loader that reads the
/// body up to a cap, follows no redirect the host's policy has not seen, and carries nothing of the host.
@immutable
class NetworkPicture extends ImageProvider<NetworkPicture> {
  const NetworkPicture(this.url, {required this.policy});

  /// The address the policy approved.
  final String url;
  final PicturePolicy policy;

  @override
  Future<NetworkPicture> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NetworkPicture>(this);

  @override
  ImageStreamCompleter loadImage(
    NetworkPicture key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1.0,
    debugLabel: 'NetworkPicture',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await fetchPictureBytes(
      Uri.parse(url),
      approve: policy.approve,
      maxBytes: policy.maxDownloadBytes,
    );
    if (bytes.isEmpty) throw const PictureFetchException('empty body');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkPicture &&
      other.url == url &&
      other.policy.maxDownloadBytes == policy.maxDownloadBytes;

  @override
  int get hashCode => Object.hash(url, policy.maxDownloadBytes);

  @override
  String toString() => 'NetworkPicture';
}

/// A picture decoded at the size of its box, never at the size the file declares: a small file that says
/// 30000 × 30000 must not become gigabytes of pixels.
///
/// The target is the laid-out box times the device pixel ratio, with a hard ceiling of [kMaxDecodedSide]
/// pixels on a side; without a bounded box the ceiling alone applies. A picture is never enlarged. For
/// `cover` the target is twice the box, because the cropped axis needs more than the box on it.
class BoundedImage extends StatelessWidget {
  const BoundedImage({
    super.key,
    required this.provider,
    required this.fit,
    required this.errorBuilder,
    this.frameBuilder,
  });

  final ImageProvider provider;
  final BoxFit fit;
  final ImageErrorWidgetBuilder errorBuilder;
  final ImageFrameBuilder? frameBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final spread = fit == BoxFit.cover ? 2.0 : 1.0;
      return Image(
        image: ResizeImage(
          provider,
          width: decodeSide(constraints.maxWidth, ratio, spread),
          height: decodeSide(constraints.maxHeight, ratio, spread),
          policy: ResizeImagePolicy.fit,
        ),
        fit: fit,
        errorBuilder: errorBuilder,
        frameBuilder: frameBuilder,
      );
    },
  );
}

/// The pixels to decode one side at: [logical] × [ratio] × [spread] within 1…[kMaxDecodedSide]; an unbounded or
/// not finite side takes the ceiling.
@visibleForTesting
int decodeSide(double logical, double ratio, double spread) {
  final pixels = logical * ratio * spread;
  if (!pixels.isFinite) return kMaxDecodedSide;
  return pixels.ceil().clamp(1, kMaxDecodedSide);
}
