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
/// On [LoginAwaitingEmailConfirmation] (Supabase email confirmation is on)
/// the form is replaced by a "check your email" prompt with a resend link
/// and a way back to sign-in. If sign-up returns a session immediately
/// (confirmations off / auto-confirmed) the [AuthGate] handles the
/// [LoginAuthenticated] transition before this prompt is ever shown.
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
        if (state is LoginAwaitingEmailConfirmation) {
          return _VerifyEmailCard(
            email: state.email,
            resent: state.resent,
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

/// Shown on [LoginAwaitingEmailConfirmation] — prompts the user to open the
/// confirmation link, offers a resend, and a way back to sign-in. Reuses the
/// shared auth chrome ([AuthHeader], card container, [AppPrimaryButton]).
class _VerifyEmailCard extends StatelessWidget {
  final String email;
  final bool resent;

  const _VerifyEmailCard({required this.email, required this.resent});

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
              const AuthHeader(
                title: 'Check your email',
                subtitle: 'Confirm your email to finish setup',
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  _VerifyBody(email: email),
                  if (resent) const _ResentAck(),
                  AppPrimaryButton(
                    text: 'Back to sign in',
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              _ResendLink(email: email),
            ],
          ),
        ),
      ),
    );
  }
}

/// The instruction line, with the destination email emphasized inline.
class _VerifyBody extends StatelessWidget {
  final String email;

  const _VerifyBody({required this.email});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        children: [
          const TextSpan(text: 'We sent a confirmation link to '),
          TextSpan(
            text: email,
            style: DesignConstants.pSemibold.copyWith(
              color: DesignConstants.text,
            ),
          ),
          const TextSpan(
            text: '. Click it to finish setting up your account, '
                'then sign in.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Inline acknowledgement shown after a successful resend.
class _ResentAck extends StatelessWidget {
  const _ResentAck();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: DesignConstants.iconSizeSmall,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'Confirmation link sent',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.primaryColor,
          ),
        ),
      ],
    );
  }
}

/// "Didn't get the email? Resend link" — dispatches
/// [LoginResendConfirmationRequested].
class _ResendLink extends StatelessWidget {
  final String email;

  const _ResendLink({required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          "Didn't get the email?",
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        GestureDetector(
          onTap: () => context.read<LoginBloc>().add(
                LoginResendConfirmationRequested(email),
              ),
          child: Text(
            'Resend link',
            style: DesignConstants.pSemibold.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
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
