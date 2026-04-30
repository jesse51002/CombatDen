import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';

void main() => runApp(const MobileAppRoot());

class MobileAppRoot extends StatelessWidget {
  const MobileAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CombatDen',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
