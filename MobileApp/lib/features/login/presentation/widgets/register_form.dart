import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/utils/validators.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/bloc/login_state.dart';
import 'package:mobile_app/features/login/presentation/widgets/auth_header.dart';
import 'package:mobile_app/features/login/presentation/widgets/verify_email_view.dart';
import 'package:mobile_app/shared/widgets/app_text_field.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/error_message.dart';

/// Registration form. Driven by [LoginBloc] from context.
///
/// Once a sign-up needs email confirmation the form stays mounted (retaining
/// the entered password) and swaps its body to [VerifyEmailView] — a local
/// `_awaitingConfirmation` flag keeps it there across the "continue" sign-in
/// attempt's loading/error states, so the retained password can re-attempt
/// sign-in after the user confirms in their browser.
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

  /// Set true once sign-up returns awaiting-confirmation; keeps the verify
  /// view up through the "continue" sign-in attempt's loading/error states.
  bool _awaitingConfirmation = false;
  String _confirmEmail = '';

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

  void _continueAfterConfirm() {
    context.read<LoginBloc>().add(
      LoginSignInRequested(
        email: _confirmEmail,
        password: _passwordController.text,
      ),
    );
  }

  void _resend() {
    context.read<LoginBloc>().add(
      LoginResendConfirmationRequested(_confirmEmail),
    );
  }

  void _backToSignIn() {
    setState(() => _awaitingConfirmation = false);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LoginBloc, LoginState>(
      listener: (context, state) {
        if (state is LoginAwaitingEmailConfirmation) {
          setState(() {
            _awaitingConfirmation = true;
            _confirmEmail = state.email;
          });
        }
      },
      builder: (context, state) {
        if (_awaitingConfirmation) {
          final resent =
              state is LoginAwaitingEmailConfirmation && state.resent;
          // A sign-in error from the "continue" attempt (isLoginError) means
          // the account still isn't confirmed — surface it on the verify view.
          final error = (state is LoginError && state.isLoginError)
              ? state.message
              : null;
          return VerifyEmailView(
            email: _confirmEmail,
            isLoading: state is LoginLoading,
            resent: resent,
            errorMessage: error,
            onContinue: _continueAfterConfirm,
            onResend: _resend,
            onBackToSignIn: _backToSignIn,
          );
        }

        final isLoading = state is LoginLoading;
        final errorMessage = (state is LoginError && !state.isLoginError)
            ? state.message
            : null;

        return Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingBig,
            children: [
              const AuthHeader(
                title: 'Create account',
                subtitle: 'Join your gym in the app',
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  if (errorMessage != null) ErrorMessage(message: errorMessage),
                  const _OnFileHint(),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hintText: 'you@email.com',
                    enabled: !isLoading,
                    validator: Validators.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hintText: 'At least 8 characters, letter + number',
                    isPassword: true,
                    enabled: !isLoading,
                    validator: Validators.validatePassword,
                  ),
                  AppTextField(
                    controller: _confirmController,
                    label: 'Confirm password',
                    hintText: 'Re-enter your password',
                    isPassword: true,
                    enabled: !isLoading,
                    validator: (v) => Validators.validatePasswordConfirmation(
                      _passwordController.text,
                      v,
                    ),
                  ),
                  AppPrimaryButton(
                    text: isLoading ? 'Creating…' : 'Create account',
                    onPressed: isLoading ? null : _submit,
                    fullWidth: true,
                  ),
                ],
              ),
              _SignInLink(isLoading: isLoading),
            ],
          ),
        );
      },
    );
  }
}

/// The "use the email your gym has on file" hint — the load-bearing copy that
/// tells a member to sign up with the address the gym already has, so the
/// backend matches them to their membership rows.
class _OnFileHint extends StatelessWidget {
  const _OnFileHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Use the email your gym has on file. '
      "That's how we match you to your membership.",
      style: DesignConstants.pSmall.copyWith(color: DesignConstants.text2nd),
      textAlign: TextAlign.center,
    );
  }
}

/// "Already have an account? Sign in" — pops back to the login screen.
class _SignInLink extends StatelessWidget {
  const _SignInLink({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Already have an account?',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        GestureDetector(
          onTap: isLoading ? null : () => Navigator.of(context).maybePop(),
          child: Text(
            'Sign in',
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
