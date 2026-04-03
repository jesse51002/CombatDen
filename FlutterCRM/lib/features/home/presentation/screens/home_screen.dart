import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';
import 'package:crm/features/gym_setup/presentation/screens/gym_setup_screen.dart';
import 'package:crm/features/members_list/presentation/screens/members_list_screen.dart';

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

      if (!mounted) return;
      final gymId = employee['gym_id'] as String;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              MembersListScreen(gymId: gymId),
        ),
      );
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
                          Symbols.logout_sharp,
                          color: DesignConstants.text
                              .withValues(alpha: 0.7),
                          size: 18,
                          weight: DesignConstants.iconWeight,
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
          : const SizedBox.shrink(),
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
                      Symbols.error_sharp,
                      size: 64,
                      color: DesignConstants.badRed,
                      weight: DesignConstants.iconWeight,
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
                  Symbols.logout_sharp,
                  color: DesignConstants.text
                      .withValues(alpha: 0.7),
                  size: 18,
                  weight: DesignConstants.iconWeight,
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
