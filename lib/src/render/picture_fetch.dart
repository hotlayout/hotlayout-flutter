/// The picture loader: `dart:io` where it exists, the browser's request on the web.
library;

export 'picture_fetch_web.dart' if (dart.library.io) 'picture_fetch_io.dart';
