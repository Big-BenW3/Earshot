import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser.dart';

Browser createBrowser() => WebBrowser();

class _WebFile implements PickedFile {
  _WebFile(this.file);
  final web.File file;

  @override
  String get name => file.name;
  @override
  int get size => file.size;
  @override
  String get type => file.type;

  @override
  Future<Uint8List> head([int count = 64]) async {
    final end = count > file.size ? file.size : count;
    final buffer = await file.slice(0, end).arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Future<Uint8List> readAll() async {
    final buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}

class WebBrowser extends Browser {
  JSFunction? _unloadListener;
  @override
  void setBeforeUnloadGuard(bool Function()? guard) {
    final previous = _unloadListener;
    if (previous != null) {
      web.window.removeEventListener('beforeunload', previous);
    }
    _unloadListener = guard == null
        ? null
        : ((web.Event event) {
            if (guard()) {
              event.preventDefault();
              (event as web.BeforeUnloadEvent).returnValue = '';
            }
          }).toJS;
    final listener = _unloadListener;
    if (listener != null) web.window.addEventListener('beforeunload', listener);
  }

  @override
  Future<PickedFile?> pickFile({required String accept}) {
    final completer = Completer<PickedFile?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = accept
      ..style.display = 'none';
    web.document.body?.append(input);
    void finish(PickedFile? file) {
      if (!completer.isCompleted) completer.complete(file);
      input.remove();
    }

    input.onchange = ((web.Event _) {
      final files = input.files;
      finish(
        files == null || files.length == 0 ? null : _WebFile(files.item(0)!),
      );
    }).toJS;
    input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
    input.click();
    return completer.future;
  }

  @override
  Future<Duration?> audioDuration(PickedFile file) async {
    if (file is! _WebFile) return null;
    final url = web.URL.createObjectURL(file.file);
    final audio = web.HTMLAudioElement()
      ..preload = 'metadata'
      ..muted = true;
    final completer = Completer<Duration?>();
    void done(Duration? d) {
      if (!completer.isCompleted) completer.complete(d);
    }

    audio.onloadedmetadata = ((web.Event _) {
      final seconds = audio.duration;
      done(
        seconds.isFinite && seconds > 0
            ? Duration(milliseconds: (seconds * 1000).round())
            : null,
      );
    }).toJS;
    audio.onerror = ((web.Event _) => done(null)).toJS;
    audio.src = url;
    final result = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => null,
    );
    audio.src = '';
    web.URL.revokeObjectURL(url);
    return result;
  }

  @override
  Future<PreparedImage?> prepareCover(
    PickedFile file, {
    int maxSide = 3000,
  }) async {
    if (file is! _WebFile) return null;
    final url = web.URL.createObjectURL(file.file);
    try {
      final img = web.HTMLImageElement()..src = url;
      try {
        await img.decode().toDart;
      } catch (_) {
        return null;
      }
      final w = img.naturalWidth;
      final h = img.naturalHeight;
      if (w == 0 || h == 0) return null;
      final side = w < h ? w : h;
      final target = side > maxSide ? maxSide : side;
      final square = w == h;
      if (square && target == side) {
        final bytes = await file.readAll();
        return PreparedImage(
          bytes: bytes,
          width: w,
          height: h,
          mime: file.type.isEmpty ? 'image/jpeg' : file.type,
          adjusted: false,
        );
      }
      final canvas = web.HTMLCanvasElement()
        ..width = target
        ..height = target;
      final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(
        img,
        ((w - side) / 2).floorToDouble(),
        ((h - side) / 2).floorToDouble(),
        side.toDouble(),
        side.toDouble(),
        0,
        0,
        target.toDouble(),
        target.toDouble(),
      );
      final blobCompleter = Completer<web.Blob?>();
      canvas.toBlob(
        ((web.Blob? b) => blobCompleter.complete(b)).toJS,
        'image/jpeg',
        0.9.toJS,
      );
      final blob = await blobCompleter.future;
      if (blob == null) return null;
      final buffer = await blob.arrayBuffer().toDart;
      return PreparedImage(
        bytes: buffer.toDart.asUint8List(),
        width: target,
        height: target,
        mime: 'image/jpeg',
        adjusted: true,
      );
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  @override
  bool get canShare => (web.window.navigator as JSObject).has('share');

  @override
  Future<bool> share({required String title, required String url}) async {
    try {
      await web.window.navigator
          .share(web.ShareData(title: title, url: url))
          .toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void saveFile(
    Uint8List bytes, {
    required String fileName,
    required String mime,
  }) {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }

  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // Private mode or storage full: resume positions are a nicety.
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }
}
