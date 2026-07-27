import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/my_rewards_body.dart';

/// Rewards tab landing — "My Rewards". The member's own redemption history;
/// provides a fresh [RewardsBloc] each entry (refetch-on-tab-focus). The
/// per-member chrome (streak / points) reads the app-wide MemberProfileBloc.
class MyRewardsScreen extends StatelessWidget {
  const MyRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RewardsBloc>(
      create: (_) => RewardsBloc(
        repository: MemberRewardsRepository(apiClient: ApiClient()),
      )..add(const RewardsLoadRequested()),
      child: const MyRewardsBody(),
    );
  }
}
