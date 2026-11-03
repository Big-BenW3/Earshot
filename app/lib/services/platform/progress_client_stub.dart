import 'package:http/http.dart' as http;

import 'progress_client.dart' show ProgressCallback;

/// Outside the browser there is no XHR progress; a plain client is used.
http.Client createProgressClient({
  ProgressCallback? onUpload,
  ProgressCallback? onDownload,
  bool withCredentials = false,
}) => http.Client();
