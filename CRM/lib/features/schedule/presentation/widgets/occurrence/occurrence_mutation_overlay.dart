import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// A dimmed scrim + centered spinner over the occurrence screen's content
/// while a mutation (override save / cancel this class) + board reload run.
/// Mirrors `member_detail_screen.dart`'s `_MutationOverlay` — a
/// `Positioned.fill` sibling of the real content in a `Stack`, not a
/// full-screen replacement, so the terminal success `AppDialog` appears over
/// the actual occurrence content instead of a blank spinner page.
class OccurrenceMutationOverlay extends StatelessWidget {
  const OccurrenceMutationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.text.withValues(alpha: 0.08),
      child: const Center(child: AppSpinner()),
    );
  }
}
