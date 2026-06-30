import 'package:intl/intl.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_request.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/features/schedule/data/models/class_instance_exception_request.dart';
import 'package:crm/features/schedule/data/models/class_range_exception_request.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_create_request.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_update_request.dart';

/// Repository for the Schedule screen over the FastAPI `classes` domain via
/// [ApiClient]. Paths and shapes match the backend schemas in
/// `../FastApiBackend/src/classes/schema/classes_crud_schema.py`.
///
/// The two list endpoints wrap their list in a `{ "items": [...] }` envelope
/// (`EffectiveClassInstanceListResponse` / `GymClassListResponse`); the write
/// endpoints return a bare `GymClassResponse`. Writes are admin/owner-gated on
/// the backend — the CRM JWT already carries that role.
class ScheduleRepository {
  final ApiClient _apiClient;

  ScheduleRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Backend `date` query params are bare `YYYY-MM-DD` (gym-local, no tz).
  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  /// `GET /api/v1/classes/instances?gym_id=&start_date=&end_date=` — the
  /// schedule board: every effective dated occurrence in `[startDate, endDate]`
  /// (cancelled days included, flagged).
  Future<List<EffectiveClassInstance>> listEffectiveInstances(
    String gymId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/classes/instances',
      queryParameters: {
        'gym_id': gymId,
        'start_date': _dateParam.format(startDate),
        'end_date': _dateParam.format(endDate),
      },
    );
    final items = (response.data as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) =>
            EffectiveClassInstance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/classes?gym_id=…` — the gym's (non-deleted) classes.
  Future<List<GymClassResponse>> listClasses(String gymId) async {
    final response = await _apiClient.get(
      '/api/v1/classes',
      queryParameters: {'gym_id': gymId},
    );
    final items = (response.data as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) => GymClassResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/v1/classes` — create a class. Returns the created row.
  Future<GymClassResponse> createClass(GymClassCreateRequest req) async {
    final response = await _apiClient.post(
      '/api/v1/classes',
      data: req.toJson(),
    );
    return GymClassResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `PUT /api/v1/classes/{class_id}` — update a class (the [data] changes
  /// nest under `data`). Returns the updated row.
  Future<GymClassResponse> updateClass(
    String classId,
    GymClassUpdateData data,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/classes/$classId',
      data: GymClassUpdateRequest(data: data).toJson(),
    );
    return GymClassResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/classes/{class_id}` — soft-delete (sets `is_deleted`).
  Future<void> deleteClass(String classId) async {
    await _apiClient.delete('/api/v1/classes/$classId');
  }

  /// `POST /api/v1/checkin/batch` — staff batch check-in. The occurrence is now
  /// addressed by the `class_id` + `occurrence_date` BODY fields (carried on
  /// [req] alongside the gym, member ids, and `is_member`); the path no longer
  /// carries them.
  ///
  /// Returns **207 Multi-Status** — a 2xx, so Dio does NOT throw: the
  /// per-member split arrives here on the SUCCESS path and is parsed as a
  /// [BatchCheckInResponse]. (A total failure is a 500 and throws; an invalid
  /// occurrence is 400/404.)
  Future<BatchCheckInResponse> batchCheckIn(BatchCheckInRequest req) async {
    final response = await _apiClient.post(
      '/api/v1/checkin/batch',
      data: req.toJson(),
    );
    return BatchCheckInResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `GET /api/v1/checkin/attendees?gym_id=&class_id=&occurrence_date=` — the
  /// members who attended a materialized occurrence (read-only). An occurrence
  /// that was never materialized (no check-ins yet) comes back with a null
  /// `class_history_id` and an empty list.
  Future<AttendeeListResponse> listAttendees(
    String gymId,
    String classId,
    DateTime occurrenceDate,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/checkin/attendees',
      queryParameters: {
        'gym_id': gymId,
        'class_id': classId,
        'occurrence_date': _dateParam.format(occurrenceDate),
      },
    );
    return AttendeeListResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/checkin?member_id=&gym_id=&class_id=&occurrence_date=` —
  /// reverse one member's check-in on this occurrence (a staff correction):
  /// deletes their attendance row, claws back the class's points, and
  /// reverses any pack auto-end the removal drops back below capacity. The
  /// response's `removed` flag is `false` (still 200) when the member wasn't
  /// checked in — this method only signals success/failure via throw, so the
  /// roster doesn't need the body.
  Future<void> removeAttendee(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String memberId,
  ) async {
    await _apiClient.delete(
      '/api/v1/checkin',
      queryParameters: {
        'member_id': memberId,
        'gym_id': gymId,
        'class_id': classId,
        'occurrence_date': _dateParam.format(occurrenceDate),
      },
    );
  }

  /// `POST /api/v1/classes/{class_id}/exceptions/instance` with
  /// `is_cancelled: true` — cancel the single occurrence on [originalDate].
  /// Upserts the one-day exception; the response body is ignored (the board is
  /// reloaded from `/instances` instead).
  Future<void> cancelInstance(String classId, DateTime originalDate) async {
    await _apiClient.post(
      '/api/v1/classes/$classId/exceptions/instance',
      data: ClassInstanceExceptionRequest(
        originalDate: _dateParam.format(originalDate),
        isCancelled: true,
      ).toJson(),
    );
  }

  /// `POST /api/v1/classes/{class_id}/exceptions/instance` with
  /// `is_cancelled: false` and the override fields set — upsert this single
  /// occurrence's effective instructor / start time / max capacity / duration.
  /// The response body is ignored (the board reloads from `/instances`
  /// instead).
  Future<void> overrideInstance(
    String classId,
    DateTime originalDate, {
    required String newClassTime,
    required int newDurationMinutes,
    int? newMaxCapacity,
    String? newInstructorId,
  }) async {
    await _apiClient.post(
      '/api/v1/classes/$classId/exceptions/instance',
      data: ClassInstanceExceptionRequest(
        originalDate: _dateParam.format(originalDate),
        isCancelled: false,
        newClassTime: newClassTime,
        newDurationMinutes: newDurationMinutes,
        newMaxCapacity: newMaxCapacity,
        newInstructorId: newInstructorId,
      ).toJson(),
    );
  }

  /// `POST /api/v1/classes/{class_id}/exceptions/range` with
  /// `is_cancelled: true` — cancel every occurrence in `[startDate, endDate]`
  /// (inclusive). The response body is ignored (the board reloads instead).
  Future<void> cancelRange(
    String classId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    await _apiClient.post(
      '/api/v1/classes/$classId/exceptions/range',
      data: ClassRangeExceptionRequest(
        startDate: _dateParam.format(startDate),
        endDate: _dateParam.format(endDate),
        isCancelled: true,
      ).toJson(),
    );
  }
}
