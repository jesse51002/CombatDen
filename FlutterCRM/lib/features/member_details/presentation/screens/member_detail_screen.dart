import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/back_button_row.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/membership_carousel.dart';
import 'package:crm/features/member_details/presentation/widgets/personal_info_card.dart';
import 'package:crm/features/member_details/presentation/widgets/profile_header/profile_header_section.dart';
import 'package:crm/features/member_details/presentation/widgets/rank_retention/retention_card.dart';
import 'package:crm/features/member_details/presentation/widgets/responsive_grid.dart';
import 'package:crm/features/member_details/presentation/widgets/right_member_sidebar.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';

/// The Specific Member Detail screen.
///
/// Displays full member profile with personal info,
/// membership carousel, retention, payments,
/// and rewards.
class MemberDetailScreen extends StatelessWidget {
  final String crmUserId;

  const MemberDetailScreen({
    super.key,
    required this.crmUserId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MemberDetailBloc(
        repository: MemberRepository(
          apiClient: ApiClient(),
          supabase: Supabase.instance.client,
        ),
      )..add(MemberDetailRequested(crmUserId)),
      child: const _MemberDetailView(),
    );
  }
}

class _MemberDetailView extends StatelessWidget {
  const _MemberDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberDetailBloc,
        MemberDetailState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >=
                AppConstants.breakpointDesktop;

            return AppShell(
              activeRoute: 'members',
              rightBar: _rightBar(
                context,
                state,
                isDesktop,
              ),
              child: _mainContent(context, state),
            );
          },
        );
      },
    );
  }

  Widget? _rightBar(
    BuildContext context,
    MemberDetailState state,
    bool isDesktop,
  ) {
    if (!isDesktop || state is! MemberDetailLoaded) {
      return null;
    }

    return RightMemberSidebar(
      members: state.filteredMembers,
      onSearchChanged: (query) => context
          .read<MemberDetailBloc>()
          .add(MemberSearchChanged(query)),
      onMemberTap: (id) =>
          _navigateToMember(context, id),
    );
  }

  Widget _mainContent(
    BuildContext context,
    MemberDetailState state,
  ) {
    if (state is MemberDetailLoading ||
        state is MemberDetailInitial) {
      return const Center(
        child: CircularProgressIndicator(
          color: DesignConstants.primaryColor,
        ),
      );
    }

    if (state is MemberDetailError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              'Failed to load member',
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
            Text(
              state.message,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
            AppOutlineButton(
              text: 'Retry',
              onPressed: () {
                context.read<MemberDetailBloc>().add(
                      MemberDetailRequested(
                        state.crmUserId,
                      ),
                    );
              },
            ),
          ],
        ),
      );
    }

    if (state is MemberDetailLoaded) {
      return _loadedContent(context, state);
    }

    return const SizedBox.shrink();
  }

  Widget _loadedContent(
    BuildContext context,
    MemberDetailLoaded state,
  ) {
    final member = state.member;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal:
            DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.paddingBig,
      ),
      child: Column(
        spacing: DesignConstants.spacingBig,
        children: [
          const BackButtonRow(),
          ProfileHeaderSection(
            member: member,
            onLinkedAccountTap: (id) =>
                _navigateToMember(context, id),
          ),
          ResponsiveGrid(
            personalInfoCard: PersonalInfoCard(
              personalInfo: member.personalInfo,
            ),
            retentionCard: RetentionCard(
              retention: member.retention,
              rewards: member.recentlyRedeemedRewards,
            ),
            membershipCard: MembershipCarousel(
              memberships: member.memberships,
              currentIndex:
                  state.currentMembershipIndex,
              onPageChanged: (index) => context
                  .read<MemberDetailBloc>()
                  .add(
                    MembershipPageChanged(index),
                  ),
              onLinkedAccountTap: (id) =>
                  _navigateToMember(context, id),
              payments: member.paymentHistory,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToMember(
    BuildContext context,
    String crmUserId,
  ) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MemberDetailScreen(
          crmUserId: crmUserId,
        ),
      ),
    );
  }
}
