import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/core/utils/number_format.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

// Bundled fallback assets for the topbar's theme-driven logo / rank belt (used
// only when the loaded customization has no image for the slot).
const String _kDefaultLogoAsset = 'gym_logo_global_mma.png';
const String _kDefaultRankBadgeAsset = 'icon_rank_belt.png';

/// The profile screen's topbar (name-only variant): the gym name from the
/// selected member, the streak / points read LIVE from the shared
/// [MemberProfileBloc]. Tapping the identity block switches profile — the same
/// per-member chrome the home + rewards topbars render, never mock.
class ProfileTopbar extends StatelessWidget {
  const ProfileTopbar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final retention = state.profile?.retention;
        return AppTopbar(
          mode: AppTopbarMode.nameOnly,
          showBackButton: false,
          gymName: selectedMember.gymName ?? '',
          memberName: selectedMember.fullName,
          memberPhotoUrl: selectedMember.photoUrl,
          memberFirstName: selectedMember.firstName,
          memberLastName: selectedMember.lastName,
          logoAsset: _kDefaultLogoAsset,
          streakDays: retention?.classStreakWeeks ?? 0,
          pointsLabel:
              retention != null ? formatCount(retention.pointsBalance) : '—',
          rankBadgeAsset: _kDefaultRankBadgeAsset,
          rankImageUrl: state.profile?.rank?.imageUrl,
          onTitleDoubleTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.memberSelect),
        );
      },
    );
  }
}
