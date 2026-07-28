import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Why the feed is showing a message instead of videos.
enum VideosFeedStatusKind {
  /// The feed request is still in flight.
  loading,

  /// The feed request failed.
  error,

  /// The request succeeded and the gym has no videos at all.
  empty,

  /// The gym has videos, but none in the selected top filter.
  scopeEmpty,
}

/// The feed's non-content state: one spinner, three messages.
///
/// Extracted so every layout format shows the identical state — a
/// format arranges videos, it does not get to reword or drop the
/// reason there are none.
class VideosFeedStatus extends StatelessWidget {
  const VideosFeedStatus({super.key, required this.kind});

  final VideosFeedStatusKind kind;

  String get _message => switch (kind) {
    VideosFeedStatusKind.loading => '',
    VideosFeedStatusKind.error => 'Couldn\'t load videos right now.',
    VideosFeedStatusKind.empty => 'No videos yet.',
    VideosFeedStatusKind.scopeEmpty => 'Nothing here yet.',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Center(
        child: kind == VideosFeedStatusKind.loading
            ? const CircularProgressIndicator()
            : Text(
                _message,
                textAlign: TextAlign.center,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
      ),
    );
  }
}
