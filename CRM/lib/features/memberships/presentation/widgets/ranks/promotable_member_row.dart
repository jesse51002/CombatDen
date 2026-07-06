import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_ladder_position.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_leaf_progression.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_progress_bar.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// One promotable member, rendered identically wherever staff act on a
/// member's rank: their belt, avatar, name, a **current → next**
/// progression label, the shared [RankProgressBar], and a single
/// **Promote** button (green once eligible) that opens the full
/// promotion dialog.
///
/// Deliberately **bloc-agnostic** — it takes the row's display fields,
/// the gym ladder + sub-rank type, and the member's current leaf, then
/// derives the current → next label itself (via [RankLadderPosition], the
/// same resolver the [PromotionDialog] uses) so both the ready-to-promote
/// board ([ReadyToPromoteRow]) and the rank-detail roster share the exact
/// same row. The single [onPromote] callback opens the dialog; there is
/// no quick one-tap path. Eligibility (whether [classesSince] has met
/// [stepDenominator]) is derived here so the Promote affordance and the
/// bar read the same on both.
class PromotableMemberRow extends StatelessWidget {
  /// The belt art for this member's current leaf (already resolved by
  /// the caller — a per-sub override or the main rank's image). Null /
  /// empty renders the neutral belt placeholder.
  final String? imageUrl;

  /// The member's photo, or null for an initials avatar.
  final String? avatarUrl;

  final String name;

  /// The gym's ladder, in order — used to resolve the next leaf.
  final List<MainRank> ladder;

  /// The gym's sub-rank type (drives the derived sub-position labels).
  final RankSubType subRankType;

  /// The member's current MAIN rank id (both surfaces show ranked
  /// members, so this is non-null here).
  final String mainRankId;

  /// The member's current leaf within that rank, or null when the rank
  /// has no sub-positions.
  final int? currentSubIndex;

  /// Classes attended since the member's last rank change.
  final int classesSince;

  /// Classes needed to reach the next leaf, or null at the top.
  final int? stepDenominator;

  /// Open the full promotion dialog (the row's only affordance).
  final VoidCallback onPromote;

  const PromotableMemberRow({
    super.key,
    required this.imageUrl,
    required this.avatarUrl,
    required this.name,
    required this.ladder,
    required this.subRankType,
    required this.mainRankId,
    required this.currentSubIndex,
    required this.classesSince,
    required this.stepDenominator,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final denom = stepDenominator;
    final eligible = denom != null && denom > 0 && classesSince >= denom;

    final position = RankLadderPosition(
      ladder: ladder,
      subRankType: subRankType,
      currentMainRankId: mainRankId,
      currentSubIndex: currentSubIndex,
    );
    final currentLeaf = position.currentLeaf;
    final nextLeaf = position.nextLeaf;
    final currentLabel = currentLeaf == null
        ? name
        : position.leafLabel(currentLeaf, showBase: true);
    final nextLabel = nextLeaf == null
        ? null
        : position.leafLabel(nextLeaf, showBase: true);

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
                      child: Text(
                        name,
                        style: DesignConstants.pSemibold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Where they are now → where a Promote lands them; the
                // destination reads as the emphasized token.
                RankLeafProgression(
                  currentLabel: currentLabel,
                  nextLabel: nextLabel,
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
            onPressed: onPromote,
          ),
        ],
      ),
    );
  }
}
