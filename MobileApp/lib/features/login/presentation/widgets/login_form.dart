import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/utils/validators.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/bloc/login_state.dart';
import 'package:mobile_app/features/login/presentation/screens/register_screen.dart';
import 'package:mobile_app/features/login/presentation/widgets/auth_header.dart';
import 'package:mobile_app/shared/widgets/app_text_field.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/error_message.dart';

/// Sign-in form. Driven by [LoginBloc] from context. Validates locally, then
/// dispatches [LoginSignInRequested]; an inline [ErrorMessage] shows a
/// [LoginError] when it is a sign-in error.
class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<LoginBloc>().add(
      LoginSignInRequested(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) {
        final isLoading = state is LoginLoading;
        final errorMessage = (state is LoginError && state.isLoginError)
            ? state.message
            : null;

        return Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingBig,
            children: [
              const AuthHeader(
                title: 'Welcome back',
                subtitle: 'Sign in to your membership',
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  if (errorMessage != null) ErrorMessage(message: errorMessage),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hintText: 'you@email.com',
                    enabled: !isLoading,
                    validator: Validators.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: () => _passwordFocus.requestFocus(),
                  ),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hintText: 'Enter your password',
                    isPassword: true,
                    enabled: !isLoading,
                    focusNode: _passwordFocus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _submit,
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Password is required' : null,
                  ),
                  AppPrimaryButton(
                    text: isLoading ? 'Signing in…' : 'Sign In',
                    onPressed: isLoading ? null : _submit,
                    fullWidth: true,
                  ),
                ],
              ),
              _RegisterLink(isLoading: isLoading),
            ],
          ),
        );
      },
    );
  }
}

/// "Don't have an account? Sign up" — pushes the register screen onto the
/// unauthenticated flow's nested navigator.
class _RegisterLink extends StatelessWidget {
  const _RegisterLink({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          "Don't have an account?",
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        GestureDetector(
          onTap: isLoading
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterScreen(),
                    ),
                  ),
          child: Text(
            'Sign up',
            style: DesignConstants.h3.copyWith(
              color: isLoading
                  ? DesignConstants.primaryColor.withValues(alpha: 0.5)
                  : DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
