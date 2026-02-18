import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/features/login/presentation/widgets/auth_header.dart';
import 'package:crm/features/login/presentation/screens/register_screen.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
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
    return BlocConsumer<LoginBloc, LoginState>(
      listener: (context, state) {
        // Handle successful authentication
        if (state is LoginAuthenticated) {
          // Navigation will be handled by the app-level auth listener
        }
      },
      builder: (context, state) {
        final isLoading = state is LoginLoading;
        final errorMessage = state is LoginError && state.isLoginError
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
                    title: 'Welcome Back',
                    subtitle: 'Sign in to continue',
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
                    hintText: 'Enter your password',
                    isPassword: true,
                    enabled: !isLoading,
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Password is required' : null,
                  ),
                  SizedBox(height: DesignConstants.spacingBig.toDouble()),
                  PrimaryButton(
                    text: 'Sign In',
                    onPressed: _handleLogin,
                    isLoading: isLoading,
                  ),
                  SizedBox(height: DesignConstants.spacingLarge.toDouble()),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
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
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Sign Up',
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
