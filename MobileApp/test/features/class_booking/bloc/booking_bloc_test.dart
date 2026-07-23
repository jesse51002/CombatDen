import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_bloc.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_event.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_state.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/models/signup_result.dart';
import 'package:mobile_app/features/home/data/repositories/member_signup_repository.dart';

class _MockSignupRepo extends Mock implements MemberSignupRepository {}

ClassOccurrence _occ() => const ClassOccurrence(
      classId: 'c1',
      gymId: 'g1',
      className: 'Muay Thai',
      classDate: '2026-07-23',
      originalDate: '2026-07-23',
      originalTime: '18:00:00',
      occurredAt: '2026-07-23T18:00:00Z',
      resolvedClassTime: '18:00:00',
      resolvedDurationMinutes: 55,
      imageUrl: 'https://x/i.png',
      pointsWorth: 50,
      isCancelled: false,
      hasInstanceException: false,
      hasRangeException: false,
      signupCount: 5,
    );

void main() {
  late _MockSignupRepo repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
    );
    repo = _MockSignupRepo();
  });

  BookingBloc build({bool booked = false}) => BookingBloc(
        repository: repo,
        occurrence: _occ(),
        initiallyBooked: booked,
      );

  void stubReserve(SignupResult result) {
    when(() => repo.reserve(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          classId: any(named: 'classId'),
          occurrenceDate: any(named: 'occurrenceDate'),
          occurrenceTime: any(named: 'occurrenceTime'),
        )).thenAnswer((_) async => result);
  }

  blocTest<BookingBloc, BookingState>(
    'reserve success flips booked and bumps the reserve token',
    setUp: () => stubReserve(
      const SignupResult(signupId: 's1', alreadySignedUp: false),
    ),
    build: build,
    act: (b) => b.add(const BookingReserveRequested()),
    expect: () => [
      isA<BookingState>()
          .having((s) => s.status, 'status', BookingStatus.reserving),
      isA<BookingState>()
          .having((s) => s.booked, 'booked', true)
          .having((s) => s.status, 'status', BookingStatus.idle)
          .having((s) => s.reserveSuccessToken, 'token', 1),
    ],
  );

  blocTest<BookingBloc, BookingState>(
    'an idempotent already-reserved 200 is treated as a reserve success',
    setUp: () => stubReserve(
      const SignupResult(signupId: 's1', alreadySignedUp: true),
    ),
    build: build,
    act: (b) => b.add(const BookingReserveRequested()),
    expect: () => [
      isA<BookingState>()
          .having((s) => s.status, 'status', BookingStatus.reserving),
      isA<BookingState>()
          .having((s) => s.booked, 'booked', true)
          .having((s) => s.reserveSuccessToken, 'token', 1),
    ],
  );

  blocTest<BookingBloc, BookingState>(
    'a full class surfaces the designed full-class error state',
    setUp: () {
      when(() => repo.reserve(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            classId: any(named: 'classId'),
            occurrenceDate: any(named: 'occurrenceDate'),
            occurrenceTime: any(named: 'occurrenceTime'),
          )).thenThrow(
        const ServerException(
          'Server error 400',
          statusCode: 400,
          detail: 'Class is full',
        ),
      );
    },
    build: build,
    act: (b) => b.add(const BookingReserveRequested()),
    expect: () => [
      isA<BookingState>()
          .having((s) => s.status, 'status', BookingStatus.reserving),
      isA<BookingState>()
          .having((s) => s.status, 'status', BookingStatus.error)
          .having((s) => s.fullClass, 'fullClass', true)
          .having((s) => s.errorMessage, 'errorMessage', 'Class is full')
          .having((s) => s.booked, 'booked', false),
    ],
  );
}
