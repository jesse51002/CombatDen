import 'package:flutter/foundation.dart';

/// Capture-only override clock for the one-shot reveal animations
/// ([ScaleReveal] / [StaggeredReveal]).
///
/// In normal app use this stays **null** and each reveal animates itself on its
/// own controller. The capture harness (`tools/capture/`) sets it to a fixed
/// elapsed time per exported frame, so a reveal is driven deterministically and
/// plays at true speed in the export — even though `RepaintBoundary.toImage` is
/// far slower than real time (capturing the reveal in real time would under-
/// sample and look sped up). Each reveal computes its own progress from this
/// clock minus its own `delay`, so the stagger is preserved.
///
/// It's a [ValueNotifier] so the (often `const`) reveal subtree rebuilds as the
/// harness advances the clock.
final ValueNotifier<Duration?> captureRevealClock =
    ValueNotifier<Duration?>(null);
