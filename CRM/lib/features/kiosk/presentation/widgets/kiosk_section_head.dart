import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A section heading, in two weights. The default is the LOUD home head, the
/// primary thing on a home half. [quiet] is the demoted variant for a screen
/// whose PICKABLE ROWS dominate (the payer picker) — a small, muted,
/// left-aligned label that doesn't compete with the rows beneath it.
class KioskSectionHead extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Render as a quiet left-aligned label instead of a loud centred title.
  final bool quiet;

  const KioskSectionHead({
    super.key,
    required this.title,
    required this.subtitle,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    if (quiet) return _QuietHead(title: title, subtitle: subtitle);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          title,
          style: DesignConstants.kioskTitle,
          textAlign: TextAlign.center,
        ),
        Text(
          subtitle,
          style: DesignConstants.kioskSectionText.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The demoted head, letting the pickable rows below it dominate.
class _QuietHead extends StatelessWidget {
  final String title;
  final String subtitle;

  const _QuietHead({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          title,
          style: DesignConstants.kioskLabel.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Text(
          subtitle,
          style: DesignConstants.kioskCaption.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
