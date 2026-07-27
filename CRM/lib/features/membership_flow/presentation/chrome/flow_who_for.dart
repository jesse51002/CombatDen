import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// Who this screen is about, pinned to the top of the step and never scrolled
/// away (the pinned band belongs to `FlowStepScaffold`). It is
/// `FlowSignPanel`'s "signing for" banner laid on its side: the same avatar +
/// eyebrow + name, at row scale, centred on the stage.
///
/// The [eyebrow] names the RELATIONSHIP and the CALLER decides whose name goes
/// with it: the plan and waiver steps pass the ACTIVE person, the card step
/// passes the PAYER, who in a family is a different human — a child's name over
/// a field that attaches a card to the parent's profile would be confidently
/// wrong, which is worse than saying nothing.
class FlowWhoFor extends StatelessWidget {
  /// "PICKING FOR" / "WAIVER FOR" / "PAYING FOR" / "CARD FOR". It must not
  /// repeat a phrase the step's own panel already carries.
  final String eyebrow;

  /// The person's full name, as the gym knows it.
  final String name;

  const FlowWhoFor({
    super.key,
    required this.eyebrow,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.primaryColor10,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            InstructorAvatar(
              name: name,
              diameter: DesignConstants.iconSizeLarge,
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(eyebrow, style: scale.eyebrow),
                  Text(
                    name,
                    style: scale.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
