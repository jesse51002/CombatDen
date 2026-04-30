/// Mock data for the Live Attendance card on the dashboard.
///
/// Each row is a member that's expected to be at the currently in-session
/// class. `checkedIn` drives the green "Checked In" / red "Not Here" pill.
/// Field names mirror what a real API would return so the future swap to
/// a repository is mechanical.
class AttendanceEntry {
  final String memberId;
  final String fullName;
  final String avatarAsset;
  final bool checkedIn;

  const AttendanceEntry({
    required this.memberId,
    required this.fullName,
    required this.avatarAsset,
    required this.checkedIn,
  });
}

const List<AttendanceEntry> kMockLiveAttendance = [
  AttendanceEntry(
    memberId: 'm_001',
    fullName: 'Lily Altega',
    avatarAsset: 'assets/images/pfp_lily_altega.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_002',
    fullName: 'Ben Ama',
    avatarAsset: 'assets/images/pfp_ben_ama.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_003',
    fullName: 'Timothy Tom',
    avatarAsset: 'assets/images/pfp_timothy_tom.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_004',
    fullName: 'Sylvia Crivia',
    avatarAsset: 'assets/images/pfp_sylvia_crivia.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_005',
    fullName: 'Amy Traver',
    avatarAsset: 'assets/images/pfp_amy_traver.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_006',
    fullName: 'Marcus Pell',
    avatarAsset: 'assets/images/pfp_lily_altega.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_007',
    fullName: 'Dion Reyes',
    avatarAsset: 'assets/images/pfp_ben_ama.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_008',
    fullName: 'Kim Baranov',
    avatarAsset: 'assets/images/pfp_timothy_tom.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_009',
    fullName: 'Priya Shah',
    avatarAsset: 'assets/images/pfp_sylvia_crivia.png',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_010',
    fullName: 'Jordan Vega',
    avatarAsset: 'assets/images/pfp_amy_traver.png',
    checkedIn: false,
  ),
];
