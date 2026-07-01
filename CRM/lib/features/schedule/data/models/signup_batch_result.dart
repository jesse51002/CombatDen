import 'package:equatable/equatable.dart';

/// Outcome of one member's sign-up attempt inside a "Reserve members" batch.
///
/// A CRM-side aggregate — there is no backend batch sign-up endpoint, so
/// [ScheduleBloc] loops `POST /api/v1/signup` once per member and collects
/// each outcome here. [reason] carries the failure message (e.g. "Class is
/// full") when [status] is [SignupBatchStatus.failed]; null otherwise.
enum SignupBatchStatus { signedUp, alreadySignedUp, failed }

class SignupBatchResultItem extends Equatable {
  final String memberId;
  final SignupBatchStatus status;
  final String? reason;

  const SignupBatchResultItem({
    required this.memberId,
    required this.status,
    this.reason,
  });

  @override
  List<Object?> get props => [memberId, status, reason];
}

/// The full per-member breakdown of a "Reserve members" batch, in request
/// order. One bad member (e.g. the room is full) never sinks the rest — each
/// [SignupBatchResultItem] is independent.
class SignupBatchResponse extends Equatable {
  final List<SignupBatchResultItem> results;

  const SignupBatchResponse({this.results = const []});

  /// Newly-created sign-ups (excludes already-signed-up repeats).
  int get signedUpCount =>
      results.where((r) => r.status == SignupBatchStatus.signedUp).length;

  List<SignupBatchResultItem> get failed =>
      results.where((r) => r.status == SignupBatchStatus.failed).toList();

  @override
  List<Object?> get props => [results];
}
