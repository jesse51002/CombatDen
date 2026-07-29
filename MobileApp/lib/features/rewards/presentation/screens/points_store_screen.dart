import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_store_body.dart';

/// Points store — the gym's ACTIVE reward catalog the member can redeem with
/// earned points. Provides a fresh [RewardsBloc] each time the tab is entered
/// (the refetch-on-tab-focus rule); the per-member chrome + points balance
/// read the app-wide MemberProfileBloc provided above the shell.
class PointsStoreScreen extends StatelessWidget {
  const PointsStoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RewardsBloc>(
      create: (_) => RewardsBloc(
        repository: MemberRewardsRepository(apiClient: ApiClient()),
      )..add(const RewardsLoadRequested()),
      child: const PointsStoreBody(),
    );
  }
}
