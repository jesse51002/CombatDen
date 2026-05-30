// Mock data for the Members list screen.
//
// Each entry is a single gym member. Field names mirror what the real
// API will eventually return so the swap to a repository is mechanical.
// `lastClassDaysAgo` drives the green/yellow/red color in the "Last
// Class" column — the screen maps the bucket to a [DesignConstants]
// status color rather than baking the color into the data.

/// Membership lifecycle status. Drives any future status pill / filter
/// logic. Field names match what the API will hand us.
enum MemberStatus { active, frozen, unknown }

class Member {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final MemberStatus status;
  final int lastClassDaysAgo;

  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.status,
    required this.lastClassDaysAgo,
  });

  String get fullName => '$firstName $lastName';
}

/// High-level summary numbers shown under the page title. The real API
/// will return these as a single aggregate; for now they're hardcoded.
class MembersSummary {
  final int active;
  final int frozen;

  const MembersSummary({
    required this.active,
    required this.frozen,
  });
}

const MembersSummary kMockMembersSummary = MembersSummary(
  active: 85,
  frozen: 3,
);

/// ~20 members with intentionally varied names and recency buckets so the
/// design has texture to evaluate.
const List<Member> kMockMembers = [
  Member(
    id: 'm_001',
    firstName: 'Lily',
    lastName: 'Altega',
    email: 'lillymthree@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 3,
  ),
  Member(
    id: 'm_002',
    firstName: 'Ben',
    lastName: 'Ama',
    email: 'ben.ama@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 11,
  ),
  Member(
    id: 'm_003',
    firstName: 'Timothy',
    lastName: 'Tom',
    email: 'tim.tom@outlook.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 5,
  ),
  Member(
    id: 'm_004',
    firstName: 'Sylvia',
    lastName: 'Crivia',
    email: 'sylvia.crivia@protonmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 12,
  ),
  Member(
    id: 'm_005',
    firstName: 'Amy',
    lastName: 'Traver',
    email: 'amy.traver@gmail.com',
    status: MemberStatus.frozen,
    lastClassDaysAgo: 18,
  ),
  Member(
    id: 'm_006',
    firstName: 'Marcus',
    lastName: 'Pell',
    email: 'marcuspell@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 2,
  ),
  Member(
    id: 'm_007',
    firstName: 'Dion',
    lastName: 'Reyes',
    email: 'dion.reyes@hey.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 9,
  ),
  Member(
    id: 'm_008',
    firstName: 'Kim',
    lastName: 'Baranov',
    email: 'kim.b@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 5,
  ),
  Member(
    id: 'm_009',
    firstName: 'Priya',
    lastName: 'Shah',
    email: 'priya.shah@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 13,
  ),
  Member(
    id: 'm_010',
    firstName: 'Jordan',
    lastName: 'Vega',
    email: 'jvega@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 19,
  ),
  Member(
    id: 'm_011',
    firstName: 'Ravi',
    lastName: 'Okafor',
    email: 'ravi.okafor@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 1,
  ),
  Member(
    id: 'm_012',
    firstName: 'Nora',
    lastName: 'Linwood',
    email: 'nora.linwood@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 7,
  ),
  Member(
    id: 'm_013',
    firstName: 'Hugo',
    lastName: 'Marchetti',
    email: 'hugo.m@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 4,
  ),
  Member(
    id: 'm_014',
    firstName: 'Aiko',
    lastName: 'Tanaka',
    email: 'aiko.tanaka@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 14,
  ),
  Member(
    id: 'm_015',
    firstName: 'Diego',
    lastName: 'Salinas',
    email: 'diego.salinas@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 6,
  ),
  Member(
    id: 'm_016',
    firstName: 'Emma',
    lastName: 'Whitfield',
    email: 'emmawhit@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 21,
  ),
  Member(
    id: 'm_017',
    firstName: 'Owen',
    lastName: 'Brennan',
    email: 'owen.brennan@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 3,
  ),
  Member(
    id: 'm_018',
    firstName: 'Zara',
    lastName: 'Mehmood',
    email: 'zara.m@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 10,
  ),
  Member(
    id: 'm_019',
    firstName: 'Felix',
    lastName: 'Donovan',
    email: 'felix.donovan@gmail.com',
    status: MemberStatus.frozen,
    lastClassDaysAgo: 24,
  ),
  Member(
    id: 'm_020',
    firstName: 'Sana',
    lastName: 'Aldridge',
    email: 'sana.a@gmail.com',
    status: MemberStatus.active,
    lastClassDaysAgo: 8,
  ),
];
