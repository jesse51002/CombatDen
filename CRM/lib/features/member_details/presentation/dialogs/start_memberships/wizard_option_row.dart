import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// One full-width option: a leading glyph, a name over one quiet line of what
/// choosing it MEANS, and a trailing mark.
///
/// The desk's answer to a row of radio buttons. It carries the consequence on
/// the row itself rather than in a paragraph above the list, because the two
/// adders on the `who` step are mirror images of each other — "authorize the
/// payer for them" and "authorize them as the payer" — and the old wizard put
/// both on one screen with identical copy pointing in opposite directions.
///
/// [selected] paints the picked state; a row that NAVIGATES rather than picks
/// leaves it false and passes [opensMore], which swaps the trailing tick for
/// a chevron.
class WizardOptionRow extends StatelessWidget {
  final IconData icon;
  final String title;

  /// The one quiet line under [title] — what choosing this does.
  final String? meta;

  final bool selected;

  /// This row opens something rather than answering the question.
  final bool opensMore;

  /// Null renders the row inert (an option that is already the answer).
  final VoidCallback? onTap;

  const WizardOptionRow({
    super.key,
    required this.icon,
    required this.title,
    this.meta,
    this.selected = false,
    this.opensMore = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final line = meta;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.spacingMedium),
          decoration: BoxDecoration(
            color: selected ? DesignConstants.primaryColor10 : null,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            border: Border.all(
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.line,
            ),
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                icon,
                size: DesignConstants.iconSizeLarge,
                weight: DesignConstants.iconWeight,
                color: selected
                    ? DesignConstants.primaryColor
                    : DesignConstants.text2nd,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    Text(
                      title,
                      style: scale.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (line != null)
                      Text(
                        line,
                        style: scale.caption.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
                  ],
                ),
              ),
              _Mark(selected: selected, opensMore: opensMore),
            ],
          ),
        ),
      ),
    );
  }
}

/// The trailing mark: a tick on the chosen option, a chevron on a row that
/// opens something, and nothing at all on an unpicked option — a grey tick
/// that is always there teaches nothing about which row is chosen.
class _Mark extends StatelessWidget {
  final bool selected;
  final bool opensMore;

  const _Mark({required this.selected, required this.opensMore});

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Icon(
        Symbols.check_sharp,
        size: DesignConstants.iconSizeSmall,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
      );
    }
    if (!opensMore) return const SizedBox.shrink();
    return Icon(
      Symbols.chevron_right_sharp,
      size: DesignConstants.iconSizeSmall,
      weight: DesignConstants.iconWeight,
      color: DesignConstants.text2nd,
    );
  }
}
