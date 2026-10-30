import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The README is the first screen of the package on pub.dev. It was once the
/// whole reference (nearly two thousand lines), and nobody could find anything
/// in it. The reference lives on the documentation site; the README stays an
/// introduction.
const int _maxReadmeLines = 350;

void main() {
  test('the README stays an introduction', () {
    final lines = File('README.md').readAsLinesSync().length;
    expect(
      lines,
      lessThanOrEqualTo(_maxReadmeLines),
      reason: 'README.md has $lines lines (limit $_maxReadmeLines): '
          'the reference lives at hotlayout.com/docs; the README is an introduction. '
          'Put the new section on a documentation page and link to it.',
    );
  });
}
