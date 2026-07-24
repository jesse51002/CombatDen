import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [bytes] saved as [filename].
///
/// The CRM is a web-only app, so this uses `package:web` directly: wrap the
/// bytes in a [web.Blob], mint an object URL for it, click a synthetic
/// `<a download>` anchor, then revoke the URL. The click starts the download
/// synchronously, so revoking immediately after is safe.
void downloadBytes(Uint8List bytes, String filename) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  final url = web.URL.createObjectURL(blob);
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}
