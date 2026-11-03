/// Browser features the app needs, behind an interface so screens can be
/// tested on the Dart VM with a fake.
library;

import 'dart:typed_data';

import 'browser_stub.dart'
    if (dart.library.js_interop) 'browser_web.dart'
    as impl;

/// A file the person picked.
abstract class PickedFile {
  String get name;
  int get size;
  String get type;

  /// The first [count] bytes, for type sniffing.
  Future<Uint8List> head([int count = 64]);

  /// The whole file. Dartus `putBlob` needs the bytes in memory.
  Future<Uint8List> readAll();
}

/// A square cover image ready to upload.
class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.mime,
    required this.adjusted,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String mime;

  /// True when the picture was cropped to a square or scaled down.
  final bool adjusted;
}

abstract class Browser {
  void setBeforeUnloadGuard(bool Function()? guard) {}
  Future<PickedFile?> pickFile({required String accept});

  /// Reads the duration from file metadata; null when the browser cannot.
  Future<Duration?> audioDuration(PickedFile file);

  /// Crops to a centred square and scales to at most [maxSide] pixels.
  /// Returns null when the image cannot be decoded.
  Future<PreparedImage?> prepareCover(PickedFile file, {int maxSide = 3000});

  bool get canShare;
  Future<bool> share({required String title, required String url});

  /// Offers [bytes] to the person as a file download.
  void saveFile(
    Uint8List bytes, {
    required String fileName,
    required String mime,
  });

  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

Browser createBrowser() => impl.createBrowser();
