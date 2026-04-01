import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';

/// BLoC for the Specific Member Detail screen.
///
/// Handles loading member detail data and managing
/// the sidebar member list with search filtering.
class MemberDetailBloc
    extends Bloc<MemberDetailEvent, MemberDetailState> {
  final MemberRepository _repository;

  MemberDetailBloc({
    required MemberRepository repository,
  })  : _repository = repository,
        super(const MemberDetailInitial()) {
    on<MemberDetailRequested>(_onDetailRequested);
    on<MemberSearchChanged>(_onSearchChanged);
  }

  Future<void> _onDetailRequested(
    MemberDetailRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    emit(const MemberDetailLoading());

    try {
      final results = await Future.wait([
        _repository.getMemberDetail(event.crmUserId),
        _repository.getAllMembers(),
      ]);

      final member = results[0] as dynamic;
      final allMembers = results[1] as List<dynamic>;

      emit(MemberDetailLoaded(
        member: member,
        allMembers: allMembers.cast(),
        filteredMembers: allMembers.cast(),
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to load member detail',
        error: e,
        stackTrace: stackTrace,
      );
      emit(MemberDetailError(e.toString()));
    }
  }

  void _onSearchChanged(
    MemberSearchChanged event,
    Emitter<MemberDetailState> emit,
  ) {
    final currentState = state;
    if (currentState is! MemberDetailLoaded) return;

    final query = event.query.toLowerCase().trim();
    if (query.isEmpty) {
      emit(currentState.copyWith(
        filteredMembers: currentState.allMembers,
        searchQuery: '',
      ));
      return;
    }

    final filtered = currentState.allMembers
        .where(
          (m) =>
              m.fullName.toLowerCase().contains(query),
        )
        .toList();

    emit(currentState.copyWith(
      filteredMembers: filtered,
      searchQuery: query,
    ));
  }
}
