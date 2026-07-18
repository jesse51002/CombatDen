import 'package:flutter/material.dart';

import 'package:crm/shared/widgets/dashed_add_tile.dart';

/// "New member" adder tile for the members step — sits above the link-first
/// tile. Uses the shared dashed-accent [DashedAddTile] idiom. Tapping opens the
/// in-run new-member dialog.
class StartNewMemberTile extends StatelessWidget {
  /// Payer's first name, woven into the subtitle so staff see who the new
  /// member will be authorized under.
  final String payerFirstName;
  final VoidCallback onTap;

  const StartNewMemberTile({
    super.key,
    required this.payerFirstName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DashedAddTile(
      title: 'New member',
      subtitle: 'Create a new member $payerFirstName will '
          'purchase a membership for.',
      onTap: onTap,
    );
  }
}
