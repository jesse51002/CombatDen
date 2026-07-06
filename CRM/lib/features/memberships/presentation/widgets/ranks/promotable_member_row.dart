import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_progress_bar.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// One promotable member, rendered identically wherever staff act on a
/// member's rank: their belt, avatar, name, a rank/sub label, the shared
/// [RankProgressBar], a one-tap **Promote** (green once eligible), and an
/// overflow that opens the full promotion dialog.
///
/// Deliberately **bloc-agnostic** — it takes the row's display fields and
/// an [onQuickPromote] / [onOpenDialog] callback pair, so both the
/// ready-to-promote board ([ReadyToPromoteRow]) and the rank-detail
/// roster share the exact same row without either owning the other's
/// bloc. Eligibility (whether [classesSince] has met [stepDenominator])
/// is derived here so the Promote affordance reads the same on both.
class PromotableMemberRow extends StatelessWidget {
  /// The belt art for this member's current leaf (already resolved by
  /// the caller — a per-sub override or the main rank's image). Null /
  /// empty renders the neutral belt placeholder.
  final String? imageUrl;

  /// The member's photo, or null for an initials avatar.
  final String? avatarUrl;

  final String name;

  /// The trailing rank/sub label, e.g. "White · 1 Stripe" on the board
  /// (where rows span ranks) or just "1 Stripe" / "Base" on a single
  /// rank's roster. Null / empty hides the label (a sub-less gym).
  final String? rankLabel;

  /// Classes attended since the member's last rank change.
  final int classesSince;

  /// Classes needed to reach the next leaf, or null at the top.
  final int? stepDenominator;

  /// Advance the member one leaf (the quick Promote action).
  final VoidCallback onQuickPromote;

  /// Open the full promotion dialog (the overflow action).
  final VoidCallback onOpenDialog;

  const PromotableMemberRow({
    super.key,
    required this.imageUrl,
    required this.avatarUrl,
    required this.name,
    required this.rankLabel,
    required this.classesSince,
    required this.stepDenominator,
    required this.onQuickPromote,
    required this.onOpenDialog,
  });

  @override
  Widget build(BuildContext context) {
    final denom = stepDenominator;
    final eligible = denom != null && denom > 0 && classesSince >= denom;
    final label = rankLabel;
    final hasLabel = label != null && label.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          RankBeltImage(imageUrl: imageUrl, size: 48),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Row(
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    InstructorAvatar(
                      photoUrl: avatarUrl,
                      name: name,
                      diameter: 24,
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        name,
                        style: DesignConstants.pSemibold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // The member's current belt + position — a legible
                    // label so their rank reads at a glance. Flexible so
                    // a long "White · 4 Stripes" ellipsizes instead of
                    // overflowing.
                    if (hasLabel)
                      Flexible(
                        flex: 2,
                        child: Text(
                          label,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignConstants.h3,
                        ),
                      ),
                  ],
                ),
                RankProgressBar(
                  done: classesSince,
                  target: denom,
                  eligible: eligible,
                ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'Promote',
            borderRadius: DesignConstants.radiusSmall,
            borderColor:
                eligible ? DesignConstants.goodGreen : DesignConstants.text,
            textStyle: DesignConstants.h3.copyWith(
              color:
                  eligible ? DesignConstants.goodGreen : DesignConstants.text,
            ),
            onPressed: onQuickPromote,
          ),
          IconButton(
            tooltip: 'More options',
            onPressed: onOpenDialog,
            icon: Icon(
              Symbols.more_vert_sharp,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ],
      ),
    );
  }
}
