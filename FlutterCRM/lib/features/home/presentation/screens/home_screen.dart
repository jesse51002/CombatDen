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

/// Home screen that checks gym setup status on load
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCheckingSetup = true;

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

    final gymRepo = GymRepository();
    final gym = await gymRepo.getGymByOwnerId(userId);

    if (gym == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const GymSetupScreen(),
        ),
      );
      return;
    }

    final gymId = gym['gym_id'] as String;
    final profile = await gymRepo.getUserGymProfile(
      userId: userId,
      gymId: gymId,
    );

    if (profile == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const GymSetupScreen(),
        ),
      );
      return;
    }

    if (mounted) {
      setState(() => _isCheckingSetup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user =
        Supabase.instance.client.auth.currentUser;

    if (_isCheckingSetup) {
      return Scaffold(
        backgroundColor: DesignConstants.background,
        body: Center(
          child: CircularProgressIndicator(
            color: DesignConstants.primary,
          ),
        ),
      );
    }

    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        if (state is LoginUnauthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: DesignConstants.background,
        appBar: AppBar(
          backgroundColor:
              DesignConstants.cardBackground,
          title: Text(
            'CRM Home',
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.symmetric(
            horizontal:
                DesignConstants.screenHorizontalPadding,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: DesignConstants.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome!',
                  style: DesignConstants.h1.copyWith(
                    color: DesignConstants.text,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Logged in as:'
                  ' ${user?.email ?? "Unknown"}',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text
                        .withValues(alpha: 0.7),
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
                    backgroundColor:
                        DesignConstants.badRed,
                    foregroundColor:
                        DesignConstants.text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        DesignConstants.radiusBig,
                      ),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style:
                        DesignConstants.h2.copyWith(
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
