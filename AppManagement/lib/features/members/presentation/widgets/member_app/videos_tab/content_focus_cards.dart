import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/shared/widgets/app_spinner.dart';

/// The agent-authored descriptions that steer the feed: "We surface" and
/// "We avoid" side by side, for the selected gym. Each shows the SHORT summary
/// for an at-a-glance read; the full prompt lives in the agent view's prompt
/// panel. Plain blocks (no card chrome) so they sit inside another card
/// without nesting.
class ContentFocusCards extends StatelessWidget {
  const ContentFocusCards({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        if (selectedGym.gymId == null) {
          return const _FocusMessage(
            'Select a gym in the Theme tab to see its content focus.',
          );
        }
        final spec = selectedGym.detail?.spec;
        if (spec == null) {
          return _FocusMessage(
            selectedGym.error != null
                ? 'Could not reach the video service to load the content focus.'
                : null,
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingBig,
            children: [
              Expanded(
                child: _DescBlock(
                  icon: Symbols.check_circle_sharp,
                  iconColor: DesignConstants.goodGreen,
                  heading: 'We surface',
                  body: spec.surfaceSummary,
                ),
              ),
              Expanded(
                child: _DescBlock(
                  icon: Symbols.block_sharp,
                  iconColor: DesignConstants.badRed,
                  heading: 'We avoid',
                  body: spec.avoidSummary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DescBlock extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String heading;
  final String body;

  const _DescBlock({
    required this.icon,
    required this.iconColor,
    required this.heading,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              icon,
              color: iconColor,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
            ),
            Text(heading, style: DesignConstants.h2),
          ],
        ),
        Text(
          body,
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Loading (null message) / error chrome while the gym detail resolves.
class _FocusMessage extends StatelessWidget {
  final String? message;

  const _FocusMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const AppSpinner()
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
