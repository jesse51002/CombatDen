import 'package:equatable/equatable.dart';

import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// What `POST /api/v1/employees/{gym_id}` returns — the created row plus what
/// actually happened to their invite.
///
/// Mirrors the backend `EmployeeCreateResponse`
/// (`../FastApiBackend/src/employees/schema/employees_schema.py`): the
/// employee is the same `EmployeeResponse` as before, now wrapped alongside
/// [invite]. The outcome is part of the response rather than assumed from the
/// request, so the Add dialog's confirmation can be honest about a held or
/// suppressed send.
class EmployeeCreateResult extends Equatable {
  final Employee employee;
  final InviteOutcome invite;

  const EmployeeCreateResult({
    required this.employee,
    required this.invite,
  });

  factory EmployeeCreateResult.fromJson(Map<String, dynamic> json) {
    return EmployeeCreateResult(
      employee: Employee.fromJson(json['employee'] as Map<String, dynamic>),
      invite: InviteOutcome.fromJson(json['invite'] as String),
    );
  }

  @override
  List<Object?> get props => [employee, invite];
}
