import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// DEBUG-ONLY. The identity sheet's Developer rows: the three screens a push
/// notification lands a member on, opened by hand.
///
/// None is otherwise reachable while the app is running — the post-class
/// celebration only fires off a fresh staff check-in (and burns its watermark
/// doing it), a real belt promotion burns ITS watermark on first sight so
/// nobody can look at it twice, and "Drill of the Day" is never shown
/// automatically. This previews what the member SEES on those screens; it says
/// nothing about push delivery or the 24h timing, which land with the
/// notification work.
///
/// Compiled out of release builds entirely: the caller wraps it in
/// `if (kDebugMode)`.
class IdentitySheetDevSection extends StatelessWidget {
  const IdentitySheetDevSection({
    super.key,
    required this.onCelebration,
    required this.onPromotion,
    required this.onSummary,
  });

  /// Force the post-class celebration flow open (watermark untouched).
  final VoidCallback onCelebration;

  /// Open the belt-promotion card (watermark untouched).
  final VoidCallback onPromotion;

  /// Open "Drill of the Day".
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Simulates opening a notification. The pushes themselves come later.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text3rd,
          ),
        ),
        _DevRow(
          icon: Symbols.celebration_sharp,
          label: 'Post-class celebration',
          onTap: onCelebration,
        ),
        _DevRow(
          icon: Symbols.military_tech_sharp,
          label: 'Belt promotion',
          onTap: onPromotion,
        ),
        _DevRow(
          icon: Symbols.play_circle_sharp,
          label: 'Drill of the Day',
          onTap: onSummary,
        ),
      ],
    );
  }
}

/// The sign-out row's treatment verbatim — plain, unfilled, uncarded — so the
/// sheet keeps ONE row idiom below its divider instead of growing a second.
class _DevRow extends StatelessWidget {
  const _DevRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.spacingLarge,
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                icon,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text2nd,
                size: DesignConstants.iconSizeSm,
              ),
              Text(
                label,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
