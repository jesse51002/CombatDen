import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_consent_check.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_row_action.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// One person on the signup roster: who they are, whether they are getting a
/// membership, and how to correct or remove them.
///
/// STACKED, not one line: the membership check decides whether this person is
/// charged, so it gets a line of its own rather than a 15px label competing
/// with an avatar, a pill and two icon buttons at arm's length on an iPad.
///
/// The check is on EVERY row and defaults ON — payer, payee, created here or
/// matched — and unchecking everybody is a legitimate registration-only signup
/// rather than an error. Edit appears only for a person this signup CREATED:
/// the kiosk prints no stored detail of an existing member on a shared screen,
/// so offering to edit fields it refuses to show would lie about what it opens.
/// Remove ASKS first, and is offered only while removal is still free — there
/// is no unlink call, so it goes away once this person's link or signature
/// commits rather than becoming a button that cannot do what it says.
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
  /// means something beside somebody else, so a roster of one drops it.
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
            // nobody's business at a glance on a shared iPad.
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

/// The name over its one quiet second line: the person's address, MASKED
/// through [kioskMaskedEmail] — no screen in this lane prints one in full.
///
/// The roster is the screen a queue reads over the member's shoulder, and it
/// lists an adopted existing member whose address came from the gym's records
/// rather than from anyone standing there, so the line says enough to recognise
/// and never enough to copy.
class _Identity extends StatelessWidget {
  final String name;
  final KioskSignupPerson person;

  const _Identity({required this.name, required this.person});

  @override
  Widget build(BuildContext context) {
    // Null before their details step has run — hence "Added just now".
    final masked = kioskMaskedEmail(person.email);
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
          masked ?? 'Added just now',
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
