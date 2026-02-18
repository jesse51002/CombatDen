import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';

/// Placeholder home screen - will be replaced with actual CRM features
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        // When logged out, navigate back to LoginScreen
        if (state is LoginUnauthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
      child: Scaffold(
        backgroundColor: DesignConstants.background,
        appBar: AppBar(
          backgroundColor: DesignConstants.cardBackground,
          title: Text(
            'CRM Home',
            style: DesignConstants.h2.copyWith(color: DesignConstants.text),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: DesignConstants.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome!',
                  style: DesignConstants.h1.copyWith(color: DesignConstants.text),
                ),
                const SizedBox(height: 16),
                Text(
                  'Logged in as: ${user?.email ?? "Unknown"}',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    context.read<LoginBloc>().add(const LoginSignOutRequested());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignConstants.badRed,
                    foregroundColor: DesignConstants.text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        DesignConstants.radiusBig,
                      ),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style: DesignConstants.h2.copyWith(
                      color: DesignConstants.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
