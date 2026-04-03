import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';

/// BLoC for the multi-step gym setup wizard.
///
/// Collects all data across steps, then submits
/// everything in one request at the end.
class GymSetupBloc
    extends Bloc<GymSetupEvent, GymSetupState> {
  final GymRepository _gymRepository;
  final String _userId;

  String? _gymName;
  String? _firstName;
  String? _lastName;

  GymSetupBloc({
    required GymRepository gymRepository,
    required String userId,
  })  : _gymRepository = gymRepository,
        _userId = userId,
        super(const GymSetupInitial()) {
    on<GymSetupCheckRequested>(_onCheckRequested);
    on<GymSetupWelcomeContinued>(_onWelcomeContinued);
    on<GymSetupGymNameSubmitted>(_onGymNameSubmitted);
    on<GymSetupOwnerNameSubmitted>(
      _onOwnerNameSubmitted,
    );
  }

  Future<void> _onCheckRequested(
    GymSetupCheckRequested event,
    Emitter<GymSetupState> emit,
  ) async {
    emit(const GymSetupLoading());
    try {
      final employee =
          await _gymRepository.getOwnerEmployee(
        _userId,
      );

      if (employee == null) {
        emit(const GymSetupWelcomeStep());
        return;
      }

      emit(const GymSetupComplete());
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Gym setup check failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupGymNameStep(
        errorMessage: e.message,
      ));
    }
  }

  void _onWelcomeContinued(
    GymSetupWelcomeContinued event,
    Emitter<GymSetupState> emit,
  ) {
    emit(const GymSetupGymNameStep());
  }

  void _onGymNameSubmitted(
    GymSetupGymNameSubmitted event,
    Emitter<GymSetupState> emit,
  ) {
    _gymName = event.gymName;
    emit(const GymSetupOwnerNameStep());
  }

  Future<void> _onOwnerNameSubmitted(
    GymSetupOwnerNameSubmitted event,
    Emitter<GymSetupState> emit,
  ) async {
    _firstName = event.firstName;
    _lastName = event.lastName;
    emit(const GymSetupOwnerNameStep(
      isSubmitting: true,
    ));
    try {
      await _gymRepository.setupGym(
        gymName: _gymName!,
        userId: _userId,
        firstName: _firstName!,
        lastName: _lastName!,
      );
      emit(const GymSetupComplete());
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Gym setup failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupOwnerNameStep(
        errorMessage: e.message,
      ));
    }
  }
}
