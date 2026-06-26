import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/register_screen.dart';
import 'package:crm/features/login/presentation/widgets/auth_header.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Sign-in form card. Driven by [LoginBloc] from context.
///
/// Validates email + password locally before dispatching
/// [LoginSignInRequested]. Inline [ErrorMessage] shows
/// [LoginError.message] when [LoginError.isLoginError] is true.
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

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusBig,
              ),
              boxShadow: DesignConstants.cardShadow,
              border: Border.all(color: DesignConstants.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(DesignConstants.paddingBig),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingBig,
                  children: [
                    const AuthHeader(
                      title: 'Welcome back',
                      subtitle: 'Sign in to your gym account',
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DesignConstants.spacingLarge,
                      children: [
                        if (errorMessage != null)
                          ErrorMessage(message: errorMessage),
                        CustomTextField(
                          controller: _emailController,
                          label: 'Email',
                          hintText: 'you@yourgym.com',
                          enabled: !isLoading,
                          validator: Validators.validateEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onSubmitted: () => _passwordFocus.requestFocus(),
                        ),
                        CustomTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hintText: 'Enter your password',
                          isPassword: true,
                          enabled: !isLoading,
                          focusNode: _passwordFocus,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _submit,
                          validator: (v) => (v?.isEmpty ?? true)
                              ? 'Password is required'
                              : null,
                        ),
                        AppPrimaryButton(
                          text: 'Sign In',
                          onPressed: _submit,
                          isLoading: isLoading,
                          fullWidth: true,
                        ),
                      ],
                    ),
                    _RegisterLink(isLoading: isLoading),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RegisterLink extends StatelessWidget {
  final bool isLoading;

  const _RegisterLink({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          "Don't have an account?",
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        GestureDetector(
          onTap: isLoading
              ? null
              : () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterScreen(),
                    ),
                  ),
          child: Text(
            'Sign up',
            style: DesignConstants.pSemibold.copyWith(
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
