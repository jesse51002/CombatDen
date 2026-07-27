import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/data/models/gym_create_response.dart';
import 'package:crm/features/gym_setup/data/models/gym_onboarding_status.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';

class _MockGymRepository extends Mock implements GymRepository {}

GymCreateResponse _createResponse() => GymCreateResponse(
      gymId: 'gym-1',
      stripeAccountId: 'acct_test123',
      stripeOnboardingStatus: GymOnboardingStatus.pending,
      onboardingUrl: 'https://connect.stripe.com/setup/e/acct_test123',
      onboardingUrlExpiresAt:
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

void main() {
  late _MockGymRepository repository;

  setUp(() {
    repository = _MockGymRepository();
    when(
      () => repository.createGym(
        gymName: any(named: 'gymName'),
        address: any(named: 'address'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
      ),
    ).thenAnswer((_) async => _createResponse());
    // The onboarding poller starts as soon as the gym is created.
    when(() => repository.getOnboardingStatus(any()))
        .thenAnswer((_) async => null);
  });

  GymSetupBloc build() => GymSetupBloc(
        gymRepository: repository,
        openUrl: (_) async {},
      );

  group('GymSetupBloc gym create', () {
    blocTest<GymSetupBloc, GymSetupState>(
      'carries the optional address from the name step into the create',
      build: build,
      act: (bloc) {
        bloc.add(
          const GymSetupGymNameSubmitted(
            gymName: 'Aztec MMA',
            address: '1200 W 6th St, Austin, TX 78703',
          ),
        );
        bloc.add(
          const GymSetupOwnerNameSubmitted(
            firstName: 'Jesse',
            lastName: 'Musa',
          ),
        );
      },
      verify: (_) {
        verify(
          () => repository.createGym(
            gymName: 'Aztec MMA',
            address: '1200 W 6th St, Austin, TX 78703',
            firstName: 'Jesse',
            lastName: 'Musa',
          ),
        ).called(1);
      },
    );

    blocTest<GymSetupBloc, GymSetupState>(
      'sends a null address when the owner skipped the field',
      build: build,
      act: (bloc) {
        bloc.add(const GymSetupGymNameSubmitted(gymName: 'Aztec MMA'));
        bloc.add(
          const GymSetupOwnerNameSubmitted(
            firstName: 'Jesse',
            lastName: 'Musa',
          ),
        );
      },
      verify: (_) {
        verify(
          () => repository.createGym(
            gymName: 'Aztec MMA',
            address: null,
            firstName: 'Jesse',
            lastName: 'Musa',
          ),
        ).called(1);
      },
    );
  });
}
