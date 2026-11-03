/// An `http.Client` that reports upload and download progress.
///
/// Dartus accepts any `http.Client`, so the app passes this one to
/// `WalrusClient` to show progress bars while Dartus does the Walrus calls.
library;

import 'package:http/http.dart' as http;

import 'progress_client_stub.dart'
    if (dart.library.js_interop) 'progress_client_web.dart'
    as impl;

typedef ProgressCallback = void Function(int done, int total);

/// [withCredentials] sends cookies on cross-origin requests too. The app
/// does not need it (the proxy is same-origin, so the browser sends the
/// session cookie anyway); the browser test does, because its server runs
/// on another port.
http.Client createProgressClient({
  ProgressCallback? onUpload,
  ProgressCallback? onDownload,
  bool withCredentials = false,
}) => impl.createProgressClient(
  onUpload: onUpload,
  onDownload: onDownload,
  withCredentials: withCredentials,
);
