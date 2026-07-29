import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/bloc/login_state.dart';
import 'package:mobile_app/features/login/data/repositories/auth_repository.dart';

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
    // No persisted session and (by default) empty dev-autologin defines, so the
    // constructor's own `LoginStatusChecked` bootstraps to LoginUnauthenticated
    // — always strictly BEFORE any event this test dispatches from `act`. Every
    // case accounts for it as the first emitted state.
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
        when(() => authRepository.signUp(
              email: 'jane@example.com',
              password: 'password123',
            )).thenAnswer(
          (_) async => AuthResponse(session: _session(user), user: user),
        );
      },
      build: build,
      act: (b) => b.add(const LoginSignUpRequested(
        email: 'jane@example.com',
        password: 'password123',
      )),
      expect: () => [
        const LoginUnauthenticated(), // bootstrap (see setUp comment)
        const LoginLoading(),
        isA<LoginAuthenticated>().having((s) => s.user.id, 'user.id', 'user-1'),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a sign-up with no session (email confirmation required) holds on '
      'the awaiting-confirmation screen instead of authenticating',
      setUp: () {
        final user = _user('user-2');
        when(() => authRepository.signUp(
              email: 'new@example.com',
              password: 'password123',
            )).thenAnswer((_) async => AuthResponse(session: null, user: user));
      },
      build: build,
      act: (b) => b.add(const LoginSignUpRequested(
        email: 'new@example.com',
        password: 'password123',
      )),
      expect: () => [
        const LoginUnauthenticated(),
        const LoginLoading(),
        const LoginAwaitingEmailConfirmation('new@example.com'),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a sign-up for an already-registered email surfaces a friendly error',
      setUp: () {
        when(() => authRepository.signUp(
              email: 'dup@example.com',
              password: 'password123',
            )).thenThrow(AuthException('User already registered'));
      },
      build: build,
      act: (b) => b.add(const LoginSignUpRequested(
        email: 'dup@example.com',
        password: 'password123',
      )),
      expect: () => [
        const LoginUnauthenticated(),
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
      'a session arriving from outside the login form (the confirmation-link '
      'landing, a persisted session, or a token refresh) authenticates',
      build: build,
      act: (_) {
        final user = _user('user-3');
        authStateController
            .add(AuthState(AuthChangeEvent.signedIn, _session(user)));
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const LoginUnauthenticated(),
        isA<LoginAuthenticated>().having((s) => s.user.id, 'user.id', 'user-3'),
      ],
    );
  });

  group('LoginBloc resend confirmation', () {
    blocTest<LoginBloc, LoginState>(
      'a successful resend stays on the awaiting-confirmation screen with '
      'resent flipped true',
      setUp: () {
        when(() => authRepository.resendConfirmation('jane@example.com'))
            .thenAnswer((_) async {});
      },
      build: build,
      seed: () => const LoginAwaitingEmailConfirmation('jane@example.com'),
      act: (b) =>
          b.add(const LoginResendConfirmationRequested('jane@example.com')),
      expect: () => [
        const LoginUnauthenticated(),
        const LoginAwaitingEmailConfirmation('jane@example.com', resent: true),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a failed resend stays on the awaiting-confirmation screen without the '
      'resent flag, so the user can try again',
      setUp: () {
        when(() => authRepository.resendConfirmation('jane@example.com'))
            .thenThrow(Exception('network error'));
      },
      build: build,
      seed: () => const LoginAwaitingEmailConfirmation('jane@example.com'),
      act: (b) =>
          b.add(const LoginResendConfirmationRequested('jane@example.com')),
      expect: () => [
        const LoginUnauthenticated(),
        const LoginAwaitingEmailConfirmation('jane@example.com'),
      ],
    );
  });

  group('LoginBloc sign-out re-entrancy', () {
    blocTest<LoginBloc, LoginState>(
      'signing out with NO active session does not call signOut() — the '
      'listener re-fires this event, so calling signOut() again would loop',
      build: build,
      act: (b) => b.add(const LoginSignOutRequested()),
      // The bootstrap already emitted LoginUnauthenticated; the sign-out
      // handler emits it again but it is deduped (state unchanged).
      expect: () => [const LoginUnauthenticated()],
      verify: (_) => verifyNever(() => authRepository.signOut()),
    );

    blocTest<LoginBloc, LoginState>(
      'signing out WITH an active session calls signOut() once and '
      'unauthenticates',
      setUp: () {
        when(() => authRepository.getCurrentUser())
            .thenReturn(_user('signed-in'));
        when(() => authRepository.signOut()).thenAnswer((_) async {});
      },
      build: build,
      act: (b) => b.add(const LoginSignOutRequested()),
      expect: () => [
        isA<LoginAuthenticated>(), // bootstrap sees the active session
        const LoginUnauthenticated(),
      ],
      verify: (_) => verify(() => authRepository.signOut()).called(1),
    );
  });

  group('LoginBloc dev auto-login', () {
    // The auto-login creds are compile-time `String.fromEnvironment` defines.
    // Run with `--dart-define=DEV_AUTOLOGIN_EMAIL=... --dart-define=
    // DEV_AUTOLOGIN_PASSWORD=...` to exercise the positive path; a plain
    // `flutter test` (empty defines) exercises the negative path. Reading the
    // defines into `final` locals keeps both branches live for the analyzer.
    test('fires an automatic sign-in only when both defines are set', () async {
      final autoEmail = const String.fromEnvironment('DEV_AUTOLOGIN_EMAIL');
      final autoPassword =
          const String.fromEnvironment('DEV_AUTOLOGIN_PASSWORD');
      final hasDefines = autoEmail.isNotEmpty && autoPassword.isNotEmpty;

      when(() => authRepository.signInWithPassword(
            email: autoEmail,
            password: autoPassword,
          )).thenAnswer((_) async => _user('auto'));

      final bloc = build();
      // Let the constructor's LoginStatusChecked (and any auto-login) settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      if (hasDefines) {
        expect(bloc.state, isA<LoginAuthenticated>());
        verify(() => authRepository.signInWithPassword(
              email: autoEmail,
              password: autoPassword,
            )).called(1);
      } else {
        expect(bloc.state, const LoginUnauthenticated());
        verifyNever(() => authRepository.signInWithPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ));
      }
      await bloc.close();
    });
  });
}
