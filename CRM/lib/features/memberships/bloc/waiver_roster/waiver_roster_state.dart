import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/waiver_signatory_row.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';

sealed class WaiverRosterState extends Equatable {
  const WaiverRosterState();

  @override
  List<Object?> get props => [];
}

class WaiverRosterInitial extends WaiverRosterState {
  const WaiverRosterInitial();
}

class WaiverRosterLoading extends WaiverRosterState {
  const WaiverRosterLoading();
}

class WaiverRosterLoaded extends WaiverRosterState {
  /// Version history, newest first, each with its sign count.
  final List<WaiverVersionResponse> versions;

  /// Every gym member + their latest sign status for this waiver.
  final List<WaiverSignatoryRow> signatories;

  const WaiverRosterLoaded({
    required this.versions,
    required this.signatories,
  });

  @override
  List<Object?> get props => [versions, signatories];
}

class WaiverRosterError extends WaiverRosterState {
  final String message;

  const WaiverRosterError(this.message);

  @override
  List<Object?> get props => [message];
}
