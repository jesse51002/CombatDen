import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_bloc.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_event.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_state.dart';
import 'package:mobile_app/features/class_booking/data/booking_rejection.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/models/signup_result.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/home/data/repositories/member_signup_repository.dart';

class _MockSignupRepo extends Mock implements MemberSignupRepository {}

class _MockHistoryRepo extends Mock implements MemberClassHistoryRepository {}

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

/// A reservation row for the occurrence under test (matching slot key), or a
/// different slot when [slot] is overridden.
MemberClassHistoryRow _reservation({
  String classId = 'c1',
  String originalDate = '2026-07-23',
  String originalTime = '18:00:00',
}) =>
    MemberClassHistoryRow(
      classId: classId,
      className: 'Muay Thai',
      imageUrl: 'https://x/i.png',
      originalDate: originalDate,
      originalTime: originalTime,
      durationMinutes: 55,
      status: MemberClassHistoryStatus.reserved,
    );

MemberClassHistory _history(List<MemberClassHistoryRow> upcoming) =>
    MemberClassHistory(upcoming: upcoming, history: const [], hasMore: false);

/// The wire shape of a typed check-in rejection: a plain-string `detail` with
/// the machine-readable `code` as its SIBLING.
ServerException _rejection({
  required String detail,
  String? code,
  int statusCode = 400,
}) =>
    ServerException(
      'Server error $statusCode',
      statusCode: statusCode,
      detail: detail,
      data: {
        'detail': detail,
        'code': ?code,
      },
    );

void main() {
  late _MockSignupRepo repo;
  late _MockHistoryRepo historyRepo;

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
    historyRepo = _MockHistoryRepo();
  });

  tearDown(() async {
    await selectedMember.reset();
  });

  BookingBloc build({bool booked = false}) => BookingBloc(
        repository: repo,
        historyRepository: historyRepo,
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

  void throwOnReserve(Object error) {
    when(() => repo.reserve(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          classId: any(named: 'classId'),
          occurrenceDate: any(named: 'occurrenceDate'),
          occurrenceTime: any(named: 'occurrenceTime'),
        )).thenThrow(error);
  }

  void throwOnCancel(Object error) {
    when(() => repo.cancel(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          classId: any(named: 'classId'),
          occurrenceDate: any(named: 'occurrenceDate'),
          occurrenceTime: any(named: 'occurrenceTime'),
        )).thenThrow(error);
  }

  void stubHistory(MemberClassHistory result) {
    when(() => historyRepo.getHistory(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
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

  group('a rejection is classified by its code, never by its message', () {
    // The full contract, verbatim from CheckinErrorCode: the six rejections
    // POST /signup can raise, their backend prose, and the member-facing copy
    // each must produce.
    const cases = <({
      String code,
      String detail,
      int statusCode,
      BookingRejection rejection,
      String message,
    })>[
      (
        code: 'class_full',
        detail: 'Class is full',
        statusCode: 400,
        rejection: BookingRejection.classFull,
        message: 'This class is full. Try another time.',
      ),
      (
        code: 'occurrence_cancelled',
        detail: 'This class is cancelled that day',
        statusCode: 400,
        rejection: BookingRejection.occurrenceCancelled,
        message: 'This class is cancelled that day.',
      ),
      (
        code: 'class_inactive',
        detail: 'Class is not active',
        statusCode: 400,
        rejection: BookingRejection.classInactive,
        message: 'This class is not running right now.',
      ),
      (
        code: 'class_deleted',
        detail: 'Class has been deleted',
        statusCode: 400,
        rejection: BookingRejection.classDeleted,
        message: 'This class is no longer on the schedule.',
      ),
      (
        code: 'occurrence_not_found',
        detail: 'Not a class occurrence on that date',
        statusCode: 400,
        rejection: BookingRejection.occurrenceNotFound,
        message: 'This class is not scheduled at that time anymore.',
      ),
      (
        code: 'class_not_found',
        detail: 'Class not found',
        statusCode: 404,
        rejection: BookingRejection.classNotFound,
        message: 'We cannot find this class anymore.',
      ),
    ];

    for (final c in cases) {
      blocTest<BookingBloc, BookingState>(
        '${c.code} -> its own member-facing copy',
        setUp: () => throwOnReserve(_rejection(
          detail: c.detail,
          code: c.code,
          statusCode: c.statusCode,
        )),
        build: build,
        act: (b) => b.add(const BookingReserveRequested()),
        skip: 1,
        expect: () => [
          isA<BookingState>()
              .having((s) => s.status, 'status', BookingStatus.error)
              .having((s) => s.rejection, 'rejection', c.rejection)
              .having((s) => s.errorMessage, 'errorMessage', c.message)
              .having(
                (s) => s.fullClass,
                'fullClass',
                c.rejection == BookingRejection.classFull,
              )
              .having((s) => s.booked, 'booked', false),
        ],
      );
    }

    blocTest<BookingBloc, BookingState>(
      'a REWORDED full-class message still trips the full state via its code',
      // The exact regression the old `detail.contains("full")` sniff would
      // cause: the backend may reword `detail` freely, the code may not move.
      setUp: () => throwOnReserve(_rejection(
        detail: 'Every spot for this session has been taken',
        code: 'class_full',
      )),
      build: build,
      act: (b) => b.add(const BookingReserveRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>()
            .having((s) => s.fullClass, 'fullClass', true)
            .having((s) => s.rejection, 'rejection', BookingRejection.classFull)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              'This class is full. Try another time.',
            ),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a message containing "full" under a DIFFERENT code is not full-class',
      // The other half of the sniff bug: prose that happens to say "full".
      setUp: () => throwOnReserve(_rejection(
        detail: 'Class is not active — the full schedule is paused',
        code: 'class_inactive',
      )),
      build: build,
      act: (b) => b.add(const BookingReserveRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>()
            .having((s) => s.fullClass, 'fullClass', false)
            .having(
              (s) => s.rejection,
              'rejection',
              BookingRejection.classInactive,
            )
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              'This class is not running right now.',
            ),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'an UNKNOWN code falls back to the backend detail',
      setUp: () => throwOnReserve(_rejection(
        detail: 'Sign-ups close 10 minutes before the class starts',
        code: 'signup_window_closed',
      )),
      build: build,
      act: (b) => b.add(const BookingReserveRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>()
            .having((s) => s.rejection, 'rejection', BookingRejection.unknown)
            .having((s) => s.fullClass, 'fullClass', false)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              'Sign-ups close 10 minutes before the class starts',
            ),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a rejection with NO code at all still falls back to the detail',
      // The backend's generic `except ValueError -> 400` arm emits no code.
      setUp: () => throwOnReserve(_rejection(detail: 'Bad request')),
      build: build,
      act: (b) => b.add(const BookingReserveRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>()
            .having((s) => s.rejection, 'rejection', BookingRejection.unknown)
            .having((s) => s.errorMessage, 'errorMessage', 'Bad request'),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'no code and no detail still shows a message, never a blank error',
      setUp: () => throwOnReserve(
        const ServerException('Server error 500', statusCode: 500),
      ),
      build: build,
      act: (b) => b.add(const BookingReserveRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>().having(
          (s) => s.errorMessage,
          'errorMessage',
          'Could not reserve your spot. Please try again.',
        ),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a cancel rejection runs through the same code mapping',
      setUp: () => throwOnCancel(_rejection(
        detail: 'Class not found',
        code: 'class_not_found',
        statusCode: 404,
      )),
      build: () => build(booked: true),
      act: (b) => b.add(const BookingCancelRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>()
            .having((s) => s.status, 'status', BookingStatus.error)
            .having(
              (s) => s.rejection,
              'rejection',
              BookingRejection.classNotFound,
            )
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              'We cannot find this class anymore.',
            )
            .having((s) => s.booked, 'booked', true),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a cancel failure with no code falls back to the cancel wording',
      setUp: () => throwOnCancel(
        const ServerException('Server error 500', statusCode: 500),
      ),
      build: () => build(booked: true),
      act: (b) => b.add(const BookingCancelRequested()),
      skip: 1,
      expect: () => [
        isA<BookingState>().having(
          (s) => s.errorMessage,
          'errorMessage',
          'Could not cancel. Please try again.',
        ),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a fresh reserve clears the previous rejection',
      setUp: () {
        throwOnReserve(_rejection(detail: 'Class is full', code: 'class_full'));
      },
      build: build,
      act: (b) => b.add(const BookingReserveRequested()),
      expect: () => [
        isA<BookingState>()
            .having((s) => s.status, 'status', BookingStatus.reserving)
            .having((s) => s.rejection, 'rejection', BookingRejection.unknown)
            .having((s) => s.fullClass, 'fullClass', false),
        isA<BookingState>().having((s) => s.fullClass, 'fullClass', true),
      ],
    );
  });

  group('the screen confirms booked against the member\'s own reservations',
      () {
    blocTest<BookingBloc, BookingState>(
      'a WRONG false seed is corrected to booked',
      // The bug: any route that does not set ClassDetailArgs.booked correctly
      // showed "Reserve" for a class the member already holds.
      setUp: () => stubHistory(_history([_reservation()])),
      build: () => build(booked: false),
      act: (b) => b.add(const BookingReservationSyncRequested()),
      expect: () => [
        isA<BookingState>().having((s) => s.booked, 'booked', true),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a WRONG true seed is corrected to not booked',
      setUp: () => stubHistory(_history(const [])),
      build: () => build(booked: true),
      act: (b) => b.add(const BookingReservationSyncRequested()),
      expect: () => [
        isA<BookingState>().having((s) => s.booked, 'booked', false),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'a reservation for a DIFFERENT slot of the same class does not count',
      setUp: () => stubHistory(
        _history([_reservation(originalTime: '19:30:00')]),
      ),
      build: () => build(booked: false),
      act: (b) => b.add(const BookingReservationSyncRequested()),
      expect: () => <BookingState>[],
    );

    blocTest<BookingBloc, BookingState>(
      'a correct seed emits nothing (no needless rebuild)',
      setUp: () => stubHistory(_history([_reservation()])),
      build: () => build(booked: true),
      act: (b) => b.add(const BookingReservationSyncRequested()),
      expect: () => <BookingState>[],
    );

    blocTest<BookingBloc, BookingState>(
      'a failed confirm keeps the seed and surfaces no error',
      setUp: () {
        when(() => historyRepo.getHistory(
              gymId: any(named: 'gymId'),
              memberId: any(named: 'memberId'),
            )).thenThrow(const NetworkException('offline'));
      },
      build: () => build(booked: true),
      act: (b) => b.add(const BookingReservationSyncRequested()),
      expect: () => <BookingState>[],
      verify: (b) {
        expect(b.state.booked, isTrue);
        expect(b.state.status, BookingStatus.idle);
        expect(b.state.errorMessage, isNull);
      },
    );

    blocTest<BookingBloc, BookingState>(
      'a late confirm never undoes a cancel the member just made',
      setUp: () {
        when(() => repo.cancel(
              gymId: any(named: 'gymId'),
              memberId: any(named: 'memberId'),
              classId: any(named: 'classId'),
              occurrenceDate: any(named: 'occurrenceDate'),
              occurrenceTime: any(named: 'occurrenceTime'),
            )).thenAnswer(
          (_) async => const SignupRemoveResult(removed: true),
        );
        // The read was in flight while they cancelled, so it still says
        // "reserved".
        stubHistory(_history([_reservation()]));
      },
      build: () => build(booked: true),
      act: (b) async {
        b.add(const BookingCancelRequested());
        await Future<void>.delayed(Duration.zero);
        b.add(const BookingReservationSyncRequested());
      },
      verify: (b) {
        expect(b.state.booked, isFalse);
        expect(b.state.cancelSuccessToken, 1);
      },
    );
  });
}
