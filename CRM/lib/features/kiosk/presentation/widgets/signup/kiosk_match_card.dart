import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// The E2 offer: what was typed, and the ONE existing member it may be.
///
/// It is `add_member/duplicate_member_panel.dart`'s match row at kiosk scale
/// with the desk's warning callout deliberately dropped — at the desk a
/// duplicate is a mistake to warn about; here it is the good outcome being
/// confirmed.
///
/// The full name (a first name plus an initial collides silently) and a MASKED
/// email are the only disambiguators — never a phone, never a membership
/// status: nobody at a shared lobby iPad may read a stranger's details off it.
class KioskMatchCard extends StatelessWidget {
  /// The typed draft this offer answers. Null on the search route, where
  /// nothing was typed to compare against.
  final KioskSignupPerson? typed;

  final KioskSignupMatch match;

  const KioskMatchCard({super.key, required this.match, this.typed});

  @override
  Widget build(BuildContext context) {
    final draft = typed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (draft != null)
          _TypedBox(
            name: '${draft.firstName} ${draft.lastName}'.trim(),
            email: kioskMaskedEmail(draft.email),
          ),
        _MatchRow(match: match),
      ],
    );
  }
}

/// "You typed" — the half of the comparison the parent owns.
class _TypedBox extends StatelessWidget {
  final String name;
  final String? email;

  const _TypedBox({required this.name, this.email});

  @override
  Widget build(BuildContext context) {
    final masked = email;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text('YOU TYPED', style: DesignConstants.kioskEyebrow),
                Text(
                  name,
                  style: DesignConstants.kioskName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (masked != null)
            Text(
              masked,
              style: DesignConstants.kioskMonoValue.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
        ],
      ),
    );
  }
}

/// The gym's own record — the thing being confirmed.
class _MatchRow extends StatelessWidget {
  final KioskSignupMatch match;

  const _MatchRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final masked = kioskMaskedEmail(match.email);
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.primaryColor),
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          InstructorAvatar(
            name: match.fullName,
            diameter: DesignConstants.iconSizeBig,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(
                  match.fullName,
                  style: DesignConstants.kioskName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (masked != null)
                  Text(
                    masked,
                    style: DesignConstants.kioskCaption.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Symbols.check_circle_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.primaryColor,
          ),
        ],
      ),
    );
  }
}
