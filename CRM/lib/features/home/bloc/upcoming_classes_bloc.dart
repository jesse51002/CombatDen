import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/home/bloc/upcoming_classes_event.dart';
import 'package:crm/features/home/bloc/upcoming_classes_state.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// How far ahead the dashboard looks for upcoming classes.
const int _kLookaheadDays = 14;

/// How far BACK the request window reaches. Nothing past is displayed (the
/// generator filters to occurrences after now), but including the recent past in
/// the request makes the backend `/classes/instances` read "start" any past,
/// non-cancelled occurrence that ran but was never recorded — the same
/// materialize-on-read the schedule board triggers, so it also fires when the
/// dashboard (the landing page) opens.
const int _kLookbackDays = 7;

/// BLoC for the dashboard Upcoming Classes section. Reads the real schedule
/// feed ([ScheduleRepository.listEffectiveInstances]) — the same
/// `/classes/instances` endpoint the board uses — so the dashboard teaser
/// reflects the live schedule rather than mock data. The request window spans
/// the recent past through the next two weeks: the past is fetched only to
/// trigger the backend materialize-on-read (it isn't displayed), the future is
/// the teaser. Self-contained: it owns its repository + bloc, like the Overdue
/// Payments section.
class UpcomingClassesBloc
    extends Bloc<UpcomingClassesEvent, UpcomingClassesState> {
  final ScheduleRepository _repository;

  UpcomingClassesBloc({required ScheduleRepository repository})
      : _repository = repository,
        super(const UpcomingClassesInitial()) {
    on<UpcomingClassesLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    UpcomingClassesLoadRequested event,
    Emitter<UpcomingClassesState> emit,
  ) async {
    emit(const UpcomingClassesLoading());
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final instances = await _repository.listEffectiveInstances(
        event.gymId,
        today.subtract(const Duration(days: _kLookbackDays)),
        today.add(const Duration(days: _kLookaheadDays)),
      );
      emit(UpcomingClassesLoaded(instances));
    } catch (e, stackTrace) {
      log('Failed to load upcoming classes', error: e, stackTrace: stackTrace);
      emit(UpcomingClassesError(e.toString(), gymId: event.gymId));
    }
  }
}
