// Mock data for the Members list screen.
//
// Each entry is a single gym member. Field names mirror what the real
// API will eventually return so the swap to a repository is mechanical.
// `lastClassDaysAgo` drives the green/yellow/red color in the "Last
// Class" column — the screen maps the bucket to a [DesignConstants]
// status color rather than baking the color into the data.

/// Loyalty/skill rank for a member. Rendered with a belt icon next to
/// the label.
enum MemberRank { silver, gold, bronze, unknown }

/// Membership lifecycle status. Drives any future status pill / filter
/// logic. Field names match what the API will hand us.
enum MemberStatus { active, trial, frozen, unknown }

class Member {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String avatarAsset;
  final MemberRank rank;
  final MemberStatus status;
  final int lastClassDaysAgo;

  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.avatarAsset,
    required this.rank,
    required this.status,
    required this.lastClassDaysAgo,
  });

  String get fullName => '$firstName $lastName';
}

/// High-level summary numbers shown under the page title. The real API
/// will return these as a single aggregate; for now they're hardcoded.
class MembersSummary {
  final int active;
  final int trial;
  final int frozen;

  const MembersSummary({
    required this.active,
    required this.trial,
    required this.frozen,
  });
}

const MembersSummary kMockMembersSummary = MembersSummary(
  active: 85,
  trial: 6,
  frozen: 3,
);

/// ~20 members with intentionally varied names, ranks, and recency
/// buckets so the design has texture to evaluate.
const List<Member> kMockMembers = [
  Member(
    id: 'm_001',
    firstName: 'Lily',
    lastName: 'Altega',
    email: 'lillymthree@gmail.com',
    avatarAsset: 'assets/images/pfp_lily_altega.png',
    rank: MemberRank.silver,
    status: MemberStatus.active,
    lastClassDaysAgo: 3,
  ),
  Member(
    id: 'm_002',
    firstName: 'Ben',
    lastName: 'Ama',
    email: 'ben.ama@gmail.com',
    avatarAsset: 'assets/images/pfp_ben_ama.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 11,
  ),
  Member(
    id: 'm_003',
    firstName: 'Timothy',
    lastName: 'Tom',
    email: 'tim.tom@outlook.com',
    avatarAsset: 'assets/images/pfp_timothy_tom.png',
    rank: MemberRank.bronze,
    status: MemberStatus.active,
    lastClassDaysAgo: 5,
  ),
  Member(
    id: 'm_004',
    firstName: 'Sylvia',
    lastName: 'Crivia',
    email: 'sylvia.crivia@protonmail.com',
    avatarAsset: 'assets/images/pfp_sylvia_crivia.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 12,
  ),
  Member(
    id: 'm_005',
    firstName: 'Amy',
    lastName: 'Traver',
    email: 'amy.traver@gmail.com',
    avatarAsset: 'assets/images/pfp_amy_traver.png',
    rank: MemberRank.bronze,
    status: MemberStatus.frozen,
    lastClassDaysAgo: 18,
  ),
  Member(
    id: 'm_006',
    firstName: 'Marcus',
    lastName: 'Pell',
    email: 'marcuspell@gmail.com',
    avatarAsset: 'assets/images/pfp_lily_altega.png',
    rank: MemberRank.silver,
    status: MemberStatus.active,
    lastClassDaysAgo: 2,
  ),
  Member(
    id: 'm_007',
    firstName: 'Dion',
    lastName: 'Reyes',
    email: 'dion.reyes@hey.com',
    avatarAsset: 'assets/images/pfp_ben_ama.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 9,
  ),
  Member(
    id: 'm_008',
    firstName: 'Kim',
    lastName: 'Baranov',
    email: 'kim.b@gmail.com',
    avatarAsset: 'assets/images/pfp_timothy_tom.png',
    rank: MemberRank.bronze,
    status: MemberStatus.trial,
    lastClassDaysAgo: 5,
  ),
  Member(
    id: 'm_009',
    firstName: 'Priya',
    lastName: 'Shah',
    email: 'priya.shah@gmail.com',
    avatarAsset: 'assets/images/pfp_sylvia_crivia.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 13,
  ),
  Member(
    id: 'm_010',
    firstName: 'Jordan',
    lastName: 'Vega',
    email: 'jvega@gmail.com',
    avatarAsset: 'assets/images/pfp_amy_traver.png',
    rank: MemberRank.bronze,
    status: MemberStatus.active,
    lastClassDaysAgo: 19,
  ),
  Member(
    id: 'm_011',
    firstName: 'Ravi',
    lastName: 'Okafor',
    email: 'ravi.okafor@gmail.com',
    avatarAsset: 'assets/images/pfp_ben_ama.png',
    rank: MemberRank.silver,
    status: MemberStatus.active,
    lastClassDaysAgo: 1,
  ),
  Member(
    id: 'm_012',
    firstName: 'Nora',
    lastName: 'Linwood',
    email: 'nora.linwood@gmail.com',
    avatarAsset: 'assets/images/pfp_lily_altega.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 7,
  ),
  Member(
    id: 'm_013',
    firstName: 'Hugo',
    lastName: 'Marchetti',
    email: 'hugo.m@gmail.com',
    avatarAsset: 'assets/images/pfp_timothy_tom.png',
    rank: MemberRank.bronze,
    status: MemberStatus.trial,
    lastClassDaysAgo: 4,
  ),
  Member(
    id: 'm_014',
    firstName: 'Aiko',
    lastName: 'Tanaka',
    email: 'aiko.tanaka@gmail.com',
    avatarAsset: 'assets/images/pfp_sylvia_crivia.png',
    rank: MemberRank.silver,
    status: MemberStatus.active,
    lastClassDaysAgo: 14,
  ),
  Member(
    id: 'm_015',
    firstName: 'Diego',
    lastName: 'Salinas',
    email: 'diego.salinas@gmail.com',
    avatarAsset: 'assets/images/pfp_amy_traver.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 6,
  ),
  Member(
    id: 'm_016',
    firstName: 'Emma',
    lastName: 'Whitfield',
    email: 'emmawhit@gmail.com',
    avatarAsset: 'assets/images/pfp_lily_altega.png',
    rank: MemberRank.bronze,
    status: MemberStatus.active,
    lastClassDaysAgo: 21,
  ),
  Member(
    id: 'm_017',
    firstName: 'Owen',
    lastName: 'Brennan',
    email: 'owen.brennan@gmail.com',
    avatarAsset: 'assets/images/pfp_ben_ama.png',
    rank: MemberRank.silver,
    status: MemberStatus.active,
    lastClassDaysAgo: 3,
  ),
  Member(
    id: 'm_018',
    firstName: 'Zara',
    lastName: 'Mehmood',
    email: 'zara.m@gmail.com',
    avatarAsset: 'assets/images/pfp_sylvia_crivia.png',
    rank: MemberRank.gold,
    status: MemberStatus.active,
    lastClassDaysAgo: 10,
  ),
  Member(
    id: 'm_019',
    firstName: 'Felix',
    lastName: 'Donovan',
    email: 'felix.donovan@gmail.com',
    avatarAsset: 'assets/images/pfp_timothy_tom.png',
    rank: MemberRank.bronze,
    status: MemberStatus.frozen,
    lastClassDaysAgo: 24,
  ),
  Member(
    id: 'm_020',
    firstName: 'Sana',
    lastName: 'Aldridge',
    email: 'sana.a@gmail.com',
    avatarAsset: 'assets/images/pfp_amy_traver.png',
    rank: MemberRank.silver,
    status: MemberStatus.active,
    lastClassDaysAgo: 8,
  ),
];
