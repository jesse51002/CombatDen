// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Employee _$EmployeeFromJson(Map<String, dynamic> json) => Employee(
  employeeId: json['employee_id'] as String,
  gymId: json['gym_id'] as String,
  employeeType: EmployeeRole.fromJson(json['employee_type'] as String),
  firstName: json['first_name'] as String,
  lastName: json['last_name'] as String,
  phone: json['phone'] as String?,
  email: json['email'] as String?,
  employeePicUrl: json['employee_pic_url'] as String?,
  employeePublicDescription: json['employee_public_description'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  inviteStatus: InviteStatus.fromJson(json['invite_status'] as String),
);
