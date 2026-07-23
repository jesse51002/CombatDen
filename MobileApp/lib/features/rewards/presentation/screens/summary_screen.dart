import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/app_slots.dart';
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
import 'package:theme_flutter/theme/theme_text.dart';

/// "Drill of the Day" — one portal-sourced drill video plus a book-your-next-
/// class nudge. Reachable ONLY by an explicit push on its named route
/// (`AppRoutes.summary`); it is NEVER shown automatically. Its real trigger is a
/// push notification fired ~24h after a class that deep-links here when the
/// member OPENS the notification — that push is a follow-up PR (it needs the FCM
/// stack); this screen is the target it will open.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  static const String _kTitle = 'Drill of the Day';

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VideoRecBloc>(
      create: (_) => VideoRecBloc(
        repository: MemberVideosRepository(apiClient: ApiClient()),
      )..add(const VideoRecRequested()),
      child: const _DrillView(title: _kTitle),
    );
  }
}

class _DrillView extends StatelessWidget {
  const _DrillView({required this.title});

  final String title;

  void _home(BuildContext context) => Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);

  @override
  Widget build(BuildContext context) {
    final ctaLabel = ThemeText.value(
      CombatDenSlots.bookNextClassCta,
      fallback: 'Book your next class',
    );
    return BlocBuilder<VideoRecBloc, VideoRecState>(
      builder: (context, state) {
        if (state.status == VideoRecStatus.loaded && state.rec != null) {
          return RecVideoLayout(
            title: title,
            card: state.rec!.video,
            ctaLabel: ctaLabel,
            onCtaPressed: () => _home(context),
            onClose: () => _home(context),
          );
        }
        // No drill available (loading / empty / error) — never trap the
        // member: show a titled frame with the book-next-class nudge.
        final loading =
            state.status == VideoRecStatus.initial ||
            state.status == VideoRecStatus.loading;
        return _DrillPlaceholder(
          title: title,
          loading: loading,
          ctaLabel: loading ? null : ctaLabel,
          onCta: () => _home(context),
          onClose: () => _home(context),
        );
      },
    );
  }
}

class _DrillPlaceholder extends StatelessWidget {
  const _DrillPlaceholder({
    required this.title,
    required this.onClose,
    this.loading = false,
    this.ctaLabel,
    this.onCta,
  });

  final String title;
  final VoidCallback onClose;
  final bool loading;
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
                        'No drill right now — keep the streak going.',
                        textAlign: TextAlign.center,
                        style: DesignConstants.p.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
              ),
            ),
            if (ctaLabel != null)
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
