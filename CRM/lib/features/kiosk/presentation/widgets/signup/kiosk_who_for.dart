import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// **Who this screen is about**, pinned to the top of the step and never
/// scrolled away.
///
/// A parent picking three memberships and signing four waivers in a row loses
/// track of which child they are on the moment the heading scrolls off — and
/// the cost of that is buying the wrong plan for the wrong person, or putting
/// a card on the wrong profile. So the answer stays on the fold for the whole
/// step (see `KioskSignupStepScaffold`'s pinned band).
///
/// It is `KioskSignPanel`'s "signing for" banner laid on its side: the same
/// avatar + eyebrow + name, at row scale, centred on the stage.
///
/// **The [eyebrow] names the RELATIONSHIP, and the caller decides whose name
/// goes with it.** The plan and waiver steps pass the ACTIVE person; the card
/// step passes the PAYER, who in a family is a different human — showing a
/// child's name over a field that attaches a card to the parent's profile
/// would be confidently wrong, which is worse than saying nothing.
class KioskWhoFor extends StatelessWidget {
  /// "PICKING FOR" / "WAIVER FOR" / "PAYING FOR" / "CARD FOR". It must not
  /// repeat a phrase the step's own panel already carries — one screen saying
  /// the same two words twice teaches neither of them.
  final String eyebrow;

  /// The person's full name, as the gym knows it.
  final String name;

  const KioskWhoFor({
    super.key,
    required this.eyebrow,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
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
                  Text(eyebrow, style: DesignConstants.kioskEyebrow),
                  Text(
                    name,
                    style: DesignConstants.kioskName,
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
