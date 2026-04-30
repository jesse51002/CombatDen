import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/presentation/widgets/home_body/home_booked_body.dart';
import 'package:mobile_app/features/home/presentation/widgets/home_body/home_not_booked_body.dart';
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
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.home),
      child: PageView(
        controller: _pageController,
        children: const [HomeNotBookedBody(), HomeBookedBody()],
      ),
    );
  }
}
