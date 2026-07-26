import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/core/utils/number_format.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

// Bundled fallback assets for the theme-driven logo / rank belt.
const String _kDefaultLogoAsset = 'gym_logo_global_mma.png';
const String _kDefaultRankBadgeAsset = 'icon_rank_belt.png';

/// The class-detail topbar (name-only, back button). In the app it reads the
/// shared [MemberProfileBloc] for the live streak / points; the capture harness
/// renders it standalone ([live] false), where no profile bloc is provided.
class ClassDetailTopbar extends StatelessWidget {
  const ClassDetailTopbar({super.key, required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    if (!live) return _bar(streak: 0, points: '—');
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final retention = state.profile?.retention;
        return _bar(
          streak: retention?.classStreakWeeks ?? 0,
          points:
              retention != null ? formatCount(retention.pointsBalance) : '—',
          rankImageUrl: state.profile?.rank?.imageUrl,
        );
      },
    );
  }

  Widget _bar({
    required int streak,
    required String points,
    String? rankImageUrl,
  }) {
    return AppTopbar(
      mode: AppTopbarMode.nameOnly,
      showBackButton: true,
      gymName: selectedMember.gymName ?? '',
      memberName: selectedMember.fullName,
      memberPhotoUrl: selectedMember.photoUrl,
      memberFirstName: selectedMember.firstName,
      memberLastName: selectedMember.lastName,
      logoAsset: _kDefaultLogoAsset,
      streakDays: streak,
      pointsLabel: points,
      rankBadgeAsset: _kDefaultRankBadgeAsset,
      rankImageUrl: rankImageUrl,
      showRank: selectedMember.gymRankEnabled,
      pointsSpendable: selectedMember.gymHasRewards,
    );
  }
}
