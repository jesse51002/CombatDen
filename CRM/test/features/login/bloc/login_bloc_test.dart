import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/data/repositories/auth_repository.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

User _user(String id, {String email = 'jane@example.com'}) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime(2026, 1, 1).toIso8601String(),
    );

Session _session(User user) => Session(
      accessToken: 'access-token',
      tokenType: 'bearer',
      user: user,
    );

void main() {
  late _MockAuthRepository authRepository;
  late StreamController<AuthState> authStateController;

  setUp(() {
    authRepository = _MockAuthRepository();
    authStateController = StreamController<AuthState>.broadcast();
    when(() => authRepository.authStateChanges)
        .thenAnswer((_) => authStateController.stream);
    // No persisted session and dev auto-login dart-defines are empty in
    // test, so every bloc under test bootstraps to LoginUnauthenticated —
    // that bootstrap transition (fired by the constructor's own
    // `add(LoginStatusChecked())`) is asynchronous relative to `add()`
    // (bloc's default event transformer flat-maps a broadcast stream), so
    // it always lands strictly BEFORE any event this test dispatches from
    // `act`. Every case below accounts for it as the first emitted state.
    when(() => authRepository.getCurrentUser()).thenReturn(null);
  });

  tearDown(() => authStateController.close());

  LoginBloc build() => LoginBloc(authRepository: authRepository);

  group('LoginBloc sign-up', () {
    blocTest<LoginBloc, LoginState>(
      'a sign-up that returns a session (confirmations off / '
      'auto-confirmed) authenticates immediately',
      setUp: () {
        final user = _user('user-1');
        when(
          () => authRepository.signUp(
            email: 'jane@example.com',
            password: 'password123',
          ),
        ).thenAnswer(
          (_) async => AuthResponse(session: _session(user), user: user),
        );
      },
      build: build,
      act: (b) => b.add(
        const LoginSignUpRequested(
          email: 'jane@example.com',
          password: 'password123',
        ),
      ),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        const LoginLoading(),
        isA<LoginAuthenticated>()
            .having((s) => s.user.id, 'user.id', 'user-1'),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a sign-up with no session (email confirmation required) holds on '
      'the awaiting-confirmation screen instead of authenticating',
      setUp: () {
        final user = _user('user-2');
        when(
          () => authRepository.signUp(
            email: 'new@example.com',
            password: 'password123',
          ),
        ).thenAnswer((_) async => AuthResponse(session: null, user: user));
      },
      build: build,
      act: (b) => b.add(
        const LoginSignUpRequested(
          email: 'new@example.com',
          password: 'password123',
        ),
      ),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        const LoginLoading(),
        const LoginAwaitingEmailConfirmation('new@example.com'),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a sign-up for an already-registered email surfaces a friendly error',
      setUp: () {
        when(
          () => authRepository.signUp(
            email: 'dup@example.com',
            password: 'password123',
          ),
        ).thenThrow(AuthException('User already registered'));
      },
      build: build,
      act: (b) => b.add(
        const LoginSignUpRequested(
          email: 'dup@example.com',
          password: 'password123',
        ),
      ),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        const LoginLoading(),
        const LoginError(
          message: 'This email is already registered',
          isLoginError: false,
        ),
      ],
    );
  });

  group('LoginBloc external session', () {
    blocTest<LoginBloc, LoginState>(
      'a session arriving from outside the login form (the '
      'confirmation-link landing, a persisted session, a token refresh, or '
      'password recovery) flips the app to authenticated',
      build: build,
      act: (_) {
        final user = _user('user-3');
        authStateController.add(
          AuthState(AuthChangeEvent.signedIn, _session(user)),
        );
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        isA<LoginAuthenticated>()
            .having((s) => s.user.id, 'user.id', 'user-3'),
      ],
    );
  });

  group('LoginBloc resend confirmation', () {
    blocTest<LoginBloc, LoginState>(
      'a successful resend stays on the awaiting-confirmation screen '
      'with resent flipped true',
      setUp: () {
        when(() => authRepository.resendConfirmation('jane@example.com'))
            .thenAnswer((_) async {});
      },
      build: build,
      seed: () => const LoginAwaitingEmailConfirmation('jane@example.com'),
      act: (b) => b.add(
        const LoginResendConfirmationRequested('jane@example.com'),
      ),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        const LoginAwaitingEmailConfirmation(
          'jane@example.com',
          resent: true,
        ),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a failed resend stays on the awaiting-confirmation screen without '
      'the resent flag, so the user can try again',
      setUp: () {
        when(() => authRepository.resendConfirmation('jane@example.com'))
            .thenThrow(Exception('network error'));
      },
      build: build,
      seed: () => const LoginAwaitingEmailConfirmation('jane@example.com'),
      act: (b) => b.add(
        const LoginResendConfirmationRequested('jane@example.com'),
      ),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        const LoginAwaitingEmailConfirmation('jane@example.com'),
      ],
    );
  });
}
