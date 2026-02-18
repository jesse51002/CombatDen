import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/features/login/presentation/widgets/auth_header.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';

class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() {
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
        final isLoading = state is LoginLoading;
        final errorMessage = state is LoginError && !state.isLoginError
            ? state.message
            : null;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            decoration: BoxDecoration(
              color: DesignConstants.cardBackground,
              borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            ),
            padding: EdgeInsets.all(DesignConstants.paddingBig.toDouble()),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AuthHeader(
                    title: 'Create Account',
                    subtitle: 'Sign up to get started',
                  ),
                  SizedBox(height: DesignConstants.spacingBig.toDouble()),
                  if (errorMessage != null) ...[
                    ErrorMessage(message: errorMessage),
                    SizedBox(height: DesignConstants.spacingLarge.toDouble()),
                  ],
                  CustomTextField(
                    controller: _emailController,
                    label: 'Email',
                    hintText: 'Enter your email',
                    enabled: !isLoading,
                    validator: Validators.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: DesignConstants.spacingLarge.toDouble()),
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hintText: 'At least 8 characters, letter + number',
                    isPassword: true,
                    enabled: !isLoading,
                    validator: Validators.validatePassword,
                  ),
                  SizedBox(height: DesignConstants.spacingLarge.toDouble()),
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hintText: 'Re-enter your password',
                    isPassword: true,
                    enabled: !isLoading,
                    validator: (value) =>
                        Validators.validatePasswordConfirmation(
                          _passwordController.text,
                          value,
                        ),
                  ),
                  SizedBox(height: DesignConstants.spacingBig.toDouble()),
                  PrimaryButton(
                    text: 'Sign Up',
                    onPressed: _handleRegister,
                    isLoading: isLoading,
                  ),
                  SizedBox(height: DesignConstants.spacingLarge.toDouble()),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: DesignConstants.p.copyWith(
                          color: DesignConstants.text.withValues(alpha: 0.7),
                        ),
                      ),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Sign In',
                          style: DesignConstants.p.copyWith(
                            color: isLoading
                                ? DesignConstants.primary.withValues(alpha: 0.5)
                                : DesignConstants.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
