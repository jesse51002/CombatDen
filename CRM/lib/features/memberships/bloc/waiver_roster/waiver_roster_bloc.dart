import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/waiver_roster/waiver_roster_event.dart';
import 'package:crm/features/memberships/bloc/waiver_roster/waiver_roster_state.dart';
import 'package:crm/features/memberships/data/models/waiver_signatory_row.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// Loads a single waiver's version history + per-member
/// signature roster for the read-only roster screen.
class WaiverRosterBloc extends Bloc<WaiverRosterEvent, WaiverRosterState> {
  final MembershipsRepository _repository;

  WaiverRosterBloc({required MembershipsRepository repository})
      : _repository = repository,
        super(const WaiverRosterInitial()) {
    on<WaiverRosterRequested>(_onRequested);
  }

  Future<void> _onRequested(
    WaiverRosterRequested event,
    Emitter<WaiverRosterState> emit,
  ) async {
    emit(const WaiverRosterLoading());
    try {
      final results = await Future.wait([
        _repository.listWaiverVersions(event.waiverId, event.gymId),
        _repository.listWaiverSignatories(event.waiverId, event.gymId),
      ]);
      emit(WaiverRosterLoaded(
        versions: results[0] as List<WaiverVersionResponse>,
        signatories: results[1] as List<WaiverSignatoryRow>,
      ));
    } catch (e, stackTrace) {
      log('Failed to load waiver roster', error: e, stackTrace: stackTrace);
      emit(WaiverRosterError(e.toString()));
    }
  }
}
