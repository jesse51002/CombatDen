import 'package:flutter/material.dart';
import 'package:crm/core/constants/design_constants.dart';

/// Loading screen shown while checking authentication
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Center(
        child: CircularProgressIndicator(
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}
