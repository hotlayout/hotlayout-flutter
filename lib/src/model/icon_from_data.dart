import 'tokens.dart';

/// THE ICON FROM DATA (schema 9.19.0, `x-iconFromData`): a node that has an icon of the document may name a data path
/// that holds the NAME of an icon of the set. The name of the document stays beside it and is drawn when the data has
/// no value.
///
/// The value is a key into the reader's own copy of the icon set, and nothing else: an address or a drawing in the
/// data is just a name that is not in the set, an empty box of the same size.

/// The `iconPath` of a node: a non-empty string; anything else is "no field".
String? iconPathOf(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

/// The icon to draw (`resolveIconName`): the document's icon when it has none (then the path is not read), when there
/// is no path, or when the data has no value under it (absent, `null`, the empty string). Otherwise the value, as is:
/// a name of the set is that icon, a name that is not in the set (not trimmed, case matters) or a value that is not a
/// string is [IconToken.unknown], an empty box of the same size. [read] reads a path in the data scope of the node.
IconToken? resolveIconToken(IconToken? documentIcon, String? path, Object? Function(String path) read) {
  if (documentIcon == null || path == null) return documentIcon;
  final value = read(path);
  if (value == null || value == '') return documentIcon;
  return IconToken.parse(value);
}
