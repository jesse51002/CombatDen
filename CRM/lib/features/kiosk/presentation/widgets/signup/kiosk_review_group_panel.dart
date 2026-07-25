import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_person_block.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// E4's left half: who is joining, one block per person.
///
/// A non-training payer still appears — they are on this screen because they
/// are paying for everyone on it, and a family review that silently dropped
/// the parent would read as though somebody had been forgotten. Their block
/// simply carries no membership row.
///
/// **After a PARTIAL failure the panel still lists everybody, and marks the
/// ones whose membership already started.** Re-entering the review through
/// "Try another card" re-shows the whole roster, and the same rule that keeps a
/// non-training payer on it keeps an already-charged person on it: removing a
/// row is indistinguishable from forgetting them. So
/// [KioskSignupState.alreadyStarted] MARKS instead — the next card is not
/// charged for them, which is a fact the panel has to state rather than imply
/// by absence.
///
/// The mark says **STARTED** because the receipt one screen back has just
/// defined that word for this member ("The ones marked Started are paid for"),
/// so the panel is re-using a vocabulary they already read rather than teaching
/// a second one.
class KioskReviewGroupPanel extends StatelessWidget {
  final KioskSignupState state;

  const KioskReviewGroupPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('WHO\'S JOINING', style: DesignConstants.kioskEyebrow),
          for (var i = 0; i < state.persons.length; i++) ...[
            if (i > 0) const Hairline(),
            KioskPersonBlock(
              person: state.persons[i],
              plan: MembershipPlanLike.of(state, state.persons[i]),
              started: state.alreadyStarted(state.persons[i]),
            ),
          ],
        ],
      ),
    );
  }
}
