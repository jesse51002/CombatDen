import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_row_action.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_training_toggle.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// One person on the signup roster: who they are, how to correct them, and —
/// for the payer — whether they are training too.
///
/// It is `add_member/group_roster_row.dart`'s composition at kiosk scale
/// (avatar + name pair + a trailing control run), with the one thing the desk
/// version has no need of: **a remove ✕, and only while removal is still
/// free.** There is no unlink call, so the moment this person's link or a
/// signature of theirs commits the ✕ goes away rather than becoming a button
/// that cannot do what it says.
///
/// **Edit appears only for a person this signup CREATED.** An existing member
/// is here by id alone: the kiosk deliberately never prints their stored
/// details on a shared screen, so offering to "edit" fields it refuses to show
/// would be an affordance that lies about what it opens.
class KioskRosterRow extends StatelessWidget {
  final KioskSignupPerson person;

  /// Their position on the roster — what every callback is keyed on.
  final int index;

  /// Whether the ✕ is offered at all (see [KioskSignupState.canRemovePerson]).
  final bool removable;

  final VoidCallback onDetails;
  final VoidCallback onRemove;
  final ValueChanged<bool> onTrainingChanged;

  const KioskRosterRow({
    super.key,
    required this.person,
    required this.index,
    required this.removable,
    required this.onDetails,
    required this.onRemove,
    required this.onTrainingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${person.firstName} ${person.lastName}'.trim();
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        InstructorAvatar(name: name, diameter: DesignConstants.iconSizeBig),
        Expanded(child: _Identity(name: name, person: person)),
        // A plain verb, not a status readout: what is or isn't on file is
        // nobody's business at a glance on a shared iPad, and "None yet"
        // beside a name only ever read as a nag.
        if (!person.wasExisting)
          KioskRowAction(
            semanticLabel: 'Edit $name',
            icon: Symbols.edit_sharp,
            label: 'Edit',
            onTap: onDetails,
          ),
        if (person.isPayer)
          KioskTrainingToggle(
            value: person.training,
            onChanged: onTrainingChanged,
          ),
        _Pill(person: person),
        if (removable)
          KioskRowAction(
            semanticLabel: 'Remove $name',
            icon: Symbols.close_sharp,
            onTap: onRemove,
          ),
      ],
    );
  }
}

/// The name over its one quiet second line. A payee's own email is theirs and
/// is shown; nothing else about them is.
class _Identity extends StatelessWidget {
  final String name;
  final KioskSignupPerson person;

  const _Identity({required this.name, required this.person});

  @override
  Widget build(BuildContext context) {
    final email = person.email.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          name,
          style: DesignConstants.kioskName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          email.isEmpty ? 'Added just now' : email,
          style: DesignConstants.kioskCaption.copyWith(
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
  final KioskSignupPerson person;

  const _Pill({required this.person});

  @override
  Widget build(BuildContext context) {
    final loud = person.isPayer;
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
        loud
            ? 'Paying'
            : person.wasExisting
                ? 'Member'
                : 'New',
        style: DesignConstants.kioskTag.copyWith(
          color: loud ? DesignConstants.onAccent : DesignConstants.text2nd,
        ),
      ),
    );
  }
}
