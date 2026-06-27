import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/features/home/bloc/overdue_payments_event.dart';
import 'package:crm/features/home/bloc/overdue_payments_state.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';

/// BLoC for the dashboard Overdue Payments section.
///
/// Reuses [MembersListRepository] (no parallel data layer)
/// to load the overdue count plus the full overdue roster.
/// Unlike the members-list screen this surface only needs
/// the overdue view, so it pages through everything up front
/// rather than scroll-paginating — overdue sets are small,
/// so in practice it is a single request, with no silent
/// truncation if a gym ever has many delinquents.
class OverduePaymentsBloc
    extends Bloc<OverduePaymentsEvent, OverduePaymentsState> {
  final MembersListRepository _repository;

  OverduePaymentsBloc({
    required MembersListRepository repository,
  })  : _repository = repository,
        super(const OverduePaymentsInitial()) {
    on<OverduePaymentsLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    OverduePaymentsLoadRequested event,
    Emitter<OverduePaymentsState> emit,
  ) async {
    emit(const OverduePaymentsLoading());

    try {
      final counts =
          await _repository.getTotalCounts(event.gymId);

      final rows = <OverdueViewRow>[];
      var startIndex = 0;
      while (true) {
        // The overdue view is self-sufficient (its SQL hardcodes the
        // overdue condition), so view=overdue with empty filters
        // returns exactly the overdue members.
        final request = CrmMembersListRequest(
          gymId: event.gymId,
          view: MembersListView.overdue,
          startIndex: startIndex,
          count: AppConstants.defaultPageSize,
        );

        final response =
            await _repository.getMembersList(request);

        rows.addAll(
          response.data.whereType<OverdueViewRow>(),
        );

        if (response.data.length <
            AppConstants.defaultPageSize) {
          break;
        }
        startIndex += AppConstants.defaultPageSize;
      }

      emit(OverduePaymentsLoaded(
        rows: rows,
        overdueCount: counts.overdue,
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to load overdue payments',
        error: e,
        stackTrace: stackTrace,
      );
      emit(OverduePaymentsError(
        e.toString(),
        gymId: event.gymId,
      ));
    }
  }
}
