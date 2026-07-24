import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_consent_check.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_row_action.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// One person on the signup roster: who they are, whether they are getting a
/// membership, and how to correct or remove them.
///
/// **It is STACKED, not one line.** The identity and its controls sit on the
/// top row; the membership check gets a line of its own underneath. Crammed
/// inline it was a 15px label competing with an avatar, a pill and two icon
/// buttons — unreadable at arm's length on an iPad, and the one control on the
/// row that decides whether this person is charged.
///
/// **The membership check is on EVERY row and defaults ON** — payer, payee,
/// created here or matched to an existing member. A payer-only special case
/// was one more thing to explain on a screen that has to explain itself, and
/// unchecking everybody is a legitimate registration-only signup rather than
/// an error.
///
/// **Edit appears only for a person this signup CREATED.** An existing member
/// is here by id alone: the kiosk deliberately never prints their stored
/// details on a shared screen, so offering to "edit" fields it refuses to show
/// would be an affordance that lies about what it opens.
///
/// **Remove is a trash control that ASKS first**, and only while removal is
/// still free — there is no unlink call, so the moment this person's link or a
/// signature of theirs commits it goes away rather than becoming a button that
/// cannot do what it says.
class KioskRosterRow extends StatelessWidget {
  final KioskSignupPerson person;

  /// Their position on the roster — what every callback is keyed on.
  final int index;

  /// Whether the trash control is offered at all (see
  /// [KioskSignupState.canRemovePerson]).
  final bool removable;

  /// Whether this roster holds more than one person, which is the only thing
  /// that makes "as well" mean anything.
  final bool isGroup;

  final VoidCallback onDetails;
  final VoidCallback onRemove;
  final ValueChanged<bool> onTrainingChanged;

  const KioskRosterRow({
    super.key,
    required this.person,
    required this.index,
    required this.removable,
    required this.isGroup,
    required this.onDetails,
    required this.onRemove,
    required this.onTrainingChanged,
  });

  /// The founder's line, with "as well" earned rather than assumed: it only
  /// means something beside somebody else, so a roster of one drops it instead
  /// of comparing a person to nobody.
  String get _checkLabel => isGroup
      ? '${person.firstName.trim().isEmpty ? 'This person' : person.firstName}'
          ' is getting a membership as well'
      : 'I\'m getting a membership';

  @override
  Widget build(BuildContext context) {
    final name = '${person.firstName} ${person.lastName}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
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
            _Pill(person: person),
            if (removable)
              KioskRowAction(
                semanticLabel: 'Remove $name',
                icon: Symbols.delete_sharp,
                onTap: onRemove,
              ),
          ],
        ),
        KioskConsentCheck(
          value: person.training,
          onChanged: onTrainingChanged,
          label: _checkLabel,
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
