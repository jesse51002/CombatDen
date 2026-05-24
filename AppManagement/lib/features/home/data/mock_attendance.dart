/// Mock data for the Live Attendance card on the dashboard.
///
/// Each row is a member that's expected to be at the currently in-session
/// class. `checkedIn` drives the green "Checked In" / red "Not Here" pill.
/// Field names mirror what a real API would return so the future swap to
/// a repository is mechanical.
class AttendanceEntry {
  final String memberId;
  final String fullName;
  final bool checkedIn;

  const AttendanceEntry({
    required this.memberId,
    required this.fullName,
    required this.checkedIn,
  });
}

const List<AttendanceEntry> kMockLiveAttendance = [
  AttendanceEntry(
    memberId: 'm_001',
    fullName: 'Lily Altega',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_002',
    fullName: 'Ben Ama',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_003',
    fullName: 'Timothy Tom',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_004',
    fullName: 'Sylvia Crivia',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_005',
    fullName: 'Amy Traver',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_006',
    fullName: 'Marcus Pell',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_007',
    fullName: 'Dion Reyes',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_008',
    fullName: 'Kim Baranov',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_009',
    fullName: 'Priya Shah',
    checkedIn: true,
  ),
  AttendanceEntry(
    memberId: 'm_010',
    fullName: 'Jordan Vega',
    checkedIn: false,
  ),
];
