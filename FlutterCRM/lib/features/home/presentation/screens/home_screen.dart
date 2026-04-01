import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';
import 'package:crm/features/gym_setup/presentation/screens/gym_setup_screen.dart';
import 'package:crm/shared/widgets/app_shell.dart';

/// Home screen that checks gym setup status on load
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCheckingSetup = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGymSetup();
    });
  }

  Future<void> _checkGymSetup() async {
    final userId = Supabase
        .instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final gymRepo = GymRepository();
      final employee =
          await gymRepo.getOwnerEmployee(userId);

      if (employee == null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const GymSetupScreen(),
          ),
        );
        return;
      }

      if (mounted) {
        setState(() => _isCheckingSetup = false);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingSetup = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user =
        Supabase.instance.client.auth.currentUser;

    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        if (state is LoginUnauthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const LoginScreen(),
            ),
          );
        }
      },
      child: _errorMessage != null
          ? _buildErrorView(context)
          : _isCheckingSetup
          ? Scaffold(
              backgroundColor:
                  DesignConstants.backgroundColor,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: CircularProgressIndicator(
                        color:
                            DesignConstants.primaryColor,
                      ),
                    ),
                    Positioned(
                      top: DesignConstants.spacingMedium,
                      right: DesignConstants.spacingMedium,
                      child: TextButton.icon(
                        onPressed: () {
                          context.read<LoginBloc>().add(
                                const LoginSignOutRequested(),
                              );
                        },
                        icon: Icon(
                          Icons.logout,
                          color: DesignConstants.text
                              .withValues(alpha: 0.7),
                          size: 18,
                        ),
                        label: Text(
                          'Logout',
                          style:
                              DesignConstants.p.copyWith(
                            color: DesignConstants.text
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : AppShell(
        activeRoute: 'dashboard',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 80,
                color: DesignConstants.primaryColor,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome!',
                style: DesignConstants.h1,
              ),
              const SizedBox(height: 16),
              Text(
                'Logged in as:'
                ' ${user?.email ?? "Unknown"}',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  context.read<LoginBloc>().add(
                        const LoginSignOutRequested(),
                      );
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
                  style: DesignConstants.h2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: DesignConstants
                      .screenHorizontalPadding,
                ),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: DesignConstants.badRed,
                    ),
                    SizedBox(
                      height:
                          DesignConstants.spacingLarge,
                    ),
                    Text(
                      'Something went wrong',
                      style: DesignConstants.h2,
                    ),
                    SizedBox(
                      height:
                          DesignConstants.spacingMedium,
                    ),
                    Text(
                      _errorMessage!,
                      style:
                          DesignConstants.p.copyWith(
                        color: DesignConstants.text
                            .withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(
                      height:
                          DesignConstants.spacingBig,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isCheckingSetup = true;
                          _errorMessage = null;
                        });
                        _checkGymSetup();
                      },
                      child: Text(
                        'Retry',
                        style:
                            DesignConstants.p.copyWith(
                          color: DesignConstants
                              .primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: TextButton.icon(
                onPressed: () {
                  context.read<LoginBloc>().add(
                        const LoginSignOutRequested(),
                      );
                },
                icon: Icon(
                  Icons.logout,
                  color: DesignConstants.text
                      .withValues(alpha: 0.7),
                  size: 18,
                ),
                label: Text(
                  'Logout',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
