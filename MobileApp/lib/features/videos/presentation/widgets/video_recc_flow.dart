import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_header.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_layout.dart';

/// Fetches the shared video feed and renders a [VideoReccLayout] for the
/// video [selectVideo] picks from it. Shows a spinner while loading and a
/// dismissible placeholder when the tenant has no suitable video, so a
/// celebration flow is never trapped.
class VideoReccFlow extends StatelessWidget {
  const VideoReccFlow({
    super.key,
    required this.title,
    required this.ctaLabel,
    required this.selectVideo,
    required this.onClose,
    required this.onCtaPressed,
  });

  final String title;
  final String ctaLabel;
  final Video? Function(List<Video> videos) selectVideo;
  final VoidCallback onClose;
  final VoidCallback onCtaPressed;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Video>>(
      future: VideoFeedRepository.instance.feed(),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final video = (loading || snapshot.hasError)
            ? null
            : selectVideo(snapshot.data ?? const <Video>[]);
        if (video != null) {
          return VideoReccLayout(
            title: title,
            video: video,
            ctaLabel: ctaLabel,
            onClose: onClose,
            onCtaPressed: onCtaPressed,
          );
        }
        return _ReccPlaceholder(
          title: title,
          loading: loading,
          ctaLabel: ctaLabel,
          onClose: onClose,
          onCtaPressed: onCtaPressed,
        );
      },
    );
  }
}

class _ReccPlaceholder extends StatelessWidget {
  const _ReccPlaceholder({
    required this.title,
    required this.loading,
    required this.ctaLabel,
    required this.onClose,
    required this.onCtaPressed,
  });

  final String title;
  final bool loading;
  final String ctaLabel;
  final VoidCallback onClose;
  final VoidCallback onCtaPressed;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            VideoReccHeader(title: title, onClose: onClose),
            Expanded(
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : Text(
                        'No recommendation right now.',
                        textAlign: TextAlign.center,
                        style: DesignConstants.p.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
              ),
            ),
            if (!loading)
              AppPrimaryButton(
                text: ctaLabel,
                fullWidth: true,
                borderRadius: DesignConstants.radiusBig,
                onPressed: onCtaPressed,
              ),
          ],
        ),
      ),
    );
  }
}
