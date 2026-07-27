import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_consent_check.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_row_action.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// One person on the purchase roster: who they are, whether they are getting a
/// membership, and how to correct or remove them.
///
/// STACKED, not one line: the membership check decides whether this person is
/// charged, so it gets a line of its own rather than a 15px label competing
/// with an avatar, a pill and two icon buttons at arm's length on an iPad.
///
/// The check is on EVERY row and defaults ON — payer, payee, created here or
/// matched — and unchecking everybody is a legitimate registration-only signup
/// rather than an error. Edit appears only where the surface OWNS the record
/// ([FlowPersonView.editable]): the kiosk prints no stored detail of an
/// existing member on a shared screen, so offering to edit fields it refuses
/// to show would lie about what it opens. Remove ASKS first, and is offered
/// only while removal is still free ([FlowPersonView.removable]) — there is no
/// unlink call, so it goes away once this person's link or signature commits
/// rather than becoming a button that cannot do what it says.
class FlowRosterRow extends StatelessWidget {
  final FlowPersonView person;

  /// Whether this roster holds more than one person, which is the only thing
  /// that makes "as well" mean anything.
  final bool isGroup;

  final VoidCallback onDetails;
  final VoidCallback onRemove;
  final ValueChanged<bool> onTrainingChanged;

  /// The check's own second line — what unticking this row would COST.
  ///
  /// It belongs to the check rather than to the row beneath it, because the
  /// consequence is the check's: a surface that renders it separately has to
  /// re-derive this control's indent, and the two drift the moment either
  /// moves. Null on a row with nothing to lose — a warning nobody needs is the
  /// fastest way to teach people to ignore the ones that matter.
  final String? checkNote;

  const FlowRosterRow({
    super.key,
    required this.person,
    required this.isGroup,
    required this.onDetails,
    required this.onRemove,
    required this.onTrainingChanged,
    this.checkNote,
  });

  @override
  Widget build(BuildContext context) {
    final copy = MembershipFlowTheme.copyOf(context);
    final name = person.fullName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            InstructorAvatar(name: name, diameter: DesignConstants.iconSizeBig),
            Expanded(child: _Identity(person: person)),
            // A plain verb, not a status readout: what is or isn't on file is
            // nobody's business at a glance on a shared iPad.
            if (person.editable)
              FlowRowAction(
                semanticLabel: copy.editSemantic(name),
                icon: Symbols.edit_sharp,
                label: copy.editAction,
                onTap: onDetails,
              ),
            _Pill(role: person.role),
            if (person.removable)
              FlowRowAction(
                semanticLabel: copy.removeSemantic(name),
                icon: Symbols.delete_sharp,
                onTap: onRemove,
              ),
          ],
        ),
        // The line that decides whether this person is charged, in the
        // surface's own voice: "as well" only means something beside somebody
        // else, which is what `isGroup` tells the copy.
        FlowConsentCheck(
          value: person.training,
          onChanged: onTrainingChanged,
          label: copy.rosterTrainingCheck(
            firstName: person.firstName,
            isGroup: isGroup,
          ),
          note: checkNote,
        ),
      ],
    );
  }
}

/// The name over its one quiet second line — the person's address as the HOST
/// decided this surface may print it ([FlowPersonView.identityLine]).
///
/// The kiosk masks it: the roster is the screen a queue reads over the
/// member's shoulder, and it lists an adopted existing member whose address
/// came from the gym's records rather than from anyone standing there, so the
/// line says enough to recognise and never enough to copy.
class _Identity extends StatelessWidget {
  final FlowPersonView person;

  const _Identity({required this.person});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    // Null before their details step has run, which is what the copy's
    // pending line answers.
    final line = person.identityLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          person.fullName,
          style: scale.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          line ?? copy.rosterPendingLine,
          style: scale.caption.copyWith(
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// "Paying" on the payer, and on a payee whichever of "Member" / "New" is
/// true. The payer's is the loud one because it is the fact that explains the
/// whole screen: one card covers everybody here.
class _Pill extends StatelessWidget {
  final FlowPersonRole role;

  const _Pill({required this.role});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    final loud = role == FlowPersonRole.paying;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: loud ? DesignConstants.primaryColor : DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: loud ? null : Border.all(color: DesignConstants.line),
      ),
      child: Text(
        switch (role) {
          FlowPersonRole.paying => copy.payingPill,
          FlowPersonRole.member => copy.memberPill,
          FlowPersonRole.newcomer => copy.newcomerPill,
        },
        style: scale.tag.copyWith(
          color: loud ? DesignConstants.onAccent : DesignConstants.text2nd,
        ),
      ),
    );
  }
}
