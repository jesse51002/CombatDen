// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_create_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$EmployeeCreateRequestToJson(
  EmployeeCreateRequest instance,
) => <String, dynamic>{
  'employee_type': _roleToJson(instance.employeeType),
  'first_name': instance.firstName,
  'last_name': instance.lastName,
  'email': instance.email,
  'phone': ?instance.phone,
  'employee_public_description': ?instance.employeePublicDescription,
};
