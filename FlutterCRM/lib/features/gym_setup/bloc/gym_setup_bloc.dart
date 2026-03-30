import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';

/// BLoC for the multi-step gym setup wizard
class GymSetupBloc
    extends Bloc<GymSetupEvent, GymSetupState> {
  final GymRepository _gymRepository;
  final String _userId;
  String? _gymId;

  GymSetupBloc({
    required GymRepository gymRepository,
    required String userId,
  })  : _gymRepository = gymRepository,
        _userId = userId,
        super(const GymSetupInitial()) {
    on<GymSetupCheckRequested>(_onCheckRequested);
    on<GymSetupWelcomeContinued>(_onWelcomeContinued);
    on<GymSetupGymNameSubmitted>(_onGymNameSubmitted);
    on<GymSetupRankConfigSubmitted>(
      _onRankConfigSubmitted,
    );
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
      final gym = await _gymRepository.getGymByOwnerId(
        _userId,
      );

      if (gym == null) {
        emit(const GymSetupWelcomeStep());
        return;
      }

      _gymId = gym['gym_id'] as String;

      final profile =
          await _gymRepository.getUserGymProfile(
        userId: _userId,
        gymId: _gymId!,
      );

      if (profile == null) {
        final hasRankConfig =
            gym['rank_preset'] != null;
        if (!hasRankConfig) {
          emit(GymSetupRankConfigStep(
            gymId: _gymId!,
          ));
        } else {
          emit(GymSetupOwnerNameStep(
            gymId: _gymId!,
          ));
        }
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

  Future<void> _onGymNameSubmitted(
    GymSetupGymNameSubmitted event,
    Emitter<GymSetupState> emit,
  ) async {
    emit(const GymSetupGymNameStep(isSubmitting: true));
    try {
      final gym = await _gymRepository.createGym(
        gymName: event.gymName,
        ownerId: _userId,
      );
      _gymId = gym['gym_id'] as String;
      emit(GymSetupRankConfigStep(gymId: _gymId!));
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Gym creation failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupGymNameStep(
        errorMessage: e.message,
      ));
    }
  }

  Future<void> _onRankConfigSubmitted(
    GymSetupRankConfigSubmitted event,
    Emitter<GymSetupState> emit,
  ) async {
    emit(GymSetupRankConfigStep(
      gymId: _gymId!,
      isSubmitting: true,
    ));
    try {
      await _gymRepository.updateGymRankConfig(
        gymId: _gymId!,
        rankEnabled: event.rankEnabled,
        rankPreset: event.rankPreset,
      );
      emit(GymSetupOwnerNameStep(gymId: _gymId!));
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Rank config update failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupRankConfigStep(
        gymId: _gymId!,
        errorMessage: e.message,
      ));
    }
  }

  Future<void> _onOwnerNameSubmitted(
    GymSetupOwnerNameSubmitted event,
    Emitter<GymSetupState> emit,
  ) async {
    emit(GymSetupOwnerNameStep(
      gymId: _gymId!,
      isSubmitting: true,
    ));
    try {
      await _gymRepository.createUserGymProfile(
        userId: _userId,
        gymId: _gymId!,
        firstName: event.firstName,
        lastName: event.lastName,
      );
      emit(const GymSetupComplete());
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Profile creation failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupOwnerNameStep(
        gymId: _gymId!,
        errorMessage: e.message,
      ));
    }
  }
}
