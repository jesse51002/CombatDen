import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Copy for each status — public so the section's tests assert on the same
/// strings the user reads.
const String kGymProfileIdleText = 'Changes save automatically.';
const String kGymProfileSavingText = 'Saving…';
const String kGymProfileSavedText = 'Saved.';
const String kGymProfileErrorText =
    'Couldn\'t save your gym profile. Your changes are still on screen, so '
    'nothing was lost.';

/// The four states of the Gym profile's auto-save.
enum GymProfileSaveStatus { idle, saving, saved, error }

/// Fade between states — never a size animation, which is exactly what
/// would make the fields below jump.
const Duration _kFade = Duration(milliseconds: 200);

/// The Gym profile section's inline save status — the confirmation that
/// replaces the removed "Save gym profile" button.
///
/// It is **permanently present**, not transient-only: the idle line states
/// the auto-save contract *before* the user blurs a field, which a
/// disappearing toast can't do. All four states share one row of constant
/// height so nothing below shifts, and every state is icon + word (never
/// colour alone).
///
/// [GymProfileSaveStatus.error] is the one state that escalates out of the
/// row into the shared [ErrorMessage] banner plus an explicit retry button:
/// the automatic path failed, so the manual one is earned — "blur the field
/// again" would be undiscoverable.
class GymProfileSaveStatusView extends StatelessWidget {
  final GymProfileSaveStatus status;

  /// Retry the failed save. Only rendered in [GymProfileSaveStatus.error].
  final VoidCallback onRetry;

  const GymProfileSaveStatusView({
    super.key,
    required this.status,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      liveRegion: true,
      label: switch (status) {
        GymProfileSaveStatus.idle => kGymProfileIdleText,
        GymProfileSaveStatus.saving => kGymProfileSavingText,
        GymProfileSaveStatus.saved => kGymProfileSavedText,
        GymProfileSaveStatus.error => kGymProfileErrorText,
      },
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : _kFade,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: switch (status) {
          GymProfileSaveStatus.error => _Failure(
              key: const ValueKey('gym-profile-status-error'),
              onRetry: onRetry,
            ),
          _ => _StatusLine(
              key: ValueKey(status),
              status: status,
            ),
        },
      ),
    );
  }
}

/// The one-line idle / saving / saved row. The leading slot is always filled
/// at [DesignConstants.iconSizeTiny], so the row's height never changes.
class _StatusLine extends StatelessWidget {
  final GymProfileSaveStatus status;

  const _StatusLine({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        _leading(),
        Text(_text(), style: _style()),
      ],
    );
  }

  Widget _leading() {
    if (status == GymProfileSaveStatus.saving) {
      return const AppSpinner(size: DesignConstants.iconSizeTiny);
    }
    return Icon(
      status == GymProfileSaveStatus.saved
          ? Symbols.check_circle_sharp
          : Symbols.info_sharp,
      size: DesignConstants.iconSizeTiny,
      color: status == GymProfileSaveStatus.saved
          ? DesignConstants.goodGreen
          : DesignConstants.text3rd,
      weight: DesignConstants.iconWeight,
    );
  }

  String _text() => switch (status) {
        GymProfileSaveStatus.saving => kGymProfileSavingText,
        GymProfileSaveStatus.saved => kGymProfileSavedText,
        _ => kGymProfileIdleText,
      };

  TextStyle _style() => switch (status) {
        GymProfileSaveStatus.saving =>
          DesignConstants.pSmall.copyWith(color: DesignConstants.text2nd),
        GymProfileSaveStatus.saved => DesignConstants.pSmallSemibold
            .copyWith(color: DesignConstants.goodGreen),
        _ => DesignConstants.pSmall.copyWith(color: DesignConstants.text3rd),
      };
}

/// The failure state: the shared error banner plus the retry the auto-save
/// path can no longer offer on its own.
class _Failure extends StatelessWidget {
  final VoidCallback onRetry;

  const _Failure({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        const ErrorMessage(message: kGymProfileErrorText),
        AppOutlineButton(
          text: 'Try again',
          onPressed: onRetry,
          borderRadius: DesignConstants.radiusSmall,
        ),
      ],
    );
  }
}
