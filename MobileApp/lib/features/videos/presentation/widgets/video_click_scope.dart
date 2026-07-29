import 'package:flutter/widgets.dart';

import 'package:mobile_app/features/videos/bloc/video_click_bloc.dart';

/// Carries the app-lifetime [VideoClickBloc] down to every video surface.
///
/// Mounted once above the app's routers (`main.dart`), which is what lets
/// `openVideoFor` report an open from ANY feed surface — the videos tab's hero
/// and carousels, a genre "view all" list, the profile's level-up carousel —
/// without each call site wiring a reporter of its own.
///
/// [maybeOf] returns null when the scope is absent instead of throwing: the
/// report is best-effort, so a surface pumped outside the app shell (a widget
/// test, the offline capture harness) opens the video and simply reports
/// nothing.
class VideoClickScope extends InheritedWidget {
  const VideoClickScope({
    super.key,
    required this.bloc,
    required super.child,
  });

  /// The reporter every video surface below this scope dispatches to.
  final VideoClickBloc bloc;

  /// The nearest reporter, or null when there is no scope above [context].
  static VideoClickBloc? maybeOf(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<VideoClickScope>();
    return scope?.bloc;
  }

  @override
  bool updateShouldNotify(VideoClickScope oldWidget) =>
      oldWidget.bloc != bloc;
}
