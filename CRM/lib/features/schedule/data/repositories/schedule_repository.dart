import 'package:intl/intl.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_request.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/check_in/data/models/signup_request.dart';
import 'package:crm/features/check_in/data/models/signup_response.dart';
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

  /// `PUT /api/v1/classes/{class_id}` — update a class. [request] is split by
  /// destination: `identity` (partial) updates `gym_classes` in place;
  /// `schedule` (a complete shape) mints a new schedule version. Returns the
  /// updated (flat) row.
  Future<GymClassResponse> updateClass(
    String classId,
    GymClassUpdateRequest request,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/classes/$classId',
      data: request.toJson(),
    );
    return GymClassResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/classes/{class_id}` — soft-delete (sets `is_deleted`).
  Future<void> deleteClass(String classId) async {
    await _apiClient.delete('/api/v1/classes/$classId');
  }

  /// `POST /api/v1/checkin/batch` — staff batch check-in. The occurrence is
  /// addressed by the `class_id` + `occurrence_date` BODY fields — the
  /// occurrence's IDENTITY date, never its effective/display date — carried
  /// on [req] alongside the gym, member ids, `is_member`, and
  /// `ignore_warnings`; the path does not carry them.
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
  /// combined roster (everyone signed up OR attended) for the occurrence
  /// addressed by [classId] + [occurrenceDate] (its IDENTITY date, never its
  /// effective/display date), read-only. An occurrence with no sign-ups and
  /// no check-ins comes back with an empty list.
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
  /// [occurrenceDate] is the occurrence's IDENTITY date, never its
  /// effective/display date. Reverse one member's check-in on this
  /// occurrence (a staff correction):
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

  /// `POST /api/v1/signup` — reserve [memberId] a spot on the occurrence of
  /// [classId] on [occurrenceDate] (its IDENTITY date, never its effective/
  /// display date) — a reservation, NOT attendance.
  /// Idempotent (`already_signed_up: true` on a repeat, no extra capacity
  /// consumed); rejected with a 400 `"Class is full"` when the occurrence's
  /// effective capacity (the distinct signed-up-or-attended count) is
  /// already reached — unlimited capacity never blocks. Both staff and the
  /// member themselves may call this; the CRM always calls as staff.
  Future<SignupResponse> signUp(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String memberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/signup',
      data: SignupRequest(
        memberId: memberId,
        gymId: gymId,
        classId: classId,
        occurrenceDate: _dateParam.format(occurrenceDate),
      ).toJson(),
    );
    return SignupResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/signup?member_id=&gym_id=&class_id=&occurrence_date=` —
  /// [occurrenceDate] is the occurrence's IDENTITY date, never its
  /// effective/display date. Cancel [memberId]'s sign-up (reservation) for
  /// this occurrence, a staff correction. The response's `removed` flag is
  /// `false` (still 200) when
  /// the member had no sign-up — this method only signals success/failure
  /// via throw, mirroring [removeAttendee].
  Future<void> cancelSignup(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String memberId,
  ) async {
    await _apiClient.delete(
      '/api/v1/signup',
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
  /// occurrence's effective instructor / start time / max capacity / duration,
  /// and optionally reschedule it to [newDate] (any date — past, today, or
  /// future; the backend rejects only a collision with an existing
  /// non-cancelled occurrence at the exact target instant, surfaced as a
  /// 400/409 whose `detail` message is thrown as a `ServerException`). The
  /// response body is ignored (the board reloads from `/instances` instead).
  Future<void> overrideInstance(
    String classId,
    DateTime originalDate, {
    required String newClassTime,
    required int newDurationMinutes,
    int? newMaxCapacity,
    String? newInstructorId,
    DateTime? newDate,
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
        newDate: newDate != null ? _dateParam.format(newDate) : null,
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
