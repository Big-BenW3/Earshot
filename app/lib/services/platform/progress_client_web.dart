import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'progress_client.dart' show ProgressCallback;

http.Client createProgressClient({
  ProgressCallback? onUpload,
  ProgressCallback? onDownload,
  bool withCredentials = false,
}) => XhrProgressClient(
  onUpload: onUpload,
  onDownload: onDownload,
  withCredentials: withCredentials,
);

/// XMLHttpRequest-based client with progress events. Same-origin requests
/// (the publisher proxy) and CORS requests (the aggregator) both work.
class XhrProgressClient extends http.BaseClient {
  XhrProgressClient({
    this.onUpload,
    this.onDownload,
    this.withCredentials = false,
    this.maxResponseBytes = 100 * 1024 * 1024,
  });

  final ProgressCallback? onUpload;
  final ProgressCallback? onDownload;
  final bool withCredentials;
  final _open = <web.XMLHttpRequest>{};
  bool _closed = false;
  final int maxResponseBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Dartus sends `http.Request` with the bytes already in memory; reuse
    // them instead of copying the file again.
    final Uint8List body = request is http.Request
        ? request.bodyBytes
        : await request.finalize().toBytes();

    if (_closed) throw http.ClientException('Client closed', request.url);
    final xhr = web.XMLHttpRequest();
    _open.add(xhr);
    final completer = Completer<http.StreamedResponse>();
    xhr.open(request.method, request.url.toString(), true);
    xhr.responseType = 'arraybuffer';
    if (withCredentials) xhr.withCredentials = true;
    request.headers.forEach((k, v) {
      // Browsers set these themselves and refuse them from scripts.
      if (k.toLowerCase() == 'content-length') return;
      xhr.setRequestHeader(k, v);
    });

    void progress(ProgressCallback? cb, web.Event e) {
      if (cb == null) return;
      final p = e as web.ProgressEvent;
      cb(p.loaded, p.lengthComputable ? p.total : body.length);
    }

    void fail(String why) {
      _open.remove(xhr);
      if (!completer.isCompleted) {
        completer.completeError(http.ClientException(why, request.url));
      }
    }

    if (onUpload != null) {
      xhr.upload.onprogress = ((web.Event e) => progress(onUpload, e)).toJS;
    }
    xhr.onprogress = ((web.Event e) {
      if ((e as web.ProgressEvent).loaded > maxResponseBytes) {
        fail('The response exceeds the download limit.');
        xhr.abort();
        return;
      }
      progress(onDownload, e);
    }).toJS;
    xhr.onload = ((web.Event _) {
      _open.remove(xhr);
      final buffer = xhr.response;
      final bytes = buffer == null
          ? Uint8List(0)
          : (buffer as JSArrayBuffer).toDart.asUint8List();
      if (completer.isCompleted) return;
      if (bytes.length > maxResponseBytes) {
        fail('The response exceeds the download limit.');
        return;
      }
      completer.complete(
        http.StreamedResponse(
          Stream.value(bytes),
          xhr.status,
          contentLength: bytes.length,
          request: request,
          headers: _parseHeaders(xhr.getAllResponseHeaders()),
          reasonPhrase: xhr.statusText,
        ),
      );
    }).toJS;

    xhr.onerror = ((web.Event _) => fail('Network error')).toJS;
    xhr.ontimeout = ((web.Event _) => fail('Timed out')).toJS;
    xhr.onabort = ((web.Event _) => fail('Cancelled')).toJS;

    if (body.isEmpty && (request.method == 'GET' || request.method == 'HEAD')) {
      xhr.send();
    } else {
      xhr.send(body.toJS);
    }
    return completer.future;
  }

  static Map<String, String> _parseHeaders(String raw) {
    final headers = <String, String>{};
    for (final line in raw.split('\r\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final key = line.substring(0, i).trim().toLowerCase();
      final value = line.substring(i + 1).trim();
      headers[key] = headers.containsKey(key)
          ? '${headers[key]}, $value'
          : value;
    }
    return headers;
  }

  @override
  void close() {
    _closed = true;
    for (final xhr in _open.toList()) {
      xhr.abort();
    }
    _open.clear();
  }
}
