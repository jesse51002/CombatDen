import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/home/bloc/home_bloc.dart';
import 'package:mobile_app/features/home/bloc/home_event.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/home/data/repositories/member_classes_repository.dart';
import 'package:mobile_app/features/home/presentation/widgets/home_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// The home tab: the member's gym schedule board joined with their open
/// reservations. Provides the [HomeBloc] fresh each time the tab is entered
/// (the nav pushes a new route), so returning to Home re-loads — the
/// refetch-on-tab-focus rule.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient();
    return BlocProvider<HomeBloc>(
      create: (_) => HomeBloc(
        classesRepository: MemberClassesRepository(apiClient: apiClient),
        historyRepository: MemberClassHistoryRepository(apiClient: apiClient),
      )..add(const HomeLoadRequested()),
      child: const AppScreenScaffold(
        horizontalPadding: AppScreenHorizontalPadding.none,
        bottomNav: AppBottomNavBar(selected: AppBottomNavTab.home),
        child: HomeBody(),
      ),
    );
  }
}
