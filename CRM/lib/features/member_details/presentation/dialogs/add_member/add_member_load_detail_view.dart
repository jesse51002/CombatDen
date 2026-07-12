import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The sub-states of the load-detail step: fetching the new member, a load
/// error (retryable — the member is already persisted), or a frozen block
/// (a use-existing member must be unfrozen before adding a membership).
enum AddMemberLoadState { loading, error, frozen }

/// The load-detail step body — spinner, retryable error, or the frozen block.
/// The member is always persisted by this point, so neither error nor frozen
/// strands the user: the footer keeps Done / View member / Retry available.
class AddMemberLoadDetailView extends StatelessWidget {
  final AddMemberLoadState state;

  const AddMemberLoadDetailView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case AddMemberLoadState.loading:
        return const SizedBox(
          height: DesignConstants.dialogProcessingHeight,
          child: Center(child: AppSpinner()),
        );
      case AddMemberLoadState.error:
        return _Panel(
          icon: Symbols.error_sharp,
          color: DesignConstants.badRed,
          title: "We couldn't load the new member.",
          body: 'They were saved — retry, or open their profile to '
              'set up a membership later.',
        );
      case AddMemberLoadState.frozen:
        return _Panel(
          icon: Symbols.ac_unit_sharp,
          color: DesignConstants.okYellow,
          title: 'This member is frozen',
          body: 'Unfreeze this member before adding a membership.',
        );
    }
  }
}

class _Panel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Panel({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          icon,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: color,
        ),
        Text(title, style: DesignConstants.h2),
        Text(
          body,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
