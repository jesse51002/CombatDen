import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/shared/widgets/existing_member_pill.dart';
import 'package:crm/shared/widgets/member_identity_card.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// The duplicate-review body shared by the add-member flow and the in-run
/// new-member dialog: a warning callout, the matched member card(s), and a
/// helper line. When more than one match exists each card is tappable so the
/// host knows which existing member "Use existing member" targets.
class DuplicateMemberPanel extends StatelessWidget {
  final List<DuplicateMemberMatch> matches;

  /// The currently-selected match id (defaults to the first). Only meaningful
  /// with more than one match; a single match is implicitly selected.
  final String selectedMatchId;
  final ValueChanged<String> onSelect;

  const DuplicateMemberPanel({
    super.key,
    required this.matches,
    required this.selectedMatchId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final multiple = matches.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        const WarningMessage(
          title: 'This member may already exist',
          message: 'Someone with the same name and email is already '
              'in this gym. Use the existing record instead of '
              'creating a duplicate.',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            for (final m in matches)
              _MatchCard(
                match: m,
                selectable: multiple,
                selected: m.memberId == selectedMatchId,
                onTap: () => onSelect(m.memberId),
              ),
          ],
        ),
        Text(
          'Create a separate record only if this is genuinely a '
          'different person.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  final DuplicateMemberMatch match;
  final bool selectable;
  final bool selected;
  final VoidCallback onTap;

  const _MatchCard({
    required this.match,
    required this.selectable,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = selectable && selected;
    final card = MemberIdentityCard(
      name: match.fullName,
      email: match.email,
      photoUrl: match.photoUrl,
      trailing: const ExistingMemberPill(),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius:
            BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: highlight
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
          width: highlight
              ? DesignConstants.buttonBorder
              : DesignConstants.dividerThickness,
        ),
      ),
    );
    if (!selectable) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: card,
    );
  }
}
