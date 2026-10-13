// Sample data and the collection source for the DEMO, used by renderer tests on fixtures.
//
// Both files are host code, not package code, so they live in `demo/lib/`. The contract
// fixtures are bound to exactly these paths (`sample_data.dart` mirrors the data
// dictionary); without them a fixture test would exercise the document's fallbacks
// instead of its bindings. The relative import into another `lib/` is confined to this
// one place: the demo is a separate package and package tests can reach it only this way
// (same reason as in `public_api_test.dart` for `example/`).
// ignore_for_file: avoid_relative_lib_imports
export '../../demo/lib/collection_source.dart';
export '../../demo/lib/sample_data.dart';
