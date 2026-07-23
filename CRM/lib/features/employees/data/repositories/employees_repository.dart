import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_create_request.dart';
import 'package:crm/features/employees/data/models/employee_update_request.dart';

/// Repository for the gym staff roster over the FastAPI `employees` domain via
/// [ApiClient]. Paths and shapes match
/// `../FastApiBackend/src/employees/schema/employees_schema.py`.
///
/// The list endpoint wraps its rows in a `{ "employees": [...] }` envelope
/// (`EmployeeListResponse`); create/update return a bare `EmployeeResponse`.
/// Errors surface as the typed exceptions [ApiClient] throws — a 409/422 keeps
/// the backend `detail` on [ServerException.detail], which the Add dialog shows
/// verbatim (e.g. a duplicate-email conflict).
class EmployeesRepository {
  final ApiClient _apiClient;

  EmployeesRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// `GET /api/v1/employees/{gym_id}` — all non-archived employees (every type).
  Future<List<Employee>> listEmployees(String gymId) async {
    final response = await _apiClient.get('/api/v1/employees/$gymId');
    final data = response.data as Map<String, dynamic>;
    final employees = data['employees'] as List;
    return employees
        .map((e) => Employee.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/v1/employees/{gym_id}` — create a staff member. Returns the
  /// created row (its server id + derived `invite_status`).
  Future<Employee> createEmployee(
    String gymId,
    EmployeeCreateRequest request,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/employees/$gymId',
      data: request.toJson(),
    );
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }

  /// `PUT /api/v1/employees/{gym_id}/{employee_id}` — update the mutable fields.
  /// Returns the updated row.
  Future<Employee> updateEmployee(
    String gymId,
    String employeeId,
    EmployeeUpdateData data,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/employees/$gymId/$employeeId',
      data: EmployeeUpdateRequest(data: data).toJson(),
    );
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/employees/{gym_id}/{employee_id}` — remove a staff member.
  Future<void> deleteEmployee(String gymId, String employeeId) async {
    await _apiClient.delete('/api/v1/employees/$gymId/$employeeId');
  }
}
