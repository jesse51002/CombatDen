import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_bloc.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_event.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_state.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';
import 'package:mobile_app/features/videos/presentation/widgets/rec/rec_video_layout.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_header.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Full-screen video recommendation surfaced after booking a class. Loads the
/// member's next rotating-category rec from the portal; pressing "Watch"
/// records the open (a best-effort click) and closes. A missing rec (404) is a
/// dismissible placeholder, so the flow is never trapped.
class VideoReccScreen extends StatelessWidget {
  const VideoReccScreen({super.key});

  static const String _kTitle = 'Video Before Class';

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VideoRecBloc>(
      create: (_) => VideoRecBloc(
        repository: MemberVideosRepository(apiClient: ApiClient()),
      )..add(const VideoRecRequested()),
      child: const _RecView(title: _kTitle),
    );
  }
}

class _RecView extends StatelessWidget {
  const _RecView({required this.title});

  final String title;

  void _close(BuildContext context) => Navigator.of(context).pop();

  void _open(BuildContext context) {
    // Record the open best-effort, then close immediately — the click never
    // blocks navigation (fire-and-forget in the bloc).
    context.read<VideoRecBloc>().add(const VideoRecOpened());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VideoRecBloc, VideoRecState>(
      builder: (context, state) {
        switch (state.status) {
          case VideoRecStatus.loaded:
            final rec = state.rec;
            if (rec == null) {
              return _Placeholder(
                title: title,
                onClose: () => _close(context),
              );
            }
            return RecVideoLayout(
              title: title,
              card: rec.video,
              ctaLabel: 'Watch',
              onCtaPressed: () => _open(context),
              onClose: () => _close(context),
            );
          case VideoRecStatus.error:
            return _Placeholder(
              title: title,
              message: state.errorMessage ?? 'No recommendation right now.',
              ctaLabel: 'Retry',
              onCta: () =>
                  context.read<VideoRecBloc>().add(const VideoRecRequested()),
              onClose: () => _close(context),
            );
          case VideoRecStatus.empty:
            return _Placeholder(
              title: title,
              message: 'No recommendation right now.',
              ctaLabel: 'Continue',
              onCta: () => _close(context),
              onClose: () => _close(context),
            );
          case VideoRecStatus.initial:
          case VideoRecStatus.loading:
            return _Placeholder(
              title: title,
              loading: true,
              onClose: () => _close(context),
            );
        }
      },
    );
  }
}

/// The loading / empty / error frame — a titled header with a close action and
/// a centered spinner or message (plus an optional CTA), so a celebration flow
/// is never trapped. Mirrors the old flow's placeholder.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.onClose,
    this.loading = false,
    this.message,
    this.ctaLabel,
    this.onCta,
  });

  final String title;
  final VoidCallback onClose;
  final bool loading;
  final String? message;
  final String? ctaLabel;
  final VoidCallback? onCta;

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
                        message ?? 'No recommendation right now.',
                        textAlign: TextAlign.center,
                        style: DesignConstants.p.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
              ),
            ),
            if (!loading && ctaLabel != null)
              AppPrimaryButton(
                text: ctaLabel!,
                fullWidth: true,
                borderRadius: DesignConstants.radiusBig,
                onPressed: onCta,
              ),
          ],
        ),
      ),
    );
  }
}
