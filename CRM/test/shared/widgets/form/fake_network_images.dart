import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart'
    show PaintingBinding, debugNetworkImageHttpClientProvider;

/// A 1x1 transparent PNG — the canonical bytes decoded by widget-test image
/// helpers. Served for every URL that is not asked to fail.
final Uint8List _kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

/// Runs [body] with a fake image HTTP client so `Image.network` resolves
/// without touching the network. URLs in [failUrls] answer 404 (so the
/// widget's `errorBuilder` fires); every other URL answers 200 with a 1x1
/// transparent PNG (so the image loads and its chip renders).
///
/// Wrap the whole test body (pump + assertions). Two globals fight this, so
/// the wrapper owns both: it clears the process-wide [imageCache] up front so a
/// success decoded in an earlier test can't shadow this test's fake response,
/// and it resets [debugNetworkImageHttpClientProvider] in a `finally` — the
/// reset must happen inside the body, before the framework's end-of-test
/// "painting debug vars unset" invariant check (a plain `tearDown` is too
/// late). Uses Flutter's documented [debugNetworkImageHttpClientProvider] hook
/// (consulted per image load in debug/test builds), so it needs no zones and
/// no extra packages.
Future<void> withFakeNetworkImages(
  Future<void> Function() body, {
  Set<String> failUrls = const <String>{},
}) async {
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.clear();
  imageCache.clearLiveImages();
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient(failUrls);
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._failUrls);

  final Set<String> _failUrls;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_failUrls.contains(url.toString()));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._fail);

  final bool _fail;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _fail
      ? _FakeHttpClientResponse(const <int>[], HttpStatus.notFound)
      : _FakeHttpClientResponse(_kTransparentPng, HttpStatus.ok);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

class _FakeHttpHeaders implements HttpHeaders {
  // NetworkImage only ever calls `add` (and only when custom headers are
  // passed, which these tests don't). A permissive no-op keeps it safe.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._bytes, this.statusCode);

  final List<int> _bytes;

  @override
  final int statusCode;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}
