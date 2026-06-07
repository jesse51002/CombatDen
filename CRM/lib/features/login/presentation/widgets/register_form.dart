import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/features/login/presentation/widgets/auth_header.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Registration form card. Driven by [LoginBloc] from context.
///
/// On [LoginRegistrationSuccess] the form is replaced by a
/// confirm-email prompt with a link back to sign-in.
/// If the backend immediately authenticates on sign-up, the
/// [AuthGate] handles the [LoginAuthenticated] transition
/// before this prompt is ever shown.
class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<LoginBloc>().add(
      LoginSignUpRequested(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) {
        if (state is LoginRegistrationSuccess) {
          return _ConfirmEmailCard(
            email: _emailController.text.trim(),
          );
        }

        final isLoading = state is LoginLoading;
        final errorMessage = (state is LoginError && !state.isLoginError)
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
                      title: 'Create account',
                      subtitle: 'Start managing your gym',
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
                        ),
                        CustomTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hintText: 'At least 8 characters, letter + number',
                          isPassword: true,
                          enabled: !isLoading,
                          validator: Validators.validatePassword,
                        ),
                        CustomTextField(
                          controller: _confirmController,
                          label: 'Confirm password',
                          hintText: 'Re-enter your password',
                          isPassword: true,
                          enabled: !isLoading,
                          validator: (v) =>
                              Validators.validatePasswordConfirmation(
                                _passwordController.text,
                                v,
                              ),
                        ),
                        AppPrimaryButton(
                          text: 'Create account',
                          onPressed: _submit,
                          isLoading: isLoading,
                          fullWidth: true,
                        ),
                      ],
                    ),
                    _SignInLink(isLoading: isLoading),
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

/// Shown when [LoginRegistrationSuccess] is emitted — prompts
/// the user to check their inbox and offers a link to sign in.
class _ConfirmEmailCard extends StatelessWidget {
  final String email;

  const _ConfirmEmailCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          boxShadow: DesignConstants.cardShadow,
          border: Border.all(color: DesignConstants.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingBig,
            children: [
              Icon(
                Symbols.mark_email_read_sharp,
                size: DesignConstants.iconSizeBig * 1.5,
                color: DesignConstants.primaryColor,
                weight: DesignConstants.iconWeight,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingMedium,
                children: [
                  Text(
                    'Check your email',
                    style: DesignConstants.h1,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'We sent a confirmation link to',
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    email,
                    style: DesignConstants.h3.copyWith(
                      color: DesignConstants.primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Confirm your email, then sign in below.',
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              AppPrimaryButton(
                text: 'Go to sign in',
                fullWidth: true,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const LoginScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignInLink extends StatelessWidget {
  final bool isLoading;

  const _SignInLink({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Already have an account?',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        GestureDetector(
          onTap: isLoading
              ? null
              : () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  ),
          child: Text(
            'Sign in',
            style: DesignConstants.p.copyWith(
              color: isLoading
                  ? DesignConstants.primaryColor.withValues(alpha: 0.5)
                  : DesignConstants.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
