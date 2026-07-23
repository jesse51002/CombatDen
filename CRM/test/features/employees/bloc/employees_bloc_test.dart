import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_create_request.dart';
import 'package:crm/features/employees/data/models/employee_update_request.dart';
import 'package:crm/features/employees/data/models/invite_status.dart';
import 'package:crm/features/employees/data/repositories/employees_repository.dart';
import 'package:crm/features/schedule/data/models/class_slot.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

class _MockEmployeesRepository extends Mock implements EmployeesRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _FakeEmployeeCreateRequest extends Fake
    implements EmployeeCreateRequest {}

class _FakeEmployeeUpdateData extends Fake implements EmployeeUpdateData {}

Employee _employee(
  String id,
  EmployeeRole role, {
  String firstName = 'Jane',
  String lastName = 'Doe',
}) =>
    Employee(
      employeeId: id,
      gymId: 'gym-1',
      employeeType: role,
      firstName: firstName,
      lastName: lastName,
      email: '${firstName.toLowerCase()}@example.com',
      createdAt: DateTime(2026, 1, 1),
      inviteStatus: InviteStatus.active,
    );

final _boxingClass = GymClassResponse(
  classId: 'class-1',
  gymId: 'gym-1',
  className: 'Boxing',
  durationMinutes: 60,
  recurringUnit: RecurringUnit.weekly,
  recurringInterval: 1,
  weekdaySlots: const {
    'mon': [ClassSlot(time: '18:00:00', instructorId: 'emp-1')],
  },
  startDate: DateTime(2026, 1, 1),
  pointsWorth: 10,
  isActive: true,
  isDeleted: false,
  createdAt: DateTime(2026, 1, 1),
);

const _createReq = EmployeeCreateRequest(
  employeeType: EmployeeRole.trainer,
  firstName: 'New',
  lastName: 'Hire',
  email: 'new.hire@example.com',
);

void main() {
  late _MockEmployeesRepository employeesRepo;
  late _MockScheduleRepository scheduleRepo;

  setUpAll(() {
    registerFallbackValue(_FakeEmployeeCreateRequest());
    registerFallbackValue(_FakeEmployeeUpdateData());
  });

  setUp(() {
    employeesRepo = _MockEmployeesRepository();
    scheduleRepo = _MockScheduleRepository();
  });

  EmployeesBloc build() => EmployeesBloc(
        employeesRepository: employeesRepo,
        scheduleRepository: scheduleRepo,
      );

  EmployeesLoaded loaded({
    List<Employee> employees = const [],
    String query = '',
    EmployeeRole? roleFilter,
  }) =>
      EmployeesLoaded(
        gymId: 'gym-1',
        employees: employees,
        visibleEmployees: employees,
        query: query,
        roleFilter: roleFilter,
      );

  group('EmployeesBloc init', () {
    blocTest<EmployeesBloc, EmployeesState>(
      'loads the roster and the gym classes, merging '
      'taughtByEmployeeId from the two',
      setUp: () {
        when(() => employeesRepo.listEmployees('gym-1')).thenAnswer(
          (_) async => [_employee('emp-1', EmployeeRole.trainer)],
        );
        when(() => scheduleRepo.listClasses('gym-1'))
            .thenAnswer((_) async => [_boxingClass]);
      },
      build: build,
      act: (b) => b.add(const EmployeesInitRequested('gym-1')),
      expect: () => [
        const EmployeesLoading(),
        isA<EmployeesLoaded>()
            .having((s) => s.employees, 'employees', hasLength(1))
            .having(
              (s) => s.classesLoadFailed,
              'classesLoadFailed',
              isFalse,
            )
            .having(
              (s) => s.taughtByEmployeeId.keys,
              'taughtByEmployeeId keys',
              contains('emp-1'),
            )
            .having(
              (s) => s.taughtByEmployeeId['emp-1']!.single.className,
              'emp-1 teaches Boxing',
              'Boxing',
            ),
      ],
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'a classes-load failure is non-fatal: the roster still loads with '
      'classesLoadFailed true and an empty taughtByEmployeeId',
      setUp: () {
        when(() => employeesRepo.listEmployees('gym-1')).thenAnswer(
          (_) async => [_employee('emp-1', EmployeeRole.trainer)],
        );
        when(() => scheduleRepo.listClasses('gym-1'))
            .thenThrow(Exception('classes boom'));
      },
      build: build,
      act: (b) => b.add(const EmployeesInitRequested('gym-1')),
      expect: () => [
        const EmployeesLoading(),
        isA<EmployeesLoaded>()
            .having((s) => s.employees, 'employees', hasLength(1))
            .having(
              (s) => s.classesLoadFailed,
              'classesLoadFailed',
              isTrue,
            )
            .having(
              (s) => s.taughtByEmployeeId,
              'taughtByEmployeeId',
              isEmpty,
            ),
      ],
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'a roster-load failure is fatal: emits EmployeesError',
      setUp: () {
        when(() => employeesRepo.listEmployees('gym-1'))
            .thenThrow(Exception('roster boom'));
        when(() => scheduleRepo.listClasses('gym-1'))
            .thenAnswer((_) async => const []);
      },
      build: build,
      act: (b) => b.add(const EmployeesInitRequested('gym-1')),
      expect: () => [
        const EmployeesLoading(),
        isA<EmployeesError>().having((s) => s.gymId, 'gymId', 'gym-1'),
      ],
    );
  });

  group('EmployeesBloc search + role filter', () {
    blocTest<EmployeesBloc, EmployeesState>(
      'search narrows visibleEmployees client-side (debounced)',
      build: build,
      seed: () => loaded(
        employees: [
          _employee('emp-1', EmployeeRole.trainer, firstName: 'Alice'),
          _employee('emp-2', EmployeeRole.frontDesk, firstName: 'Bob'),
        ],
      ),
      act: (b) => b.add(const EmployeesSearchChanged('ali')),
      wait: const Duration(milliseconds: 350),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.query, 'query', 'ali')
            .having(
              (s) => s.visibleEmployees.map((e) => e.employeeId),
              'visibleEmployees',
              ['emp-1'],
            ),
      ],
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'the role filter narrows visibleEmployees client-side',
      build: build,
      seed: () => loaded(
        employees: [
          _employee('emp-1', EmployeeRole.trainer),
          _employee('emp-2', EmployeeRole.frontDesk),
        ],
      ),
      act: (b) => b.add(
        const EmployeesRoleFilterChanged(EmployeeRole.frontDesk),
      ),
      expect: () => [
        isA<EmployeesLoaded>()
            .having(
              (s) => s.roleFilter,
              'roleFilter',
              EmployeeRole.frontDesk,
            )
            .having(
              (s) => s.visibleEmployees.map((e) => e.employeeId),
              'visibleEmployees',
              ['emp-2'],
            ),
      ],
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'clearing the role filter (null / the "All" pill) restores '
      'every employee to visibleEmployees',
      build: build,
      seed: () => loaded(
        employees: [
          _employee('emp-1', EmployeeRole.trainer),
          _employee('emp-2', EmployeeRole.frontDesk),
        ],
        roleFilter: EmployeeRole.frontDesk,
      ),
      act: (b) => b.add(const EmployeesRoleFilterChanged(null)),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.roleFilter, 'roleFilter', isNull)
            .having(
              (s) => s.visibleEmployees,
              'visibleEmployees',
              hasLength(2),
            ),
      ],
    );
  });

  group('EmployeesBloc invite', () {
    blocTest<EmployeesBloc, EmployeesState>(
      'a successful invite bumps inviteSuccess, records '
      'lastInvitedEmployee, and reloads the roster',
      setUp: () {
        when(() => employeesRepo.createEmployee('gym-1', any())).thenAnswer(
          (_) async => _employee('emp-new', EmployeeRole.trainer),
        );
        when(() => employeesRepo.listEmployees('gym-1')).thenAnswer(
          (_) async => [_employee('emp-new', EmployeeRole.trainer)],
        );
      },
      build: build,
      seed: () => loaded(),
      act: (b) => b.add(const EmployeeInviteSubmitted(_createReq)),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isTrue),
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isFalse)
            .having((s) => s.inviteSuccess, 'inviteSuccess', 1)
            .having(
              (s) => s.lastInvitedEmployee?.employeeId,
              'lastInvitedEmployee',
              'emp-new',
            )
            .having((s) => s.employees, 'employees', hasLength(1)),
      ],
      verify: (_) {
        verify(() => employeesRepo.createEmployee('gym-1', any())).called(1);
      },
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'a failed invite sets mutationError, does NOT bump inviteSuccess, '
      'and leaves the roster untouched',
      setUp: () {
        when(() => employeesRepo.createEmployee('gym-1', any()))
            .thenThrow(Exception('duplicate email'));
      },
      build: build,
      seed: () => loaded(
        employees: [_employee('emp-1', EmployeeRole.trainer)],
      ),
      act: (b) => b.add(const EmployeeInviteSubmitted(_createReq)),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isTrue),
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isFalse)
            .having((s) => s.mutationError, 'mutationError', isNotNull)
            .having((s) => s.inviteSuccess, 'inviteSuccess', 0)
            .having((s) => s.employees, 'employees', hasLength(1)),
      ],
      verify: (_) {
        // The failed create() short-circuits _runMutation before it ever
        // reaches the roster reload.
        verifyNever(() => employeesRepo.listEmployees(any()));
      },
    );
  });

  group('EmployeesBloc update', () {
    blocTest<EmployeesBloc, EmployeesState>(
      'a successful update bumps updateSuccess and reloads the roster',
      setUp: () {
        when(
          () => employeesRepo.updateEmployee('gym-1', 'emp-1', any()),
        ).thenAnswer((_) async => _employee('emp-1', EmployeeRole.admin));
        when(() => employeesRepo.listEmployees('gym-1')).thenAnswer(
          (_) async => [_employee('emp-1', EmployeeRole.admin)],
        );
      },
      build: build,
      seed: () => loaded(
        employees: [_employee('emp-1', EmployeeRole.trainer)],
      ),
      act: (b) => b.add(
        const EmployeeUpdateSubmitted(
          'emp-1',
          EmployeeUpdateData(employeeType: EmployeeRole.admin),
        ),
      ),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isTrue),
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isFalse)
            .having((s) => s.updateSuccess, 'updateSuccess', 1)
            .having(
              (s) => s.employees.single.employeeType,
              'updated role',
              EmployeeRole.admin,
            ),
      ],
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'a failed update sets mutationError and does NOT bump updateSuccess',
      setUp: () {
        when(
          () => employeesRepo.updateEmployee('gym-1', 'emp-1', any()),
        ).thenThrow(Exception('server error'));
      },
      build: build,
      seed: () => loaded(
        employees: [_employee('emp-1', EmployeeRole.trainer)],
      ),
      act: (b) => b.add(
        const EmployeeUpdateSubmitted(
          'emp-1',
          EmployeeUpdateData(employeeType: EmployeeRole.admin),
        ),
      ),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isTrue),
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isFalse)
            .having((s) => s.mutationError, 'mutationError', isNotNull)
            .having((s) => s.updateSuccess, 'updateSuccess', 0),
      ],
    );
  });

  group('EmployeesBloc remove', () {
    blocTest<EmployeesBloc, EmployeesState>(
      'a successful remove bumps removeSuccess and reloads the roster',
      setUp: () {
        when(() => employeesRepo.deleteEmployee('gym-1', 'emp-1'))
            .thenAnswer((_) async {});
        when(() => employeesRepo.listEmployees('gym-1'))
            .thenAnswer((_) async => const []);
      },
      build: build,
      seed: () => loaded(
        employees: [_employee('emp-1', EmployeeRole.trainer)],
      ),
      act: (b) => b.add(const EmployeeRemoveRequested('emp-1')),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isTrue),
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isFalse)
            .having((s) => s.removeSuccess, 'removeSuccess', 1)
            .having((s) => s.employees, 'employees', isEmpty),
      ],
    );

    blocTest<EmployeesBloc, EmployeesState>(
      'a failed remove sets mutationError and does NOT bump removeSuccess',
      setUp: () {
        when(() => employeesRepo.deleteEmployee('gym-1', 'emp-1'))
            .thenThrow(Exception('cannot remove'));
      },
      build: build,
      seed: () => loaded(
        employees: [_employee('emp-1', EmployeeRole.trainer)],
      ),
      act: (b) => b.add(const EmployeeRemoveRequested('emp-1')),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isTrue),
        isA<EmployeesLoaded>()
            .having((s) => s.isMutating, 'isMutating', isFalse)
            .having((s) => s.mutationError, 'mutationError', isNotNull)
            .having((s) => s.removeSuccess, 'removeSuccess', 0)
            .having((s) => s.employees, 'employees', hasLength(1)),
      ],
    );
  });

  group('EmployeesBloc mutation outcome clear', () {
    blocTest<EmployeesBloc, EmployeesState>(
      'clears a lingering mutationError without touching anything else',
      build: build,
      seed: () => loaded(
        employees: [_employee('emp-1', EmployeeRole.trainer)],
      ).copyWith(mutationError: 'stale error'),
      act: (b) => b.add(const EmployeesMutationOutcomeCleared()),
      expect: () => [
        isA<EmployeesLoaded>()
            .having((s) => s.mutationError, 'mutationError', isNull)
            .having((s) => s.employees, 'employees', hasLength(1)),
      ],
    );
  });
}
