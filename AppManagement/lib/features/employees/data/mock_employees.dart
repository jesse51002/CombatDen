import 'package:flutter/foundation.dart';

/// Mock staff directory for the Employees prototype.
///
/// Field names mirror the eventual `gym_employees` table (first_name,
/// last_name, employee_pic_url, employee_type, …) so the swap to a repository
/// is mechanical. The four coach headshots are the real shared instructor
/// roster the VideoService serves with each gym — reused here as hardcoded
/// network urls so the directory shows real faces without widening the live
/// carve-out. Front-of-house staff carry no photo, so their avatars fall back
/// to initials (the common real-world case where someone hasn't uploaded one).

/// Staff role on `gym_employees.employee_type`. The API hands these to us
/// lowercase; [label] capitalizes for display. Richer than the schedule
/// feature's minimal `EmployeeType` — this is the canonical staff directory.
enum EmployeeRole {
  owner,
  manager,
  headCoach,
  coach,
  frontDesk,
  admin,
  unknown;

  String get label {
    switch (this) {
      case EmployeeRole.owner:
        return 'Owner';
      case EmployeeRole.manager:
        return 'Manager';
      case EmployeeRole.headCoach:
        return 'Head Coach';
      case EmployeeRole.coach:
        return 'Coach';
      case EmployeeRole.frontDesk:
        return 'Front Desk';
      case EmployeeRole.admin:
        return 'Admin';
      case EmployeeRole.unknown:
        return 'Staff';
    }
  }

  /// Coaching roles drive the retention engine (classes, attendance), so the
  /// detail page surfaces their teaching stats; support staff hide them.
  bool get coaches =>
      this == EmployeeRole.owner ||
      this == EmployeeRole.headCoach ||
      this == EmployeeRole.coach;
}

/// One class session an employee leads, with its day + time slot.
@immutable
class TaughtClass {
  final String name;
  final String schedule;

  const TaughtClass({required this.name, required this.schedule});
}

@immutable
class Employee {
  final String id;
  final String firstName;
  final String lastName;
  final EmployeeRole role;

  /// Network headshot url (the gym's instructor photo). Null when the employee
  /// has no picture on file — the avatar falls back to initials.
  final String? photoUrl;

  final String email;
  final String phone;
  final String joinedLabel;
  final String tenureLabel;
  final String employmentLabel;
  final String bio;

  /// Coaching detail — empty / null for support staff.
  final List<TaughtClass> classesTaught;
  final int? classesPerWeek;
  final int? membersCoached;
  final int? avgClassSize;

  const Employee({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.photoUrl,
    required this.email,
    required this.phone,
    required this.joinedLabel,
    required this.tenureLabel,
    required this.employmentLabel,
    required this.bio,
    this.classesTaught = const [],
    this.classesPerWeek,
    this.membersCoached,
    this.avgClassSize,
  });

  String get fullName => '$firstName $lastName';
  bool get coaches => role.coaches;
}

/// Expands a coach's weekly lineup (each class run across several day/time
/// slots) into one [TaughtClass] per session, so the "Classes taught" list
/// runs long and realistic — coaches repeat each class many times a week.
List<TaughtClass> _sessions(List<(String, List<String>)> lineup) {
  return [
    for (final (name, slots) in lineup)
      for (final slot in slots) TaughtClass(name: name, schedule: slot),
  ];
}

final List<TaughtClass> _jamesClasses = _sessions(const [
  (
    'Fundamentals BJJ',
    ['Mon — 6:00 AM', 'Mon — 6:00 PM', 'Wed — 6:00 AM', 'Wed — 6:00 PM',
        'Fri — 6:00 PM'],
  ),
  ('Competition Team', ['Tue — 7:30 PM', 'Thu — 7:30 PM', 'Sat — 1:00 PM']),
  ('Advanced No-Gi', ['Tue — 12:00 PM', 'Thu — 12:00 PM']),
  ('Open Mat', ['Sat — 10:00 AM', 'Sun — 10:00 AM']),
  ('Private Lessons', ['Mon — 8:00 AM', 'Wed — 8:00 AM', 'Fri — 8:00 AM']),
  ('Wrestling for BJJ', ['Thu — 6:00 PM']),
]);

final List<TaughtClass> _sarahClasses = _sessions(const [
  ('Strength Foundations', ['Mon — 12:00 PM', 'Thu — 12:00 PM', 'Sat — 9:00 AM']),
  ('Conditioning', ['Wed — 5:30 PM', 'Fri — 5:30 PM']),
  ('Mobility Reset', ['Sun — 9:00 AM', 'Tue — 7:00 AM']),
  ('Kettlebell Circuit', ['Mon — 5:30 PM', 'Wed — 7:00 AM']),
  ('Comp Strength Block', ['Tue — 6:00 PM', 'Thu — 6:00 PM']),
  ('Intro to Barbell', ['Sat — 11:00 AM']),
  ('Recovery & Stretch', ['Sun — 11:00 AM']),
]);

final List<TaughtClass> _danielClasses = _sessions(const [
  ('Muay Thai Fundamentals', ['Tue — 6:30 PM', 'Thu — 6:30 PM']),
  ('Beginner Striking', ['Sat — 11:00 AM', 'Sun — 11:00 AM']),
  ('Pad Work', ['Tue — 7:30 PM', 'Thu — 7:30 PM']),
  ('Clinch & Knees', ['Wed — 6:30 PM']),
  ('Kids Kickboxing', ['Mon — 4:30 PM', 'Wed — 4:30 PM', 'Fri — 4:30 PM']),
]);

final List<TaughtClass> _mayaClasses = _sessions(const [
  ('Boxing Basics', ['Mon — 7:00 PM', 'Wed — 7:00 PM']),
  ('HIIT Rounds', ['Fri — 6:00 PM', 'Sat — 9:00 AM']),
  ('Sparring Class', ['Tue — 7:00 PM', 'Thu — 7:00 PM']),
  ('Footwork & Defense', ['Wed — 12:00 PM']),
  ('Conditioning for Fighters', ['Mon — 6:00 AM', 'Fri — 6:00 AM']),
  ('Open Gym', ['Sun — 10:00 AM']),
]);

final Employee _james = Employee(
  id: 'emp_001',
  firstName: 'James',
  lastName: 'Carter',
  role: EmployeeRole.owner,
  photoUrl:
      'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
  email: 'james@apexmma.com',
  phone: '(415) 555-0142',
  joinedLabel: 'March 2018',
  tenureLabel: '7 yrs',
  employmentLabel: 'Full-time · Owner',
  bio:
      'Founded the gym in 2018 and still coaches most mornings. A decade-plus '
      'on the mats helping members of every level train smarter, move better, '
      'and stay consistent — and the one who sets the tone for the room.',
  classesTaught: _jamesClasses,
  classesPerWeek: 16,
  membersCoached: 96,
  avgClassSize: 19,
);

final Employee _sarah = Employee(
  id: 'emp_002',
  firstName: 'Sarah',
  lastName: 'Mitchell',
  role: EmployeeRole.headCoach,
  photoUrl:
      'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
  email: 'sarah@apexmma.com',
  phone: '(415) 555-0188',
  joinedLabel: 'August 2020',
  tenureLabel: '4 yrs',
  employmentLabel: 'Full-time',
  bio:
      'Performance coach focused on building strength, mobility, and '
      'confidence through approachable, well-structured sessions. Runs the '
      'strength program and writes the conditioning blocks for the comp team.',
  classesTaught: _sarahClasses,
  classesPerWeek: 13,
  membersCoached: 74,
  avgClassSize: 16,
);

final Employee _daniel = Employee(
  id: 'emp_003',
  firstName: 'Daniel',
  lastName: 'Brooks',
  role: EmployeeRole.coach,
  photoUrl:
      'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
  email: 'daniel@apexmma.com',
  phone: '(415) 555-0157',
  joinedLabel: 'January 2022',
  tenureLabel: '3 yrs',
  employmentLabel: 'Part-time',
  bio:
      'Certified instructor who breaks every movement down step by step so '
      'newcomers and regulars alike feel supported. The coach beginners are '
      'most often handed off to on their first week.',
  classesTaught: _danielClasses,
  classesPerWeek: 10,
  membersCoached: 51,
  avgClassSize: 14,
);

final Employee _maya = Employee(
  id: 'emp_004',
  firstName: 'Maya',
  lastName: 'Bennett',
  role: EmployeeRole.coach,
  photoUrl:
      'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
  email: 'maya@apexmma.com',
  phone: '(415) 555-0173',
  joinedLabel: 'September 2021',
  tenureLabel: '3 yrs',
  employmentLabel: 'Full-time',
  bio:
      'Coach passionate about creating an inclusive, high-energy room where '
      'members from all backgrounds can thrive, with a focus on bringing '
      'newer members into the boxing program.',
  classesTaught: _mayaClasses,
  classesPerWeek: 10,
  membersCoached: 63,
  avgClassSize: 17,
);

const Employee _priya = Employee(
  id: 'emp_005',
  firstName: 'Priya',
  lastName: 'Nair',
  role: EmployeeRole.manager,
  email: 'priya@apexmma.com',
  phone: '(415) 555-0109',
  joinedLabel: 'February 2022',
  tenureLabel: '3 yrs',
  employmentLabel: 'Full-time',
  bio:
      'Runs the business side — memberships, billing questions, and the class '
      'schedule — and keeps the front-of-house running so the coaches can stay '
      'on the floor.',
);

const Employee _elena = Employee(
  id: 'emp_006',
  firstName: 'Elena',
  lastName: 'Rossi',
  role: EmployeeRole.frontDesk,
  email: 'elena@apexmma.com',
  phone: '(415) 555-0120',
  joinedLabel: 'May 2023',
  tenureLabel: '2 yrs',
  employmentLabel: 'Full-time',
  bio:
      'First face members see at the door — handles check-ins, sign-ups, and '
      'the day-to-day questions so the floor stays focused on training.',
);

final List<Employee> kMockEmployees = [
  _james,
  _sarah,
  _daniel,
  _maya,
  _priya,
  _elena,
];

/// Headline counts for the Employees list subtitle.
@immutable
class EmployeesSummary {
  final int total;
  final int coaches;

  const EmployeesSummary({required this.total, required this.coaches});
}

EmployeesSummary buildEmployeesSummary(List<Employee> employees) {
  return EmployeesSummary(
    total: employees.length,
    coaches: employees.where((e) => e.coaches).length,
  );
}
