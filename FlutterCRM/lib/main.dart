import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/config/environment.dart';
import 'package:crm/core/config/supabase_config.dart';
import 'package:crm/core/constants/app_theme.dart';
import 'package:crm/core/constants/env_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/home/presentation/screens/home_screen.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/data/repositories/auth_repository.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/shared/widgets/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.initialize();
    debugPrint('Supabase initialized successfully');
  } catch (e, stackTrace) {
    // Log error but continue - app might work in offline mode
    debugPrint('Supabase initialization failed: $e');
    debugPrint('Stack trace: $stackTrace');
  }

  try {
    Stripe.publishableKey = EnvironmentConfig.get(
      EnvConstants.stripePublishable,
    );
    await Stripe.instance.applySettings();
    debugPrint('Stripe initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('Stripe initialization failed: $e');
    debugPrint('Stack trace: $stackTrace');
  }

  runApp(const MyApp());
}

/// Main application widget with Bloc-based auth routing
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = LoginBloc(
          authRepository: AuthRepository(),
        );
        ApiClient.onUnauthorized = () => bloc.add(
              const LoginSignOutRequested(),
            );
        return bloc;
      },
      child: MaterialApp(
        title: 'CombatDen',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const AuthGate(),
      ),
    );
  }
}

/// Widget that handles routing based on authentication state
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) {
        // Loading initial auth check
        if (state is LoginInitial || state is LoginLoading) {
          return const LoadingScreen();
        }

        // Logged in - show HomeScreen
        if (state is LoginAuthenticated) {
          return const HomeScreen();
        }

        // Not logged in - show LoginScreen
        return const LoginScreen();
      },
    );
  }
}
