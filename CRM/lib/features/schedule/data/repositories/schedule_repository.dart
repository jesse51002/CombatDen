import 'package:intl/intl.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_request.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/check_in/data/models/signup_request.dart';
import 'package:crm/features/check_in/data/models/signup_response.dart';
import 'package:crm/features/member_details/data/models/member_class_history.dart';
import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/features/schedule/data/models/class_instance_exception_request.dart';
import 'package:crm/features/schedule/data/models/class_range_exception.dart';
import 'package:crm/features/schedule/data/models/class_range_exception_request.dart';
import 'package:crm/features/schedule/data/models/class_range_exception_update_request.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_create_request.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_update_request.dart';

/// Repository for the schedule surfaces over the FastAPI `classes` domain
/// AND the `checkin` domain's occurrence-scoped + member-scoped reads/writes
/// (roster, check-in removal, sign-ups, batch check-in, the member
/// class-history feed) via [ApiClient]. Paths and shapes match the backend
/// schemas in `../FastApiBackend/src/classes/schema/classes_crud_schema.py`
/// and `../FastApiBackend/src/checkin/schema/*.py`.
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
  ///
  /// PAUSED classes (`is_active = false`) are OPT-IN, and the opt-in belongs
  /// to exactly one caller.
  ///
  /// [includeInactive] maps to the endpoint's `include_inactive` query param
  /// and defaults to **false**, matching the server's own default: a paused
  /// class then contributes no occurrences at all. That default is the
  /// fail-closed guarantee — check-in and sign-up both reject a paused class
  /// with a bare `400 class_inactive`, so the dashboard, the kiosk, and the
  /// member-detail check-in/reserve dialog must never be offered one, and
  /// they get that by simply not passing the flag.
  ///
  /// **Only the SCHEDULE BOARD (the classes page) passes `true`** — the one
  /// surface a paused class must stay visible on, because it is the only
  /// route to the class editor. Those rows come back flagged
  /// `isActive: false`, and the board marks them "Paused" and sends their tap
  /// straight to the class form rather than the check-in chooser. Do not add
  /// a second caller without a founder decision, and never filter
  /// `isActive` client-side — the server default is the mechanism.
  Future<List<EffectiveClassInstance>> listEffectiveInstances(
    String gymId,
    DateTime startDate,
    DateTime endDate, {
    bool includeInactive = false,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/classes/instances',
      queryParameters: {
        'gym_id': gymId,
        'start_date': _dateParam.format(startDate),
        'end_date': _dateParam.format(endDate),
        'include_inactive': includeInactive,
      },
    );
    final items = (response.data as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) =>
            EffectiveClassInstance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/v1/classes?gym_id=&include_inactive=` — the gym's (non-deleted)
  /// classes.
  ///
  /// [includeInactive] maps to the backend's `include_inactive` query param
  /// and defaults to **false**, matching the endpoint's own default: a
  /// consumer that just needs the live catalog (e.g. the Employees tab's
  /// taught-classes derivation) gets active classes only. The SCHEDULE
  /// board's catalog load passes `true`, because class management is the one
  /// surface where a PAUSED class must stay visible — it is the only place
  /// it can be un-paused from.
  Future<List<GymClassResponse>> listClasses(
    String gymId, {
    bool includeInactive = false,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/classes',
      queryParameters: {
        'gym_id': gymId,
        'include_inactive': includeInactive,
      },
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
  /// addressed by the `class_id` + `occurrence_date` + `occurrence_time` BODY
  /// fields — the occurrence's IDENTITY key, never its effective/display
  /// date/time — carried on [req] alongside the gym, member ids, `is_member`,
  /// and `ignore_warnings`; the path does not carry them.
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

  /// `GET /api/v1/checkin/attendees?gym_id=&class_id=&occurrence_date=&occurrence_time=`
  /// — the combined roster (everyone signed up OR attended) for the
  /// occurrence addressed by [classId] + [occurrenceDate] + [occurrenceTime]
  /// (its IDENTITY key, never its effective/display date/time), read-only.
  /// An occurrence with no sign-ups and no check-ins comes back with an empty
  /// list.
  Future<AttendeeListResponse> listAttendees(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String occurrenceTime,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/checkin/attendees',
      queryParameters: {
        'gym_id': gymId,
        'class_id': classId,
        'occurrence_date': _dateParam.format(occurrenceDate),
        'occurrence_time': occurrenceTime,
      },
    );
    return AttendeeListResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `GET /api/v1/checkin/history?member_id=&gym_id=&limit=&offset=` — one
  /// member's class-history card feed: their open reservations (soonest
  /// first, unpaginated) plus a newest-first PAGE of their attended/no-show
  /// history. [limit]/[offset] paginate `history` only; `upcoming` is always
  /// complete. Read-only side read for the member-detail page's Class
  /// history card.
  Future<MemberClassHistoryResponse> getMemberClassHistory(
    String memberId,
    String gymId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/checkin/history',
      queryParameters: {
        'member_id': memberId,
        'gym_id': gymId,
        'limit': limit,
        'offset': offset,
      },
    );
    return MemberClassHistoryResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/checkin?member_id=&gym_id=&class_id=&occurrence_date=&occurrence_time=`
  /// — [occurrenceDate] + [occurrenceTime] are the occurrence's IDENTITY key,
  /// never its effective/display date/time. Reverse one member's check-in on
  /// this occurrence (a staff correction): deletes their attendance row,
  /// claws back the class's points, and reverses any pack auto-end the
  /// removal drops back below capacity. The response's `removed` flag is
  /// `false` (still 200) when the member wasn't checked in — this method
  /// only signals success/failure via throw, so the roster doesn't need the
  /// body.
  Future<void> removeAttendee(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String occurrenceTime,
    String memberId,
  ) async {
    await _apiClient.delete(
      '/api/v1/checkin',
      queryParameters: {
        'member_id': memberId,
        'gym_id': gymId,
        'class_id': classId,
        'occurrence_date': _dateParam.format(occurrenceDate),
        'occurrence_time': occurrenceTime,
      },
    );
  }

  /// `POST /api/v1/signup` — reserve [memberId] a spot on the occurrence of
  /// [classId] on [occurrenceDate] + [occurrenceTime] (its IDENTITY key,
  /// never its effective/display date/time) — a reservation, NOT attendance.
  /// Idempotent (`already_signed_up: true` on a repeat, no extra capacity
  /// consumed); rejected with a 400 `"Class is full"` when the occurrence's
  /// effective capacity (the distinct signed-up-or-attended count) is
  /// already reached — unlimited capacity never blocks. Both staff and the
  /// member themselves may call this; the CRM always calls as staff.
  Future<SignupResponse> signUp(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String occurrenceTime,
    String memberId,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/signup',
      data: SignupRequest(
        memberId: memberId,
        gymId: gymId,
        classId: classId,
        occurrenceDate: _dateParam.format(occurrenceDate),
        occurrenceTime: occurrenceTime,
      ).toJson(),
    );
    return SignupResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// `DELETE /api/v1/signup?member_id=&gym_id=&class_id=&occurrence_date=&occurrence_time=`
  /// — [occurrenceDate] + [occurrenceTime] are the occurrence's IDENTITY key,
  /// never its effective/display date/time. Cancel [memberId]'s sign-up
  /// (reservation) for this occurrence, a staff correction. The response's
  /// `removed` flag is `false` (still 200) when the member had no sign-up —
  /// this method only signals success/failure via throw, mirroring
  /// [removeAttendee].
  Future<void> cancelSignup(
    String gymId,
    String classId,
    DateTime occurrenceDate,
    String occurrenceTime,
    String memberId,
  ) async {
    await _apiClient.delete(
      '/api/v1/signup',
      queryParameters: {
        'member_id': memberId,
        'gym_id': gymId,
        'class_id': classId,
        'occurrence_date': _dateParam.format(occurrenceDate),
        'occurrence_time': occurrenceTime,
      },
    );
  }

  /// `POST /api/v1/classes/{class_id}/exceptions/instance` with
  /// `is_cancelled: true` — cancel the single occurrence on [originalDate] +
  /// [originalTime] (its identity slot — a same-day sibling slot is
  /// untouched). Upserts the one-slot exception; the response body is
  /// ignored (the board is reloaded from `/instances` instead).
  Future<void> cancelInstance(
    String classId,
    DateTime originalDate,
    String originalTime,
  ) async {
    await _apiClient.post(
      '/api/v1/classes/$classId/exceptions/instance',
      data: ClassInstanceExceptionRequest(
        originalDate: _dateParam.format(originalDate),
        originalTime: originalTime,
        isCancelled: true,
      ).toJson(),
    );
  }

  /// `POST /api/v1/classes/{class_id}/exceptions/instance` with
  /// `is_cancelled: false` and the override fields set — upsert this single
  /// occurrence's (identified by [originalDate] + [originalTime]) effective
  /// instructor / start time / max capacity / duration, and optionally
  /// reschedule it to [newDate] (any date — past, today, or future; the
  /// backend rejects only a collision with an existing non-cancelled
  /// occurrence at the exact target instant, surfaced as a 400/409 whose
  /// `detail` message is thrown as a `ServerException`). The response body is
  /// ignored (the board reloads from `/instances` instead).
  Future<void> overrideInstance(
    String classId,
    DateTime originalDate,
    String originalTime, {
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
        originalTime: originalTime,
        isCancelled: false,
        newClassTime: newClassTime,
        newDurationMinutes: newDurationMinutes,
        newMaxCapacity: newMaxCapacity,
        newInstructorId: newInstructorId,
        newDate: newDate != null ? _dateParam.format(newDate) : null,
      ).toJson(),
    );
  }

  /// `DELETE /api/v1/classes/{class_id}/occurrences/{occurrence_date}` — the
  /// DEDICATED staff (owner/admin/front_desk) cancel path, distinct from the
  /// owner/admin-only [cancelInstance] `exceptions/instance` override.
  /// Un-occurs the occurrence at [originalDate] + [originalTime] (its IDENTITY
  /// slot): [originalDate] (`YYYY-MM-DD`) is the PATH param; [originalTime]
  /// (`HH:MM:SS`) and [gymId] are QUERY params. Server-side it reverses the
  /// day's attendance (points clawed back) and deletes its sign-ups. The
  /// `OccurrenceCancelResponse` body is ignored — the board reloads from
  /// `/instances` — so this returns void; a non-2xx surfaces as a
  /// `ServerException` carrying the `detail`.
  Future<void> cancelOccurrence({
    required String classId,
    required DateTime originalDate,
    required String originalTime,
    required String gymId,
  }) async {
    await _apiClient.delete(
      '/api/v1/classes/$classId/occurrences/'
      '${_dateParam.format(originalDate)}',
      queryParameters: {
        'occurrence_time': originalTime,
        'gym_id': gymId,
      },
    );
  }

  /// `POST /api/v1/classes/{class_id}/occurrences/{occurrence_date}/reschedule`
  /// — the DEDICATED staff (owner/admin/front_desk) move path, distinct from
  /// the owner/admin-only [overrideInstance] `exceptions/instance` reschedule.
  /// Moves the occurrence at [originalDate] + [originalTime] (its IDENTITY
  /// slot) to [newDate] — DATE ONLY; the occurrence keeps its original TIME.
  /// [originalDate] (`YYYY-MM-DD`) is the PATH param, [originalTime]
  /// (`HH:MM:SS`) a QUERY param, and the body carries `{gym_id, new_date}`. The
  /// backend rejects a collision with an existing non-cancelled occurrence at
  /// the exact target instant with a 409 whose `detail` is surfaced as a
  /// `ServerException`. The `OccurrenceRescheduleResponse` body is ignored (the
  /// board reloads from `/instances`), so this returns void.
  Future<void> rescheduleOccurrence({
    required String classId,
    required DateTime originalDate,
    required String originalTime,
    required String gymId,
    required DateTime newDate,
  }) async {
    await _apiClient.post(
      '/api/v1/classes/$classId/occurrences/'
      '${_dateParam.format(originalDate)}/reschedule',
      queryParameters: {'occurrence_time': originalTime},
      data: {
        'gym_id': gymId,
        'new_date': _dateParam.format(newDate),
      },
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

  /// `GET /api/v1/classes/{class_id}/exceptions/range` — every range
  /// exception ever created for this class (cancel and instructor-
  /// substitution alike), newest-created first.
  Future<List<ClassRangeException>> listRangeExceptions(
    String classId,
  ) async {
    final response =
        await _apiClient.get('/api/v1/classes/$classId/exceptions/range');
    final items = (response.data as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) => ClassRangeException.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `PUT /api/v1/classes/{class_id}/exceptions/range/{exception_id}` — move
  /// a range exception's dates. For a CANCEL range the backend atomically
  /// re-runs the create path's teardown over the NEW coverage; dates that
  /// fall out of coverage simply revive (nothing already removed is
  /// restored).
  Future<ClassRangeException> updateRangeException(
    String classId,
    String exceptionId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final response = await _apiClient.put(
      '/api/v1/classes/$classId/exceptions/range/$exceptionId',
      data: ClassRangeExceptionUpdateRequest(
        startDate: _dateParam.format(startDate),
        endDate: _dateParam.format(endDate),
      ).toJson(),
    );
    return ClassRangeException.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// `DELETE /api/v1/classes/{class_id}/exceptions/range/{exception_id}` —
  /// remove a range exception outright. Covered dates revive on the next
  /// expansion; reservations/check-ins already torn down while it was
  /// active are not restored.
  Future<void> deleteRangeException(
    String classId,
    String exceptionId,
  ) async {
    await _apiClient.delete(
      '/api/v1/classes/$classId/exceptions/range/$exceptionId',
    );
  }
}
