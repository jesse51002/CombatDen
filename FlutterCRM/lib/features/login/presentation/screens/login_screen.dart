import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/presentation/widgets/login_form.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/home/presentation/screens/home_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        // When authenticated, push replacement to HomeScreen
        if (state is LoginAuthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      },
      child: Scaffold(
        backgroundColor: DesignConstants.backgroundColor,
        body: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(DesignConstants.screenHorizontalPadding),
            child: const LoginForm(),
          ),
        ),
      ),
    );
  }
}
