// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$EmployeeUpdateDataToJson(EmployeeUpdateData instance) =>
    <String, dynamic>{
      'first_name': ?instance.firstName,
      'last_name': ?instance.lastName,
      'phone': ?instance.phone,
      'email': ?instance.email,
      'employee_public_description': ?instance.employeePublicDescription,
      'employee_pic_url': ?instance.employeePicUrl,
      'employee_type': ?_roleOrNullToJson(instance.employeeType),
    };
