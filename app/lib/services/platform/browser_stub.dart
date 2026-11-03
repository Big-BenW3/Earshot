import 'dart:typed_data';

import 'browser.dart';

Browser createBrowser() => MemoryBrowser();

/// In-memory browser used on the Dart VM (tests).
class MemoryBrowser extends Browser {
  final Map<String, String> storage = {};
  final List<(String, int)> saved = [];
  final List<String> shared = [];
  PickedFile? nextPick;
  Duration? nextDuration;
  PreparedImage? nextCover;

  @override
  Future<PickedFile?> pickFile({required String accept}) async => nextPick;

  @override
  Future<Duration?> audioDuration(PickedFile file) async => nextDuration;

  @override
  Future<PreparedImage?> prepareCover(
    PickedFile file, {
    int maxSide = 3000,
  }) async => nextCover;

  @override
  bool get canShare => false;

  @override
  Future<bool> share({required String title, required String url}) async {
    shared.add(url);
    return true;
  }

  @override
  void saveFile(
    Uint8List bytes, {
    required String fileName,
    required String mime,
  }) => saved.add((fileName, bytes.length));

  @override
  String? read(String key) => storage[key];

  @override
  void write(String key, String value) => storage[key] = value;

  @override
  void remove(String key) => storage.remove(key);
}

/// A picked file backed by bytes in memory.
class MemoryFile implements PickedFile {
  MemoryFile(this.name, this.bytes, {this.type = ''});

  @override
  final String name;
  final Uint8List bytes;
  @override
  final String type;

  @override
  int get size => bytes.length;

  @override
  Future<Uint8List> head([int count = 64]) async =>
      bytes.sublist(0, count > bytes.length ? bytes.length : count);

  @override
  Future<Uint8List> readAll() async => bytes;
}
