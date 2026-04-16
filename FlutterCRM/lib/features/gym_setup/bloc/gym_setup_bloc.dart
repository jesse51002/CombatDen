import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/data/gym_setup_constants.dart';
import 'package:crm/features/gym_setup/data/models/gym_onboarding_status.dart';
import 'package:crm/features/gym_setup/data/models/gym_onboarding_status_response.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';

/// BLoC driving the multi-step gym setup wizard and
/// the Stripe onboarding poller.
///
/// Polling lives here: a single-shot [Timer] schedules
/// the next `GET /me/onboarding` after each response,
/// so adaptive backoff comes for free and timers never
/// race in-flight requests.
class GymSetupBloc
    extends Bloc<GymSetupEvent, GymSetupState> {
  final GymRepository _gymRepository;
  final Future<void> Function(String url) _openUrl;

  Timer? _pollTimer;
  int _consecutiveErrors = 0;

  String? _pendingGymName;
  String? _pendingFirstName;
  String? _pendingLastName;

  GymSetupBloc({
    required GymRepository gymRepository,
    required Future<void> Function(String url) openUrl,
  })  : _gymRepository = gymRepository,
        _openUrl = openUrl,
        super(const GymSetupInitial()) {
    on<GymSetupCheckRequested>(_onCheckRequested);
    on<GymSetupWelcomeContinued>(_onWelcomeContinued);
    on<GymSetupGymNameSubmitted>(_onGymNameSubmitted);
    on<GymSetupOwnerNameSubmitted>(
      _onOwnerNameSubmitted,
    );
    on<GymSetupResumeAccepted>(_onResumeAccepted);
    on<GymSetupStripeOpenRequested>(
      _onStripeOpenRequested,
    );
    on<GymSetupStripePollNow>(_onStripePollNow);
    on<GymSetupVisibilityChanged>(_onVisibilityChanged);
  }

  // ----- Bootstrap -----

  Future<void> _onCheckRequested(
    GymSetupCheckRequested event,
    Emitter<GymSetupState> emit,
  ) async {
    emit(const GymSetupLoading());
    try {
      final status =
          await _gymRepository.getOnboardingStatus();
      _routeFromStatus(status, emit);
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Gym bootstrap check failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupWelcomeStep(errorMessage: e.message));
    }
  }

  /// Maps a [GymOnboardingStatusResponse] (or null for
  /// 404) to the correct next state and starts the
  /// poller when appropriate.
  void _routeFromStatus(
    GymOnboardingStatusResponse? status,
    Emitter<GymSetupState> emit,
  ) {
    if (status == null) {
      emit(const GymSetupWelcomeStep());
      return;
    }

    switch (status.stripeOnboardingStatus) {
      case GymOnboardingStatus.complete:
        emit(GymSetupComplete(gymId: status.gymId));
      case GymOnboardingStatus.pending:
        if (status.onboardingUrl != null &&
            status.onboardingUrlExpiresAt != null) {
          emit(GymSetupResumeStep(
            gymId: status.gymId,
            onboardingUrl: status.onboardingUrl!,
            onboardingUrlExpiresAt:
                status.onboardingUrlExpiresAt!,
          ));
        } else {
          // Contract violation: status=pending but no
          // URL. Fall back to the welcome step with a
          // recoverable error.
          emit(const GymSetupWelcomeStep(
            errorMessage:
                'Something went wrong. Please try again.',
          ));
        }
      case GymOnboardingStatus.disabled:
        emit(GymSetupDisabledStep(
          gymId: status.gymId,
          disabledReason: status.disabledReason,
        ));
      case GymOnboardingStatus.unknown:
        emit(GymSetupDisabledStep(
          gymId: status.gymId,
          disabledReason: null,
        ));
    }
  }

  // ----- Wizard steps -----

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
    _pendingGymName = event.gymName;
    emit(const GymSetupOwnerNameStep());
  }

  Future<void> _onOwnerNameSubmitted(
    GymSetupOwnerNameSubmitted event,
    Emitter<GymSetupState> emit,
  ) async {
    _pendingFirstName = event.firstName;
    _pendingLastName = event.lastName;
    emit(const GymSetupOwnerNameStep(isSubmitting: true));

    try {
      final response = await _gymRepository.createGym(
        gymName: _pendingGymName!,
        firstName: _pendingFirstName!,
        lastName: _pendingLastName!,
      );
      emit(GymSetupStripeOnboardingStep(
        gymId: response.gymId,
        onboardingUrl: response.onboardingUrl,
        onboardingUrlExpiresAt:
            response.onboardingUrlExpiresAt,
      ));
      add(const GymSetupStripeOpenRequested());
      _startPolling();
    } on GymConflictException catch (e) {
      // All three contract detail strings resolve by
      // re-running the bootstrap check, which routes
      // to the right place.
      log('Gym create 409: ${e.detail}');
      add(const GymSetupCheckRequested());
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Gym create failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupOwnerNameStep(errorMessage: e.message));
    }
  }

  // ----- Resume -----

  Future<void> _onResumeAccepted(
    GymSetupResumeAccepted event,
    Emitter<GymSetupState> emit,
  ) async {
    final current = state;
    if (current is! GymSetupResumeStep) return;

    if (!_isLinkExpired(current.onboardingUrlExpiresAt)) {
      emit(GymSetupStripeOnboardingStep(
        gymId: current.gymId,
        onboardingUrl: current.onboardingUrl,
        onboardingUrlExpiresAt:
            current.onboardingUrlExpiresAt,
      ));
      add(const GymSetupStripeOpenRequested());
      _startPolling();
      return;
    }

    emit(GymSetupResumeStep(
      gymId: current.gymId,
      onboardingUrl: current.onboardingUrl,
      onboardingUrlExpiresAt: current.onboardingUrlExpiresAt,
      isSubmitting: true,
    ));

    try {
      final link =
          await _gymRepository.refreshOnboardingLink();
      emit(GymSetupStripeOnboardingStep(
        gymId: link.gymId,
        onboardingUrl: link.onboardingUrl,
        onboardingUrlExpiresAt: link.onboardingUrlExpiresAt,
      ));
      add(const GymSetupStripeOpenRequested());
      _startPolling();
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Refresh onboarding link failed',
        error: e,
        stackTrace: stackTrace,
      );
      emit(GymSetupResumeStep(
        gymId: current.gymId,
        onboardingUrl: current.onboardingUrl,
        onboardingUrlExpiresAt:
            current.onboardingUrlExpiresAt,
        errorMessage: e.message,
      ));
    }
  }

  // ----- Stripe open -----

  Future<void> _onStripeOpenRequested(
    GymSetupStripeOpenRequested event,
    Emitter<GymSetupState> emit,
  ) async {
    final current = state;
    if (current is! GymSetupStripeOnboardingStep) return;

    var urlToOpen = current.onboardingUrl;

    if (_isLinkExpired(current.onboardingUrlExpiresAt)) {
      emit(current.copyWith(
        isPolling: true,
        clearErrorMessage: true,
      ));
      try {
        final link =
            await _gymRepository.refreshOnboardingLink();
        urlToOpen = link.onboardingUrl;
        emit(current.copyWith(
          onboardingUrl: link.onboardingUrl,
          onboardingUrlExpiresAt:
              link.onboardingUrlExpiresAt,
          isPolling: false,
        ));
      } on DatabaseException catch (e, stackTrace) {
        log(
          'Refresh link before open failed',
          error: e,
          stackTrace: stackTrace,
        );
        emit(current.copyWith(
          isPolling: false,
          errorMessage: e.message,
        ));
        return;
      }
    }

    try {
      await _openUrl(urlToOpen);
    } catch (e, stackTrace) {
      log(
        'Failed to launch Stripe onboarding URL',
        error: e,
        stackTrace: stackTrace,
      );
      final latest = state;
      if (latest is GymSetupStripeOnboardingStep) {
        emit(latest.copyWith(
          errorMessage:
              'Could not open Stripe onboarding.',
        ));
      }
    }
  }

  // ----- Poll tick -----

  Future<void> _onStripePollNow(
    GymSetupStripePollNow event,
    Emitter<GymSetupState> emit,
  ) async {
    final current = state;
    if (current is! GymSetupStripeOnboardingStep) return;

    emit(current.copyWith(
      isPolling: true,
      clearErrorMessage: true,
    ));

    try {
      final status =
          await _gymRepository.getOnboardingStatus();

      if (status == null) {
        _stopPolling();
        emit(const GymSetupWelcomeStep());
        return;
      }

      switch (status.stripeOnboardingStatus) {
        case GymOnboardingStatus.complete:
          _stopPolling();
          emit(GymSetupComplete(gymId: status.gymId));
        case GymOnboardingStatus.pending:
          _consecutiveErrors = 0;
          final latest = state;
          final base = latest is GymSetupStripeOnboardingStep
              ? latest
              : current;
          emit(base.copyWith(
            onboardingUrl: status.onboardingUrl ??
                base.onboardingUrl,
            onboardingUrlExpiresAt:
                status.onboardingUrlExpiresAt ??
                    base.onboardingUrlExpiresAt,
            requirementsDue:
                status.requirementsCurrentlyDue,
            isPolling: false,
            showBackendTroubleBanner: false,
          ));
          _scheduleNextTick(
            GymSetupConstants.pollInterval,
          );
        case GymOnboardingStatus.disabled:
          _stopPolling();
          emit(GymSetupDisabledStep(
            gymId: status.gymId,
            disabledReason: status.disabledReason,
          ));
        case GymOnboardingStatus.unknown:
          _stopPolling();
          emit(GymSetupDisabledStep(
            gymId: status.gymId,
            disabledReason: null,
          ));
      }
    } on DatabaseException catch (e, stackTrace) {
      log(
        'Poll tick failed',
        error: e,
        stackTrace: stackTrace,
      );
      _consecutiveErrors++;
      final latest = state;
      if (latest is GymSetupStripeOnboardingStep) {
        emit(latest.copyWith(
          isPolling: false,
          showBackendTroubleBanner: _consecutiveErrors >=
              GymSetupConstants.bannerThresholdErrors,
        ));
      }
      _scheduleNextTick(_nextBackoff());
    }
  }

  // ----- Visibility -----

  void _onVisibilityChanged(
    GymSetupVisibilityChanged event,
    Emitter<GymSetupState> emit,
  ) {
    if (!event.visible) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    if (state is GymSetupStripeOnboardingStep) {
      _pollTimer?.cancel();
      _pollTimer = null;
      add(const GymSetupStripePollNow());
    }
  }

  // ----- Helpers -----

  bool _isLinkExpired(DateTime expiresAt) {
    final deadline = DateTime.now()
        .toUtc()
        .add(GymSetupConstants.linkExpiryBuffer);
    return expiresAt.toUtc().isBefore(deadline);
  }

  Duration _nextBackoff() {
    const schedule = <Duration>[
      GymSetupConstants.errorBackoff1,
      GymSetupConstants.errorBackoff2,
      GymSetupConstants.errorBackoffMax,
    ];
    final index =
        math.min(_consecutiveErrors - 1, schedule.length - 1);
    return schedule[math.max(index, 0)];
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _consecutiveErrors = 0;
    _scheduleNextTick(GymSetupConstants.pollInterval);
  }

  void _scheduleNextTick(Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(
      delay,
      () => add(const GymSetupStripePollNow()),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _consecutiveErrors = 0;
  }

  @override
  Future<void> close() {
    _stopPolling();
    return super.close();
  }
}
