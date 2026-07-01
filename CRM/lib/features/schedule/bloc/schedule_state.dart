import 'package:equatable/equatable.dart';

import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/signup_batch_result.dart';

sealed class ScheduleState extends Equatable {
  const ScheduleState();

  @override
  List<Object?> get props => [];
}

class ScheduleInitial extends ScheduleState {
  const ScheduleInitial();
}

class ScheduleLoading extends ScheduleState {
  const ScheduleLoading();
}

/// The board loaded for [weekStart]: the effective [instances] across that week
/// plus the gym's [classes] (the catalog, week-independent).
///
/// [isMutating] / [actionError] / [actionSuccessCount] carry the create / edit
/// / soft-delete mutation lifecycle (mirrors `PlansLoaded`): a mutation flips
/// [isMutating] on, then either bumps [actionSuccessCount] (success, board
/// reloaded) or sets [actionError] (failure). The class form watches these to
/// drive its processing → success → error terminal state.
class ScheduleLoaded extends ScheduleState {
  final DateTime weekStart;
  final List<EffectiveClassInstance> instances;
  final List<GymClassResponse> classes;

  /// True while a create / update / delete is in flight.
  final bool isMutating;

  /// Set when the last mutation failed; cleared when the next one starts.
  final String? actionError;

  /// Monotonic counter bumped on each successful mutation. A watcher snapshots
  /// it and treats an increase as "my mutation committed".
  final int actionSuccessCount;

  /// True while a batch staff check-in ("Update attendees") is in flight.
  /// A DEDICATED channel separate from [isMutating] so the check-in dialog owns
  /// its own processing → results step and the board's class-CRUD lifecycle
  /// never collides with it (mirrors the member-detail charge-card channel).
  final bool isCheckingIn;

  /// The last batch check-in's per-member breakdown (207 Multi-Status body).
  /// Rendered by the check-in dialog's results step; cleared via
  /// [ScheduleBatchCheckInCleared].
  final BatchCheckInResponse? batchCheckInResult;

  /// The last batch check-in failure (total failure / transport error). Kept
  /// off [actionError] so the board-level mutation handling doesn't swallow it
  /// while the check-in dialog is open.
  final String? checkInError;

  /// True while a "Sign up members" batch is in flight — its own channel,
  /// mirroring [isCheckingIn], so it doesn't collide with class-CRUD
  /// [isMutating] or the check-in channel (both dialogs can, in principle,
  /// be opened from the same occurrence screen at different times).
  final bool isSigningUp;

  /// The last "Sign up members" batch's per-member breakdown. There is no
  /// backend batch sign-up endpoint — [ScheduleBloc] loops `POST
  /// /api/v1/signup` and assembles this itself. Rendered by the sign-up
  /// dialog's results step; cleared via [ScheduleSignUpCleared].
  final SignupBatchResponse? signupResult;

  const ScheduleLoaded({
    required this.weekStart,
    required this.instances,
    required this.classes,
    this.isMutating = false,
    this.actionError,
    this.actionSuccessCount = 0,
    this.isCheckingIn = false,
    this.batchCheckInResult,
    this.checkInError,
    this.isSigningUp = false,
    this.signupResult,
  });

  /// Toggle only the lifecycle fields on the same loaded data.
  /// [actionError] follows reset semantics — an omitted value clears it — so
  /// starting a mutation (`copyWith(isMutating: true)`) wipes a stale error.
  /// The check-in channel is preserved across class-CRUD copyWiths; pass
  /// [clearCheckIn] to reset its result + error (e.g. when the check-in dialog
  /// opens or closes). The sign-up channel works the same way via
  /// [clearSignUp].
  ScheduleLoaded copyWith({
    bool? isMutating,
    String? actionError,
    bool? isCheckingIn,
    BatchCheckInResponse? batchCheckInResult,
    String? checkInError,
    bool clearCheckIn = false,
    bool? isSigningUp,
    SignupBatchResponse? signupResult,
    bool clearSignUp = false,
  }) {
    return ScheduleLoaded(
      weekStart: weekStart,
      instances: instances,
      classes: classes,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError,
      actionSuccessCount: actionSuccessCount,
      isCheckingIn: isCheckingIn ?? this.isCheckingIn,
      batchCheckInResult: clearCheckIn
          ? null
          : (batchCheckInResult ?? this.batchCheckInResult),
      checkInError:
          clearCheckIn ? null : (checkInError ?? this.checkInError),
      isSigningUp: isSigningUp ?? this.isSigningUp,
      signupResult:
          clearSignUp ? null : (signupResult ?? this.signupResult),
    );
  }

  @override
  List<Object?> get props => [
        weekStart,
        instances,
        classes,
        isMutating,
        actionError,
        actionSuccessCount,
        isCheckingIn,
        batchCheckInResult,
        checkInError,
        isSigningUp,
        signupResult,
      ];
}

class ScheduleError extends ScheduleState {
  final String message;

  const ScheduleError(this.message);

  @override
  List<Object?> get props => [message];
}
