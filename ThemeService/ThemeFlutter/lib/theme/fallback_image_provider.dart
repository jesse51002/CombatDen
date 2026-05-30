import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// An [ImageProvider] that tries [primary] and transparently degrades to
/// [fallback] if the primary fails to load (404, timeout, corrupt bytes).
///
/// This is what makes the ThemeService a *best-effort* live
/// override: a bad override asset must never surface as a thrown
/// `HttpException` or a broken image box in the app — it falls back to the
/// caller's bundled asset, exactly as an empty/absent slot already does.
/// See `ThemeImage`, which wraps every resolved network slot in one of
/// these.
///
/// [ImageProvider.resolve] is `@nonVirtual`, so the composition is done in
/// [loadImage] via a relay [ImageStreamCompleter] that forwards the
/// primary's frames and, on the primary's error, resolves and forwards the
/// fallback's instead. Because the relay supplies an error listener, the
/// primary failure is handled rather than dumped to `FlutterError`.
/// [obtainKey] threads the ambient [ImageConfiguration] through so both
/// delegates resolve against it. Web-safe (pure framework API, no
/// `dart:io`).
@immutable
class FallbackImageProvider extends ImageProvider<FallbackImageProvider> {
  const FallbackImageProvider(
    this.primary,
    this.fallback, [
    this.configuration = ImageConfiguration.empty,
  ]);

  /// Tried first (the network/override asset).
  final ImageProvider primary;

  /// Relayed in if [primary] errors (the caller's bundled asset).
  final ImageProvider fallback;

  /// The ambient configuration captured by [obtainKey], used to resolve
  /// both delegates. Intentionally excluded from `==`/[hashCode] so the
  /// image cache keys purely on the (primary, fallback) pair.
  final ImageConfiguration configuration;

  @override
  Future<FallbackImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<FallbackImageProvider>(
      FallbackImageProvider(primary, fallback, configuration),
    );
  }

  @override
  ImageStreamCompleter loadImage(
    FallbackImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return _FallbackImageStreamCompleter(
      key.primary,
      key.fallback,
      key.configuration,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FallbackImageProvider &&
        other.primary == primary &&
        other.fallback == fallback;
  }

  @override
  int get hashCode => Object.hash(primary, fallback);
}

/// Forwards [primary]'s image events; on a primary error, logs once and
/// forwards [fallback]'s events instead.
///
/// Listeners are removed when this completer's own last listener is removed
/// (via [addOnLastListenerRemovedCallback]), so neither the primary nor the
/// fallback upstream retains a stale closure reference.
class _FallbackImageStreamCompleter extends ImageStreamCompleter {
  _FallbackImageStreamCompleter(
    ImageProvider primary,
    ImageProvider fallback,
    ImageConfiguration configuration,
  ) {
    _primaryStream = primary.resolve(configuration);
    _primaryListener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) => setImage(image),
      onChunk: (ImageChunkEvent event) => reportImageChunkEvent(event),
      onError: (Object exception, StackTrace? stackTrace) {
        // Swallow the failure visually but keep it diagnosable.
        debugPrint('[CUSTOMIZATION] image slot fell back: $exception');
        _fallbackStream = fallback.resolve(configuration);
        _fallbackListener = ImageStreamListener(
          (ImageInfo image, bool synchronousCall) => setImage(image),
          onChunk: (ImageChunkEvent event) => reportImageChunkEvent(event),
          // The bundled fallback failing is a real (build) bug —
          // surface it normally.
          onError: (Object exception, StackTrace? stackTrace) =>
              reportError(exception: exception, stack: stackTrace),
        );
        _fallbackStream!.addListener(_fallbackListener!);
      },
    );
    _primaryStream.addListener(_primaryListener);

    addOnLastListenerRemovedCallback(_detach);
  }

  late final ImageStream _primaryStream;
  late final ImageStreamListener _primaryListener;
  ImageStream? _fallbackStream;
  ImageStreamListener? _fallbackListener;

  void _detach() {
    _primaryStream.removeListener(_primaryListener);
    final fallbackStream = _fallbackStream;
    final fallbackListener = _fallbackListener;
    if (fallbackStream != null && fallbackListener != null) {
      fallbackStream.removeListener(fallbackListener);
    }
  }
}
