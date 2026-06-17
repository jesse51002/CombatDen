import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/tasks/data/models/task_response.dart';

/// Repository for gym background tasks.
///
/// Every call goes through [ApiClient]; shapes match
/// the FastAPI `/api/v1/tasks/` endpoints.
class TasksRepository {
  final ApiClient _apiClient;

  TasksRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/tasks/ongoing?gym_id=…`
  Future<List<TaskResponse>> getOngoingTasks(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/tasks/ongoing',
      queryParameters: {'gym_id': gymId},
    );
    return (response.data as List<dynamic>)
        .map((e) => TaskResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/tasks/{task_id}?gym_id=…`
  Future<TaskResponse> getTask(String taskId, String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/tasks/$taskId',
      queryParameters: {'gym_id': gymId},
    );
    return TaskResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
