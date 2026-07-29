import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/presentation/widgets/home_body/home_body.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // No gym picked yet → the gym-select screen is the real entry point. (After
    // a pick the gym is set and this never fires; the theme re-key rebuilds
    // Home with the chosen gym.)
    if (selectedGym.gymId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.styleSelect);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While redirecting to the gym-select (no gym yet), render nothing.
    if (selectedGym.gymId == null) return const SizedBox.shrink();
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.home),
      child: PageView(
        controller: _pageController,
        children: const [
          HomeBody(booked: false),
          HomeBody(booked: true),
        ],
      ),
    );
  }
}
