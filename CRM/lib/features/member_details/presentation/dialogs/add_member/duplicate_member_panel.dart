import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/shared/widgets/member_avatar.dart';

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
        const _WarnCallout(),
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

class _WarnCallout extends StatelessWidget {
  const _WarnCallout();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.okYellow.withValues(alpha: 0.12),
        borderRadius:
            BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.okYellow),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.warning_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeMedium,
            color: DesignConstants.okYellow,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  'This member may already exist',
                  style: DesignConstants.pSemibold,
                ),
                Text(
                  'Someone with the same name and email is already '
                  'in this gym. Use the existing record instead of '
                  'creating a duplicate.',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final card = Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius:
            BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: highlight
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          MemberAvatar(
            name: match.fullName,
            photoUrl: match.photoUrl,
            size: DesignConstants.rankBeltSmall,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(match.fullName, style: DesignConstants.h3),
                if (match.email != null && match.email!.isNotEmpty)
                  Text(
                    match.email!,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const _ExistingPill(),
        ],
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

/// A soft accent pill marking the row as an already-existing member.
class _ExistingPill extends StatelessWidget {
  const _ExistingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.primaryColor),
      ),
      child: Text(
        'Existing member',
        style: DesignConstants.pSmallBold.copyWith(
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}
