import 'package:flutter/foundation.dart';

/// Coordinates the post-class celebration screen with its body's intro
/// animation. While the body is animating, the scaffold hides the CTA and
/// treats taps on the body area as "skip the animation". When the body
/// reaches its final settled state it calls [markDone] so the CTA appears.
///
/// Usage:
/// 1. Screen creates a controller in `initState` and disposes it.
/// 2. Pass the same controller to both `PostClassScaffold` and the body
///    (e.g. `StreakBody(controller: _controller)`).
/// 3. Body registers a skip handler in its `initState` via
///    [registerSkipHandler]; the handler should jump straight to the
///    final visual state.
/// 4. Body calls [markDone] once it reaches that final state — whether
///    via natural progression or a skip.
class PostClassController extends ChangeNotifier {
  bool _isAnimating = true;
  VoidCallback? _skipHandler;

  bool get isAnimating => _isAnimating;

  void registerSkipHandler(VoidCallback handler) {
    _skipHandler = handler;
  }

  void clearSkipHandler() {
    _skipHandler = null;
  }

  /// Called by the scaffold when the user taps during the intro.
  /// Forwards to the body's registered handler (a no-op if no body has
  /// claimed it yet).
  void requestSkip() {
    if (!_isAnimating) return;
    _skipHandler?.call();
  }

  /// Body signals that its intro is complete and the CTA can appear.
  void markDone() {
    if (!_isAnimating) return;
    _isAnimating = false;
    notifyListeners();
  }
}
