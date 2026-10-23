import 'dart:convert';
import 'dart:typed_data';

/// The UTF-8 bytes of [text], as a transport hands them to the placement reader.
Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

/// No body.
final Uint8List noBytes = Uint8List(0);
