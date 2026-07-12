import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/member_create_event.dart';
import 'package:crm/features/member_details/bloc/member_create_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';

/// Drives creating a new member: submit → (duplicate | created | failure),
/// plus create-anyway and use-existing off the duplicate step. Reusable — the
/// add-member flow and the in-wizard new-member dialog both host it; each
/// decides what to do once [MemberCreated] arrives.
class MemberCreateBloc
    extends Bloc<MemberCreateEvent, MemberCreateState> {
  final MemberRepository _repository;

  MemberCreateBloc({required MemberRepository repository})
      : _repository = repository,
        super(const MemberCreateIdle()) {
    on<MemberCreateSubmitted>(_onSubmitted);
    on<MemberCreateAnywayRequested>(_onCreateAnyway);
    on<MemberCreateUseExisting>(_onUseExisting);
    on<MemberCreateReset>(_onReset);
  }

  Future<void> _create(
    MembersManagementCreateRequest request,
    Emitter<MemberCreateState> emit,
  ) async {
    emit(const MemberCreateSubmitting());
    try {
      final memberId = await _repository.createMember(request);
      emit(MemberCreated(memberId));
    } on DuplicateMemberException catch (e) {
      emit(MemberCreateDuplicate(
        matches: e.matches,
        pendingRequest: request,
      ));
    } catch (e, stackTrace) {
      log('Create member failed', error: e, stackTrace: stackTrace);
      final needsStripe =
          e is ServerException && e.statusCode == 400;
      emit(MemberCreateFailure(
        e is ServerException ? (e.detail ?? e.message) : e.toString(),
        needsStripeSetup: needsStripe,
      ));
    }
  }

  Future<void> _onSubmitted(
    MemberCreateSubmitted event,
    Emitter<MemberCreateState> emit,
  ) =>
      _create(event.request, emit);

  Future<void> _onCreateAnyway(
    MemberCreateAnywayRequested event,
    Emitter<MemberCreateState> emit,
  ) async {
    final s = state;
    if (s is! MemberCreateDuplicate) return;
    await _create(
      s.pendingRequest.copyWith(allowDuplicate: true),
      emit,
    );
  }

  void _onUseExisting(
    MemberCreateUseExisting event,
    Emitter<MemberCreateState> emit,
  ) {
    emit(MemberCreated(event.memberId));
  }

  void _onReset(
    MemberCreateReset event,
    Emitter<MemberCreateState> emit,
  ) {
    emit(const MemberCreateIdle());
  }
}
