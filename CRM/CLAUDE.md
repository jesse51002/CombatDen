# CRM — Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this app is

This is the CombatDen **gym admin web app** (CRM) — staff and owners managing their gym from a browser. It is **production software**: real Supabase auth, real FastApiBackend data over `dio`, Bloc state management, and Stripe billing. Treat every screen as something a paying gym depends on.

- **Web-only Flutter app** (no Android, no iOS target).
- **Architecture is feature-first** (see *Project Structure*): each feature owns its `bloc/`, `data/` (models + repositories), and `presentation/` (screens + widgets + dialogs + sections).
- **Two deliberate edge integrations** — the video feed/gym-detail (read, plus the owner's "Your videos" add/remove) and the read-only ThemeService theme preview — are documented below. They are specific, scoped integrations, **not** the only backend access: the CRM feature stack (members, member detail, gym setup, billing) goes through the FastApiBackend via the authenticated `ApiClient`.

**Theme/design rules are not relaxed for any reason.** See *Theming System*.

## Hybrid state-management model (documented and deliberate)

This app uses **two patterns side by side, on purpose**:

- **CRM feature screens use Bloc.** Anything backed by the FastApiBackend — the **login / auth gate** (`features/login/`), **gym setup wizard** (`features/gym_setup/`), **members list** (`features/members_list/` → rendered by `MembersListBody` inside the **People** screen, `features/people/.../people_screen.dart` — the Members tab of the People section), **member detail + its billing dialogs** (`features/member_details/`), the **Memberships catalog** (`features/memberships/` — the Memberships / Discounts / Waivers screen; one `MembershipsRepository` behind a `PlansBloc`, `DiscountsBloc`, and `WaiversBloc`; the membership plan form and the waiver editor are full-screen **repository-direct** edit screens, not bloc-backed), the dashboard's **Overdue Payments section** (`features/home/bloc/overdue_payments_*` → `features/home/.../overdue_payments/`, which reuses `MembersListRepository`), the **Settings** screen's appearance save (`features/settings/` — a small `SettingsBloc` that persists the theme via `PUT .../employees/me/theme`), and the **Schedule** screen's class **week board** + its Add/Edit Class form (`features/schedule/` — a `ScheduleBloc` over `ScheduleRepository` against the FastApiBackend `classes` domain: it **reads** `GET /api/v1/classes/instances` for the effective dated occurrences (each board card shows the occurrence's participant count as a `Symbols.group_sharp` chip — "N attended" for a past occurrence, "N signed up" for an upcoming one, chosen by the card's `occurrenceInPast` flag — from `EffectiveClassInstance.attendanceCount`) + `GET /api/v1/classes` for the catalog, and **writes** via `POST /api/v1/classes` / `PUT /api/v1/classes/{class_id}` / `DELETE /api/v1/classes/{class_id}` — create / edit / soft-delete dispatched from `class_form_screen.dart` as `ScheduleClassCreated` / `ScheduleClassUpdated` / `ScheduleClassDeleted` — plus **cancel exceptions** + a **two-view occurrence flow**: tapping a board card opens a small **chooser dialog** (`presentation/dialogs/class_occurrence_chooser_dialog.dart`, naming the tapped occurrence's date) with two choices, each pushed with `BlocProvider.value` so it shares the board's bloc — **"This occurrence"** opens `presentation/screens/class_occurrence_screen.dart`, a dedicated occurrence-focused screen (header = the class image banner at a **fixed 16:9 aspect ratio** — `widgets/occurrence/class_occurrence_header.dart`'s `_kBannerAspect`, matching the board card's own `ClassCard._kCardImageAspect` so a class's image reads the same on the board and here — when the class has one, then the class name + the occurrence's date), and **"All future occurrences"** opens `presentation/screens/class_form_screen.dart`, now purely the class-**definition** editor (name, description, recurrence, per-weekday instructors, capacity, points, image, start/end date, the "Cancel a date range" secondary action, delete) with no per-occurrence actions. The occurrence screen's **"This day's details"** block defaults to a **read-only view** (`widgets/occurrence/class_occurrence_read_only_details.dart`'s `ClassOccurrenceReadOnlyDetails` — date / start time / instructor / max capacity as label/value rows, sourced straight from the tapped entry) — a tapped occurrence is opened to be **seen** first, not dropped straight into an editable form — with an **Edit** button that switches to the editable **override-edit section** (`widgets/occurrence/class_occurrence_override_section.dart`) — instructor, start time, max capacity, and a **date** field, pre-filled from the tapped occurrence's *effective* values (`ScheduleClassEntry.resolvedInstructorId` / `resolvedClassTime` / `maxCapacity` / `classDate`, enriched onto the tap payload in `schedule_screen.dart`'s `_entryFromInstance`), plus a **Cancel** button that discards in-progress edits (resets the fields to the entry's values) and returns to the read-only view without saving. The date field **reschedules** the occurrence to another day: it defaults to the occurrence's current date, and its picker's `firstDate` floors at `originalDate + 1 day` — the backend's reschedule is **forward-only** (a DB CHECK, `new_date > original_date`) and also rejects a collision with an existing occurrence (both surfaced as an inline 400/409 error); leaving the picker unmoved omits `new_date` entirely, so a plain retime/instructor/capacity save never accidentally reschedules. (Scope: this assumes the tapped entry's date is the occurrence's *original*, not-yet-moved date — rescheduling an already-rescheduled occurrence a second time is out of scope.) Save dispatches `ScheduleInstanceOverridden` (`POST /api/v1/classes/{class_id}/exceptions/instance` with `is_cancelled:false` and the override fields set, carrying the unedited `resolvedDurationMinutes` through so the upsert never blanks a duration override the field doesn't expose, plus the optional `new_date`; `EffectiveClassInstance.maxCapacity` reflects the per-day `new_max_capacity` instance override, resolved in `classes_schedule_reader_service.py::_build_row` (falling back to the class default) to match what the check-in capacity gate enforces, so the prefill stays correct and a re-save won't revert a saved override); a successful save pops the whole screen (no need to return to the read-only view). And the relocated `ClassOccurrenceActions` block (`widgets/form/class_occurrence_actions.dart`), which stays visible in both view and edit mode: "Update attendees" (the batch staff check-in) — shown only when **check-in is open** (`ClassOccurrenceScreen._checkInOpen`: the occurrence has started / passed, or starts within `_kCheckInOpensHours` = **2h**, mirroring the backend `checkin_opens_hours_before_start`; a class further out hides the action and the backend rejects it anyway), "Cancel this class" (only for an upcoming, not-already-cancelled day), and — for a past / current-day occurrence — the searchable, scrollable attendee roster (`widgets/form/class_attendee_roster.dart`, a `FutureBuilder` over its own `ScheduleRepository.listAttendees` → `GET /api/v1/checkin/attendees`; a name search (`AppSearchBox`) filters a height-bounded scrolling list, "No attendees yet" when empty/unmaterialized). Each roster row carries a remove (×) action — a staff correction reversing that member's check-in: confirm via `ConfirmationModal` ("Remove \<name\> from this class?", `badRed`) → `ScheduleRepository.removeAttendee` (`DELETE /api/v1/checkin?member_id=&gym_id=&class_id=&occurrence_date=`, mirroring `listAttendees`' date formatting) → on success the roster's own `_future` is reassigned via `setState` (re-fetching `listAttendees` so the member drops off the list) and a "Removed from class" `SnackBar` confirms; on failure an error `SnackBar` — never a silent dismiss. Both the roster row and the batch picker's row (below) render through the shared `lib/shared/widgets/member_row_tile.dart` (`MemberRowTile`: an `InstructorAvatar` photo-or-initials avatar + name + an optional `trailing` slot, pure presentational) so a member looks identical whether you're viewing the roster or picking from the batch check-in list — the roster's trailing is the remove button, `BatchCheckInMemberTile` (used inside `BatchCheckInPicker` via the shared `lib/shared/widgets/paginated_member_picker.dart`) is now a thin wrapper whose trailing is the selection `Checkbox` with the whole row tappable to toggle. A cancelled occurrence collapses to just `ClassOccurrenceActions`' note (the details block — view or edit — and roster don't render). "Cancel this class" `POST`s `/api/v1/classes/{class_id}/exceptions/instance` with `is_cancelled:true` as `ScheduleInstanceCancelled`; the **series editor's** "Cancel a date range" secondary action opens `class_range_cancel_dialog.dart` which `POST`s `/api/v1/classes/{class_id}/exceptions/range` with `is_cancelled:true` as `ScheduleRangeCancelled` (request models `class_instance_exception_request.dart` / `class_range_exception_request.dart`, responses unparsed; the range cancel dialog shares the processing/success terminal views in `dialogs/schedule_cancel_views.dart`, whose `ScheduleCancelSuccess` body both the series editor and the occurrence screen also reuse inside their own save-success dialogs). The **"Update attendees"** action (opened from the occurrence screen) opens `presentation/dialogs/check_in/class_batch_check_in_dialog.dart` — a paginated member multi-select that `POST`s the staff batch check-in `/api/v1/checkin/batch` (the occurrence is addressed by `class_id` + `occurrence_date` + `is_member:false` in the BODY now — the path no longer carries them; returns **207 Multi-Status**; Dio does NOT throw on a 207, so the per-member breakdown is read off the success path) as `ScheduleBatchCheckInRequested` on a DEDICATED `isCheckingIn` / `batchCheckInResult` / `checkInError` channel on `ScheduleLoaded` (kept off `isMutating` so the dialog owns its own processing → results step), reloading the board on success so attendance counts update. Check-in is **warn-first with an override**: a clean member records, but one the gate warns on (no membership / out of classes / ineligible plan / over capacity) comes back as the batch item status `needs_confirmation` — **nothing written** for that member, its `warnings` say why — the results step shows ✓ checked-in / already-in / needs-confirmation (⚠, `okYellow`) / ✗ failed per member, and, when any member needs confirmation, an **"Check in the remaining N anyway"** `AppOutlineButton` that resubmits just that subset as a fresh `ScheduleBatchCheckInRequested` with `ignoreWarnings: true` — the bloc's `_onBatchCheckIn` keeps the channel's prior `batchCheckInResult` alive across the retry (rather than clearing it) and merges the retry's (partial) response back into the full breakdown via `BatchCheckInResponse.mergeConfirmed` (replacing only the resubmitted members' rows), so already-resolved rows never disappear; a retry's transport failure surfaces inline on the results step (not a reversion to the picker) so the rendered breakdown is never lost. The shared check-in models + processing/actions views live under `lib/features/check_in/`. Every write — series edit, occurrence override, instance/range cancel, batch check-in — runs through a `_mutateAndReload` (or the dedicated check-in channel) that toggles `isMutating` / `actionError` / `actionSuccessCount` on `ScheduleLoaded` and reloads the board on success — so a cancelled day shows its "Cancelled" badge — mirroring `PlansBloc`. **The chooser dialog, both screens, the batch check-in dialog, and the range-cancel dialog are pushed/shown with `BlocProvider.value` so they share the board's bloc** — a save/cancel/override/check-in reloads the board the user returns to (no caller-await refresh needed); each rides the shared bloc's `actionSuccessCount` (or, for check-in, the dedicated channel) for its terminal state. **Both the series editor and the occurrence screen surface a committed mutation as a success DIALOG** (`AppDialog` reusing the `ScheduleCancelSuccess` body), then pop back to the board — not a full-screen success step. The series editor still blanks to the shared `CenteredProcessingView` while processing; the **occurrence screen instead keeps its content on screen** and overlays a dimmed scrim + spinner (`widgets/occurrence/occurrence_mutation_overlay.dart`'s `OccurrenceMutationOverlay` — a `Positioned.fill` sibling of the content in a `Stack`, mirroring `member_detail_screen.dart`'s `_MutationOverlay`) so the success dialog appears **over the real "This day's details" / actions / roster**, not a blank spinner page; failure (inline error + retry) still renders in-screen on both screens. There is no GET-employees endpoint, so the instructor pickers (per-day on the series editor, single-day on the occurrence screen) are sourced from the real (id, name) pairs already resolved on the gym's classes (`InstructorOption.fromClasses`), not a mock roster; gym-id-scoped via `selectedGym.gymId`) — is built on `flutter_bloc` + `equatable`. Events describe user/system actions; states represent UI state; repositories sit behind the bloc. This is the standard for all new CRM features.
  - **Four documented exceptions** on the member-detail page use a small **read-only side read** against a repository — the fetch lives in the widget, not as a new event/state on `MemberDetailBloc` — kept isolated so they don't bloat the bloc (a section may still *react* to the bloc's shared `refreshToken` to know when to re-fetch; its data never becomes bloc state) — the same shape the edge reads use: (1) the **Waivers section** (`features/member_details/.../sections/member_waivers_section.dart`) over `MembershipsRepository.listMemberWaiverStatus`, which lists only the waivers the member must sign for the memberships they currently hold (the backend `signatures/by-member` query is scoped to the member's non-terminal memberships' plan `waiver_ids`); (2) the **Invoices section** (`features/member_details/.../sections/invoices_section.dart`) over `MemberRepository.listMemberInvoices` + `getUpcomingInvoice`, showing the one overdue-or-upcoming invoice; and (3) the **Payment History section** (`features/member_details/.../sections/payment_history_section.dart`) over `MemberRepository.getPayments` — a **paginated** read (`?limit&offset`, "Show more"), deliberately a separate request from `/billing` so the potentially long charge history isn't bundled into the member-detail payload. It is **grouped one row per invoice** (every charge against an invoice — each retry, the success, and any refunds — folds into that single row, which carries the invoice total as `amount` and the summed `refunded_amount`, with all charges under `attempts`; the query picks a representative succeeded charge for the row's status/payer/charge_id) and surfaces an invoice by **three** paths: the member **paid** it (`member_invoices.paid_by_member_id`), a **membership** they have ever held was on it (matched by `member_memberships.item_id` on the invoice line items, so pre-link invoices stay findable), or it was **for** them (their id is in the invoice's `paid_for` beneficiary list). So a parent paying for this member's class pack shows on **both** pages, a paying parent's UNRELATED invoices never leak here, and each row is labelled with the **payer** (the "Paid by" column = `paid_by_member_id`) while the invoice popup adds who it was **"For"** (`paid_for`). (Billing rows store payer + beneficiaries explicitly — `BillingPaymentRecord.paid_by_*` + `paid_for` — there is no single conflated `member_id`.) And (4) the **one-time Refunded row** (`features/member_details/.../sections/membership_details_loader.dart`, `MembershipDetailsLoader`), which sums `MemberRepository.getPayments`' `refundedAmount` across the charges whose line items carry a one-time / trial membership's `item_id` and shows a "Refunded $X" row on that membership card only once it is partially/fully refunded. The **Invoices**, **Payment History**, and **Refunded-row** side reads all re-fetch when the bloc's `refreshToken` bumps — on every billing change and on each tick of the **post-charge invoice poll** (`InvoicePoller` → 5/10/15/30/60s after a charge / start / refund / mark-paid-cash, restarted on a new charge so only one sequence runs), so a webhook-delivered invoice appears without a manual reload (Payment History resets to page 1, discarding any superseded in-flight page fetch). **The Invoices section also dispatches a real `MarkPaidCashRequested` mutation to `MemberDetailBloc`** for OPEN/overdue invoices (via `MarkPaidCashDialog`) — upcoming invoices show a "cash available once it opens on \<date\>" note and no action. The profile header's **Check In** action opens `presentation/dialogs/check_in/member_class_check_in_dialog.dart` — a two-section class picker (TODAY = Active/emphasized, the LAST 7 DAYS = Past) that `POST`s `/api/v1/checkin` (`is_member:false`) on a dedicated `isCheckingIn` / `checkInResult` / `checkInError` channel on `MemberDetailLoaded` (mirrors the charge-card channel). Check-in is **warn-first with an override**: a clean check-in records — bumping `refreshToken`, the success step names the class + "+N points" and surfaces any gate `warnings` as a non-blocking note — but one that hits a gate warning (no membership / out of classes / ineligible plan / over capacity) comes back with `CheckInResponse.requiresConfirmation` true and **nothing written** (`logId` null, no `refreshToken` bump); the result step then shows the warnings (⚠, `okYellow`) and a **"Check in anyway"** action that re-dispatches the identical `MemberCheckInRequested` with `ignoreWarnings: true` to record it through the gate. The member-detail screen now also provides a `ScheduleRepository` in its scope so the dialog can read those occurrences (cross-feature reuse, a read-only side fetch — no schedule bloc). Only the **Waivers** "Sign waiver" affordance still opens the `ComingSoonDialog` placeholder.
- **Edge / non-CRM screens stay stateless.** The screens that only render content or drive the read-only edge integrations — the **member-app preview** (`features/members/.../member_app_screen.dart` + its tabs), the **theme browser**, and the kept showcase/demo surfaces (growth, the **employees** surface — now the Employees tab of the People screen, `features/employees/.../employees_list_body.dart`, still stateless/mock — and the Settings screen's **QR codes** section) — use `StatelessWidget` for pure display and `StatefulWidget` only for local UI state (tab index, scroll controller) or to host a `FutureBuilder` over an edge read. They do not need a bloc. The **dashboard (`features/home/`) is mixed**: its hero + Live Attendance cards are still mock and stateless, but the **Overdue Payments section** (left column, under Live Attendance) **and the Upcoming Classes card** (right column) are the live, bloc-backed CRM surfaces there. Upcoming Classes reads the **real** schedule feed — `features/home/bloc/upcoming_classes_*` over `ScheduleRepository.listEffectiveInstances` (the same `GET /api/v1/classes/instances` the board uses), self-contained `RepositoryProvider` + `BlocProvider` like Overdue; its request window spans the **recent past (~7 days) through the next ~14 days** — the past part isn't displayed, it's there only so the backend `/classes/instances` read **materializes** any already-ended-but-unrecorded occurrence on dashboard open (the same materialize-on-read the schedule board triggers, since the dashboard is the landing page). The `upcoming_classes_generator.dart` (`upcomingClassesFromInstances`) then drops cancelled occurrences, keeps those **still in session or upcoming** (END time = `occurred_at` + `resolvedDurationMinutes` is after now, so a class currently running is included — not just strictly-future ones), sorts by `occurred_at`, caps the teaser, and day-groups them.

When you add a feature that talks to the FastApiBackend, it gets a bloc. When you add a screen that only renders or drives an edge read, it does not. If you're unsure which side a new screen falls on, ask.

## Repository pattern + ApiClient (the CRM backend path)

- **All FastApiBackend calls go through `ApiClient`** (`lib/core/network/api_client.dart`). It wraps a single configured `dio` instance, attaches the **Supabase JWT** as a Bearer token on every request, applies a **30s timeout**, and on a **401 refreshes the Supabase session (time-bounded) and retries once**; if the refresh fails **or times out** it calls `ApiClient.onUnauthorized` (wired in `main.dart`) to sign the session out, dropping the auth gate back to the login screen. The refresh timeout is essential: gotrue treats a network/host-unreachable refresh failure as *retryable* and keeps retrying without emitting an event, so an unbounded refresh would hang the request — and with it the boot-time gym fetch — leaving the auth gate spinning forever instead of redirecting to login on an expired session. Never create a raw `Dio` or make bare HTTP calls for CRM data — use `ApiClient`.
- **Repositories wrap `ApiClient`.** Each feature's `data/repositories/` exposes domain methods (`getMembersList`, `getMyGym`, `getMember`, …), takes an `ApiClient` in its constructor, converts JSON responses to models, and throws typed exceptions. Blocs depend on repositories, never on `ApiClient` directly. Keep the layering: **Screen → Bloc → Repository → ApiClient → backend.** Never skip a layer.
- **Read the Pydantic schemas (`../FastApiBackend/src/<domain>/<domain>_schema.py`) before calling any endpoint.** They are the authoritative request/response contract. Match the path, method, and every field listed under `required`; model `fromJson` must track the response shape exactly. When the contract changes, update the models in the same change. (`../Database/openapi.json` is an optional gitignored local dump — never committed, never expected to exist, never flagged in review.)

## Models & code generation

- **Models are `json_serializable`.** Each model declares `@JsonSerializable()` and a generated `*.g.dart` part. Add or change a model, then regenerate: `dart run build_runner build --delete-conflicting-outputs`. Commit the regenerated `*.g.dart` alongside the model. Never hand-edit a `*.g.dart`.
- **Resilient enum parsing.** Any enum parsed from JSON must have a safe fallback in its `fromJson` — `firstWhere(..., orElse: () => <default>)` — so a new backend enum value never crashes the UI. Status-like enums get an `unknown` variant; view-like enums fall back to the default (e.g. `all`). Every `switch` on such an enum must handle the fallback case.
- **Money is signed integer minor units** (cents). Model money fields are `int` / `int?` (negative = refund/credit), preserved end-to-end from the backend. Convert to a display string **only at the render layer** via the shared helper in `lib/core/utils/money.dart` — never hand-roll `amount / 100` at a call site.
- **DateTime:** display in local time, send UTC to the backend.
- **Backend string display:** capitalize lowercase backend strings (`'active'`, `'recurring'`) before display — the API hands them to us lowercase.

## Error handling

- **Typed exceptions live in `lib/core/errors/exceptions.dart`** — `AuthException` (and its `InvalidCredentials` / `UserAlreadyExists` / `WeakPassword` / `EmailNotConfirmed` subtypes), `ServerException`, `NetworkException`, `DatabaseException`, `GymConflictException`. Repositories **throw + describe**; blocs **log + handle** (`log('...', error: e, stackTrace: stackTrace)` before emitting an error state) and surface a user-friendly message.
- Every bloc-backed screen renders explicit **loading / loaded / error** states from its state union, with a retry path on error.

## Authentication & access

- **Supabase auth gates the admin app, and only in `main.dart`.** `main.dart` boots Supabase (`SupabaseConfig.initialize`), provides the `LoginBloc`, and mounts the `AuthGate`, which routes: initial/loading → spinner, unauthenticated/error → `LoginScreen`, authenticated → **list the gyms the caller may administer (`GET /api/v1/gyms/`, owner + admin, role-annotated)** and route on the count: **0** → `GymSetupScreen`; **1** → the members workspace scoped to that gym (in a nested `Navigator` sharing the admin route table); **2+** → `GymPickerScreen`, then the workspace once a gym is chosen. Picking activates the gym via `selectedGym.setActiveGym(...)`, whose real UUID then scopes every member view. The whole authenticated subtree tears down on sign-out.
- **The public theme browser stays unauthenticated.** Its entry point (`lib/main_theme_browser.dart` → `ThemeBrowserApp`) never boots Supabase and never mounts the gate — it is a public marketing surface (see *Standalone theme browser*). Do **not** add auth to the theme target.

## Routing & URLs

- **Named routes in `lib/core/navigation/app_routes.dart`**, resolved by `_onGenerateRoute` + `_routeBuilders` in `main.dart`. No router package — section nav runs on the **nested `Navigator`** built in `auth_gate.dart::_MembersWorkspace` (it boots at the URL fragment for deep-linking, and the nav rail uses `pushReplacementNamed`).
- **The URL reflects the current section.** Because only the *root* navigator syncs to the browser bar by default, the nested navigator carries a `UrlSyncObserver` (`lib/core/navigation/url_sync.dart`) that calls `SystemNavigator.routeInformationUpdated` on push/replace/pop for the **addressable** top-level routes (`kAddressableRoutes`), so every section has a live, refreshable, shareable URL. The deliberate **hash** strategy stays (no `usePathUrlStrategy`); browser **Back/Forward is intentionally not wired** (would need the Router API / go_router). **Member detail is deep-linkable by id**: opening a member writes `/members/detail/<memberId>` to the URL (built by `AppRoutes.memberDetailPath`, parsed back by `AppRoutes.memberIdFromPath` in `_onGenerateRoute` → `SpecificMemberScreen`'s id-argument branch, synced by `UrlSyncObserver`), so a reload restores that member; an id that doesn't resolve to a viewable member bounces to `/members` — the bloc stamps the load failure's HTTP status onto `MemberDetailError.statusCode`, and `member_detail_screen.dart`'s listener redirects when `MemberDetailError.isNotFound` (a 4xx — unknown/malformed id or a gym the caller can't see), while a transient 5xx / network error keeps the retryable error view. The remaining detail/form sub-routes (class form, plan/waiver editors) keep their parent section's URL (they read route args and aren't deep-linkable).
- **Member App tabs are deep-linkable.** Videos/Loyalty are tabs inside `MemberAppScreen`, not nav-rail screens, but each has a route — `/members/app-preview/videos` and `/members/app-preview/loyalty` (base path = Theme tab) → `MemberAppScreen(initialTab: …)`. Tab switching stays a local `setState` (so the Theme tab's `ThemeRuntime` catalog isn't re-fetched) and calls `syncBrowserUrl` to reflect the open tab; `AppShell.activeRoute` stays `memberAppPreview` so the rail item stays lit on every tab.

## Stripe billing

- Stripe is initialized in `main.dart` (`Stripe.publishableKey` from env, then `applySettings()`). Billing actions (charge card, refund, invoices, update card, plan/price changes) live in `features/member_details/presentation/dialogs/` and dispatch through `MemberDetailBloc` against FastApiBackend endpoints. `flutter_stripe` / `flutter_stripe_web` / `stripe_js` provide the web payment surface. Read the matching Pydantic schema in `../FastApiBackend/src/<domain>/<domain>_schema.py` before wiring any billing endpoint.

## Testing

- **Use `bloc_test` + `mocktail`.** Blocs hold the business logic, so they get the coverage: build the bloc with a mocked repository, `act` an event, assert the emitted state sequence (loading → loaded/error). Mock repositories and `ApiClient`; never hit a live backend in a test.
- Tests mirror the `lib/` tree under `test/`. Cover error and edge conditions, not just the happy path. `flutter test` (`make test`) before committing.

## Video template integration (live edge feed + gym detail)

The member-app **videos tab** pulls its feed live so the admin previews real thumbnails and titles instead of placeholder art; a second read fetches the selected gym's **detail** (classes / rewards / spec) once into memory.

**"Your videos" is the owner section** (admin context only) — `gym_video_feed` rows with `video_run_id` NULL (run-independent). Fetched with `GymContentRepository.fetchVideos(gymId, owner: true)`; the genre rows are the gym's latest scan run. The owner edits "Your videos" inline:
- **Add** a YouTube link — a **two-step confirm**: `AddVideoDialog` looks the link up (`lookupVideo` → `POST …/videos/lookup`, no write) and shows the fetched title/channel/thumbnail/views for confirmation, then `addVideo` → `POST …/gyms/{id}/videos` commits it. **The backend fetches real metadata from the YouTube Data API** (no URL-only storage). The new `video` pool row is **owned by this gym** (`video.gym_id` set, `added_via='manual'` — a private custom video) and the feed row is inserted into the owner section.
- **Remove from "Your videos"** — a plain confirmation (`ConfirmationModal`, **no "why"**) → `removeVideo(gymId, id, owner: true)`. The backend deletes the owner-section feed row; if the video is `added_via='manual'` (gym-owned custom), it also hard-deletes the pool row.

**Genre-row (latest-run) removes are different** — they keep the **"why"**: `member_feed_section.dart` wires a real `onRemove` (admin only) → `VideoCurationDialog` (the teach-the-agent reason) → `removeVideo(gymId, id, reason)` → the backend **rejects** the latest-run row (`scan_status='rejected'`, `rejection_type='manual'`, optional reason; the pool row is never deleted). Held sections update synchronously from the cached state (no refetch). So: owner-section = confirm + delete-pool-if-manual; genre = why + reject-latest-run-row + keep-pool.

Every video tile (Your videos **and** the genre rows) is clickable — its thumbnail opens the YouTube watch page in a **new browser tab** (`openVideoInNewTab` → `url_launcher` with `webOnlyWindowName: '_blank'`). A preset import seeds a few videos into the owner section on first import (only when the owner section is still empty, so re-imports don't pile up), so "Your videos" isn't blank in the demo (they also appear in the genre rows from the same scan run — harmless). In the **public** theme browser (no real gym) "Your videos" drops out — there's no owner feed to edit. **Destructive buttons use `DesignConstants.badRed`, not `redDark`** (a 25%-alpha wash that renders as a grayed/disabled look).

**Admin preview vs. public browser** — branched on **`selectedGym.gymId != null`**:

- **Admin (real gym, `gymId` set):** detail and video feed read from **UUID-keyed, authed** endpoints via `ApiClient`. The **rejected view is restored**: the "Show rejected" toggle flips the feed between accepted videos and the scan's rejected list; in rejected mode, genre tiles show a **Keep** action (un-reject back to the served feed) instead of remove.
  - Gym detail: `GET /api/v1/gyms/{gymId}/showcase` → `GymDetail` (key `spec`, not `specification`; `GymDetail.fromJson` handles both via `?? json['spec']`). Backed by `lib/features/members/data/gym_content_repository.dart` (`GymContentRepository`). Fetched by `SelectedGym._fetchDetail` and re-fetched by `setVideoGymId` on preset import so Loyalty/classes/schedule refresh immediately. **`setVideoGymId` does NOT touch the theme** — a Settings preset import only changes content; theme selection/application is the Theme tab's job (the imported design id is persisted server-side). Touching the theme here threw when the theme engine wasn't yet initialized and wrongly reported the import as failed.
  - Video feed: `GET /api/v1/gyms/{gymId}/videos` (paginated, `?owner=true` for the owner section, `?rejected=true` for the rejected list) and `/preview?rejected=true` via `GymContentRepository`. The owner-edit endpoints: `POST /api/v1/gyms/{gymId}/videos/lookup` (`lookupVideo` — fetch details for the add confirmation, no write), `POST /api/v1/gyms/{gymId}/videos` (`addVideo`), `DELETE /api/v1/gyms/{gymId}/videos/{video_id}` (`removeVideo` — `?owner=true` deletes from the owner section; else rejects the latest-run row), and `POST /api/v1/gyms/{gymId}/videos/{video_id}/keep` (`keepVideo`), all on `GymContentRepository`.
- **Public browser (`gymId` null):** unauthenticated, slug-keyed template path via `package:http` (`VideoApiClient` / `GymApiClient`). Supabase is not initialized in this target — never call `ApiClient` on this branch.

The discriminator **`selectedGym.gymId != null`** drives this branch in `selected_gym.dart::_fetchDetail`, `member_feed_section.dart::_previewFor` + `_TagPagerState._loadMore`, and gates the admin-only editable "Your videos" section there (`_Feed`/`_AllSections` `showYourVideos`). Keep these consistent; don't scatter the check into unrelated widgets.

- **Feed (template/public path):** `GET /api/v1/videos/templates/{videoGymId}/videos` (video-gym-id-keyed, paginated). The one query knob beyond paging/genre is `?rejected=true`, which serves the scan's **rejected** list (backing the videos tab's rejected-videos section). The "Show rejected" toggle is visible in both admin and public contexts.
- **Gym detail (template/public path):** `GET /api/v1/videos/templates/{videoGymId}` via `lib/features/members/data/gym_api_client.dart` (`GymApiClient`, `package:http`) fetches the template's whole content detail (spec + classes + rewards) **once** into the `SelectedGym` global. The backend response uses `video_gym_id`; `GymDetail.fromJson` falls back to `gym_id` for transition tolerance; and falls back from `specification` key to `spec` key for the showcase response.
- **`video_gym` id ≠ regular gym id — and there is no mapping. `selectedGym` carries BOTH, named separately.** The template catalog keys on a string `video_gym` id (`boxing`, `acro_yoga`, …); the FastApiBackend gym (`GET /api/v1/gyms/`, `GymWithRole`) keys on a **UUID**. They are **separate id spaces**, so `selectedGym` exposes two getters: **`selectedGym.gymId`** = the real gym UUID (set by `setActiveGym` at login/pick; scopes every CRM member query — members list, member-detail roster, plans, discounts) and **`selectedGym.videoGymId`** = the template content key (drives the read-only preview surfaces: feed, loyalty store, content focus, phone preview). (The dashboard Upcoming Classes card no longer reads this — it now reads the real `/classes/instances` schedule feed, scoped by the real `gymId`.) Never pass the real `gymId` to a video template endpoint — it 404s; never scope a member query by `videoGymId`. After login the auth gate calls `setActiveGym` (real gym) **and** seeds `videoGymId` with a **default** `video_gym` (`AppConstants.defaultVideoGymId`, `--dart-define=DEFAULT_VIDEO_GYM`, default `boxing`) for content; the **Theme-tab gym picker** overrides `videoGymId` only; the **Gym presets** Settings section also updates `videoGymId` after a successful import via `selectedGym.setVideoGymId(...)`. If a real gym→video_gym link is ever needed, it's a new schema field + endpoint + setup UI, not a reuse of the UUID.
- **Where it lives:** `lib/features/members/data/` — `video_api_client.dart` (template feed + preview), `gym_api_client.dart`, `gym_content_repository.dart` (authed real-gym showcase + videos; methods: `fetchVideos(owner, rejected)`, `fetchVideoPreview(rejected)`, `addVideo`, `lookupVideo`, `removeVideo(owner, reason)`, `keepVideo`), `gyms_pager.dart` (pages the template catalog for the theme/gym picker), `youtube_url.dart` (`extractYoutubeId`, mirrors the backend extractor, used to validate the add input + derive `Video.videoId`); models in `video_feed.dart` / `gym_detail.dart`. The editable "Your videos" UI is `videos_tab/your_videos_feed.dart` (the stateful preview/full feed with add/remove), `your_video_tile.dart` (`feedVideoTile` + `openVideoInNewTab`), and `add_video_dialog.dart` (paste-a-link). The `StatefulWidget` + `FutureBuilder`/`setState` pattern is the right shape for the widgets that consume these reads/edits (`member_feed_section.dart`, `your_videos_feed.dart`, `library_view.dart`).
- **Dependency:** the FastApiBackend must be running. Base URL defaults to `http://localhost:8000`; override with `--dart-define=BACKEND_BASE_URL=http://<host>:<port>`. (Replaces the old `VIDEO_BASE_URL` / VideoService `:8002` dart-define.)
- **Failure behavior:** the gyms list / gym-detail calls time out after **15s**, the feed after **30s**; all degrade quietly (empty feed / error state) so the rest of the app stays up if the service is down.
- **`package:http` is whitelisted for the public/template integration only.** Do not reuse `VideoApiClient` or `package:http` to wire other screens to a backend — CRM data goes through `ApiClient`. The admin video/showcase reads use `GymContentRepository` (ApiClient-backed). (The ThemeService integration below does not use `http`; it rides `theme_flutter`'s own `dio` client.)

## Video-agent Settings section

The **Settings screen** includes a **Video feed config** section that opens a conversational
screen where the gym owner chats with an LLM agent to author the gym's video-feed
spec (keep/avoid criteria).

- **Entry:** `features/settings/presentation/sections/video_agent_settings_section.dart`
  — a button that pushes `AppRoutes.videoAgent` (`/settings/video-agent`).
- **Architecture:** full Bloc feature (`features/video_agent/`) — `VideoAgentBloc`,
  `VideoAgentRepository` (placed at `features/members/data/video_agent_repository.dart`
  next to `GymContentRepository`). Models at `features/video_agent/data/models/`.
- **Screen:** `features/video_agent/presentation/screens/video_agent_screen.dart`.
  Uses `AppShell(activeRoute: AppRoutes.settings)`. On open: calls `refineFromFeed`
  (404 = no-op) then `getConfig` (404 = empty state). The bloc carries the agent history
  across turns (stateless backend).
- **Backend contract (final):**
  - `GET  /api/v1/gyms/{gymId}/video-spec` → `VideoSpecView` or 404.
  - `POST /api/v1/gyms/{gymId}/video-agent` body `{ message, history, accepted_spec? }`
    → `{ reply?, draft?, question?, history, saved, usage? }`. Exactly one of
    reply/draft/question is set per turn. `accepted_spec` is the criteria-only map
    (`VideoSpecDraft.toJson()`); when present the backend saves and returns `saved: true`.
  - `POST /api/v1/gyms/{gymId}/video-agent/refine-from-feed` → `VideoSpecView` or 404.
  - **`PUT /video-spec` and `POST /generate-queries` do not exist and must never be called.**
- **Draft flow:** agent turn → `pendingDraft != null` → `VideoAgentDraftPanel` surfaces
  Confirm & Save / Keep chatting. **Confirm dispatches `VideoAgentDraftConfirmed` → the
  bloc sends a new agent turn with `accepted_spec = draft.toJson()`.** On `saved == true`
  in the response: the agent's reply is appended to chat, the draft is cleared, a
  SnackBar confirms, and `savedConfig` updates — **the chat stays open** (no terminal
  state; owner may continue chatting). Error is shown inline in the draft panel with a
  retry; the draft stays visible. Never a silent dismiss.
- **Queries are never shown to the gym owner.** `VideoSpecView` carries `queries` in its
  model (the backend includes them) but neither `VideoAgentCurrentPanel` nor
  `VideoAgentDraftPanel` renders them. Queries are a server-side search concern only.
- **Multi-choice question chips:** when an agent turn returns a non-null `AgentQuestion`,
  `VideoAgentQuestionChips` renders the options above the input bar.
  - `multiSelect == false` (single-select): tapping a chip immediately sends that option
    as the next turn's message and clears the question.
  - `multiSelect == true`: chips are toggleable; a "Send" button sends the comma-joined
    selection once at least one chip is chosen.
  - The text input bar stays available so the owner may type a custom reply instead.
  - Sending any message (typed or chip) clears the pending question.
- **Widgets:** `VideoAgentCurrentPanel` (saved spec, markdown via `flutter_markdown_plus`;
  no queries), `VideoAgentChatList` (reuses `AgentMessageBubble` / `UserMessageBubble`),
  `VideoAgentDraftPanel` (no queries), `VideoAgentQuestionChips` (multi-choice answer
  surface), `VideoAgentInputBar` (stateful, Shift+Enter = newline, Enter = send).

## Gym presets Settings section (owner1-only preset import)

The **Settings screen** includes a third section, **Gym presets**, that lets an authorized admin apply a template (videos + classes + rewards + theme) to the current real gym in one step.

- **Gate:** only rendered when the logged-in email is `kPresetAdminEmail = 'owner1@test.com'` (read from `Supabase.instance.client.auth.currentUser?.email`) AND `selectedGym.role == EmployeeRole.owner`. The backend also enforces an allowlist server-side — the gate is a UI convenience, not a security boundary.
- **Architecture:** a full Bloc feature (`features/presets/`) — `PresetsBloc` + `PresetsRepository`. The repository wraps `ApiClient` for both the catalog browse (`GET /api/v1/videos/templates`) and the import (`POST /api/v1/gyms/{gym_id}/presets/import`). The section lives in `features/settings/presentation/sections/gym_presets_section.dart` and is composed of three sub-widgets (`gym_presets_section.dart` → `gym_presets_content.dart` → `gym_presets_template_card.dart`), each ≤150 lines.
- **Import flow:** the admin picks a template card → taps "Apply preset" → `PresetsBloc` POSTs the import → on success calls `selectedGym.setVideoGymId(videoGymId, designId)` so the member-app preview immediately reflects the imported gym. The `PresetsImportResponse` carries `videos_imported`, `classes_imported`, `rewards_imported`, and `theme_design_id`.
- **Post-import refresh:** `setVideoGymId` now triggers `SelectedGym._fetchDetail` in the admin context (`gymId != null`), which re-fetches `GET /api/v1/gyms/{gymId}/showcase` via `GymContentRepository`. This means the Loyalty rewards, classes, and schedule surfaces update in-memory immediately after import without a page reload, because they read from `selectedGym.detail`.
- **The import writes real backend tables** (gym_video_spec, gym_classes, gym_rewards, gym_video_feed); the admin preview reads the real gym data via UUID-keyed authed endpoints, not the template slug catalog.

## ThemeService integration (read-only live theme preview)

The member-app **Theme tab** (`member_app_screen.dart` → `LiveThemePreviewTab`) is a **live theme preview**: a phone frame renders branded member-app showcase screens that re-theme the instant the admin picks a theme. Second deliberate read-only edge integration.

- **How it works:** depends on the shared **`theme_flutter`** package (path dep, `../ThemeService/ThemeFlutter`) for the customization **runtime + resolvers** only. The **showcase widgets live locally** in `lib/showcase/` (this app is their only consumer); they resolve branding through `theme_flutter`'s `ThemeColor` / `ThemeImage` / `ThemeFont` / `ThemeText` / `ThemeIcon`. The tab calls `ThemeRuntime.initialize(...)` once (lazily, idempotent), `fetchStyles()` for the catalog, and `selectDesign(id)` on tap.
- **Scope:** read-only. The engine fetches resolved branding + the catalog (`GET /apps/{appId}/styles`) and per-style assets. **No writes, no persistence** — a pick drives only the in-session preview; saving a gym's chosen theme is future work (a DB table + a FastApiBackend endpoint).
- **Where it lives:** tab chrome in `lib/features/members/presentation/widgets/member_app/theme_tab/` + the shared `lib/shared/widgets/phone_frame.dart`; the showcase screens it renders are the self-contained `lib/showcase/` module (screens + router, slots, content, tokens, assets, and `celebrations/` / `home/` / `rewards/` / `support/` subfolders; bundled fallbacks in `assets/showcase/`). The catalog model is the engine's `ThemeStyle` (no CRM-side duplicate — consume the engine's, DRY).
- **Dependency:** the ThemeService read-only API must be running. Base URL defaults to `http://localhost:8001`; override with `--dart-define=CUST_BASE_URL=http://<host>:<port>`.
- **Failure behavior:** the engine's resolvers never throw — they fall back to bundled defaults. The catalog grid degrades quietly (error message, no crash) if the service is down; the phone still renders the fallback look.
- **Two design systems coexist, intentionally.** Inside the phone frame the showcase uses its own member-app tokens (`lib/showcase/showcase_tokens.dart` — `ShowcaseTokens`, which resolve the tenant brand live); everything around it uses CRM's own `DesignConstants`. **`ShowcaseTokens` is NOT `DesignConstants` — never merge them.** They describe two different surfaces (the previewed *member* app vs. the admin chrome). Don't make the preview match the admin chrome.

## Standalone theme browser (second build target)

The Theme tab doubles as a **public theme browser** the marketing landing page links to (prospects browse the theme library live). It ships as a **second build target of this same app** — not a separate package — so one codebase powers both surfaces.

- **The module is `LiveThemePreviewTab`** (`features/members/.../theme_tab/live_theme_preview_tab.dart`). The admin preview embeds it; the standalone target mounts it full-screen. It is self-contained (bootstraps `ThemeRuntime`, owns its selection state via the `selectedGym` global + `GymsPager`). Its one host-specific knob is `routePath` (the URL path the previewed theme mirrors onto as `?theme=…`): default `AppRoutes.memberAppPreview` (embedded), `AppRoutes.home` for the standalone.
- **The standalone shell lives in `features/theme_browser/`** — `theme_browser_app.dart` (a minimal `MaterialApp` reusing `AppTheme.light`), `theme_browser_page.dart` (full-screen: top bar + module, no nav rail), `widgets/theme_browser_top_bar.dart`. Entry point: `lib/main_theme_browser.dart` (no Supabase, no auth gate).
- **It shares `DesignConstants` with the admin app** so the catalog grid looks identical embedded and standalone. What differs is the chrome: the admin nav rail vs. the browser's landing-style **top bar** (CombatDen logo + wordmark · Home / Pricing links · gradient "Book a demo" CTA, reusing `AppPrimaryButton`), responsive below `navMobileBreakpoint` (768px) into a hamburger + frosted dropdown (`theme_browser_mobile_menu.dart`). Link targets are dart-defines: `LANDING_URL`, `PRICING_URL`, `BOOK_URL`.
- **URL strategy is the Flutter web default (hash)** — no `usePathUrlStrategy` (it would change the admin app's URLs too). Deep links round-trip via the fragment; `_themeFromUrl` tolerates both strategies.
- **Same edge integrations.** The standalone hits the same read-only ThemeService + VideoService; both must be running locally (`:8001` / `:8002`); prod uses the same two dart-defines.
- **Build / deploy:** `make run-themes` (dev, 8082), `make build-themes`, `make deploy-themes` (themes.combatden.net). See *Production deployment*.

## Sibling systems in this monorepo

- `../FastApiBackend/` — the CRM's primary backend. All members / member-detail / gym-setup / billing calls go here via `ApiClient`. Contract: Pydantic schemas in `../FastApiBackend/src/<domain>/<domain>_schema.py`.
- `../Database/` — Supabase schemas, RLS, enum mirrors. `openapi.json` is an optional gitignored local convenience dump (never committed, never expected to exist).
- `../VideoService/` — the video data pipeline (scrape / scan). The CRM's video template endpoints are now served by the FastApiBackend (`/api/v1/videos/templates*`), not directly by VideoService. VideoService is still the source of video data but is no longer a runtime dependency of the CRM.
- `../ThemeService/ThemeFlutter/` — the shared `theme_flutter` white-label runtime + resolvers (path dep) for the theme preview.
- `../MobileApp/` — the member-facing mobile app, which shares this app's design language. Shared widget candidates often live there too (check before building new shared widgets).
- `../LandingPage/` — React marketing site. Its `COPY` dict and `hifi/ds.jsx` design system inform admin copy/voice and the landing-aligned tokens. Read `../LandingPage/CLAUDE.md` for user-facing strings that should match marketing voice.

## Search the web for conventions before designing

When the UX question is "how do good apps usually present X?" — login flows, empty states, error states, onboarding, list/detail patterns, settings, paywalls, billing screens, password reset, etc. — **search the web first.** Look at what proven web apps actually ship (Stripe Dashboard, Linear, Notion, Vercel, Intercom admin). Don't guess.

Why: convention is a usability shortcut. Users pattern-match to flows they've seen elsewhere; a novel treatment of a normalized interaction feels wrong even when it's "creative," and guessing wastes iteration cycles when the answer is publicly documented.

How: for normalized patterns, run a WebSearch + WebFetch a few real apps before proposing a layout; reference Material 3 where it applies; quote the convention you found. Skip the search for genuinely product-specific work (this product's unique mechanic, our brand voice, internal logic).

## General Principles

**SOLID** — single responsibility, open/closed, substitutable subtypes, segregated interfaces, depend on abstractions.
**DRY** — single source of truth for each piece of logic.
**KISS** — favor simplicity over complexity.
**YAGNI** — don't add features until needed.
**Separation of Concerns** — keep UI, business logic (bloc), and data (repository) separate.

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the code genuinely diverges from what this CLAUDE.md says (a new backend call, a renamed system, an added dependency, a rule the code has outgrown on purpose, a feature that changed the architecture), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Theming System

**CRITICAL: ALWAYS Use DesignConstants**

- **EVERY widget MUST import and use `package:crm/core/constants/design_constants.dart`.**
- **NEVER hardcode colors** — no `Colors.red`, no inline `Color(0xFF...)`, no copy-pasted hex codes.
- **NEVER hardcode font properties** — no inline `fontFamily`, `fontSize`, or `fontWeight`. Use the text styles in `DesignConstants` (`h1`, `h2`, `h3`, `p`, `pBig`, `pSmall`, etc.).
- **NEVER hardcode spacing, padding, radius, or border widths.** Use `DesignConstants.spacing*`, `DesignConstants.padding*`, `DesignConstants.radius*`, `DesignConstants.buttonBorderSize`.
- **A token is never something you inline.** If you find yourself typing a hex code, a `Color(0xFF...)`, or a literal pixel number for spacing/radius/padding, stop. Use the constant — or ask if a new one needs to exist. The whole point of theming is that one edit to `design_constants.dart` reskins the entire app; that property dies the moment a single screen inlines a value.
- **`design_constants.dart` is this app's own design system and may be edited deliberately.** CRM's tokens are **landing-aligned** — they match the marketing landing page's design system (`../LandingPage/hifi/ds.jsx`) so the public theme browser reads as an extension of it: cool off-white ground (`#F3F5F8`), white lifted cards with soft layered shadows (`cardShadow` / `buttonShadow`), the sapphire accent + its `primaryGradient`, Geist (`baseFont` / `monoFont`), tight 12/8 corners with 20px object cards. It is **not** byte-for-byte identical with `../MobileApp/` — do **not** mirror token changes to it. Keep all token changes centralized in this file (so one edit reskins the whole app) and add/rename tokens only when the design genuinely needs it. See `DESIGN.md` for the system.
- **ALWAYS reference DesignConstants** for every color, text style, padding, radius, and spacing.
- **Light + dark are both live.** The **color, gradient, shadow, and text-style** tokens are *getters* that resolve through `themeController.isDark` (`lib/core/state/theme_controller.dart`), so one mode change re-skins the whole app — the two palettes sit side by side in `design_constants.dart` as private `_l*` (light) / `_d*` (dark) constants. **Consequence: those tokens are no longer `const`** — never put a `DesignConstants` color/textstyle/shadow inside a `const` constructor (drop the `const`; the analyzer is the gate). Spacing / radius / icon-size / nav-dim tokens and the fonts stay `const` / `final`. Add a *pair* of values (light + dark) when you add a color token. `onAccent` is the label color for a sapphire/gradient fill (near-white in both themes) — use it for selected pills / button labels, never a raw `surface`/`backgroundColor`. `onAccent` is only safe on a fill that is dark in **both** themes; for a *solid* `backgroundColor` whose luminance flips between themes (e.g. `okYellow` — dark amber in light, bright gold in dark), use `onFill(fill)`, which picks near-white or near-black ink by the fill's luminance (`AppPrimaryButton` does this automatically for a passed `backgroundColor`).

**Icons: Prefer Material Symbols, Material `Icons.*` allowed**

- **Default to `Symbols.*_sharp`** from `package:material_symbols_icons/symbols.dart` — the design system's primary glyph set, carrying the variable `weight` axis the look depends on. (That variable `weight` axis is exactly why prod builds must pass `--no-tree-shake-icons` — see *Production deployment*.)
- **`Icons.*` from Flutter's built-in Material icons is permitted.** The design system is its own fork and isn't locked to one icon family; `Icons.*` values are plain `IconData` and are fine to use directly — including stored on plain models.
- **Set `weight: DesignConstants.iconWeight` on `Symbols.*_sharp` icons** (it drives stroke weight). Plain `Icons.*` glyphs don't honor the weight axis, so it's a no-op there — don't bother.
- **NEVER hardcode `size:` on any `Icon()`** (either family). Use `DesignConstants.iconSize*` — `iconSizeBig` (32), `iconSizeLarge` (24), `iconSizeMedium` (20, default), `iconSizeSmall` (18), `iconSizeTiny` (16). Same Big→Tiny cadence as `spacing*`. If a size doesn't match one, snap to the nearest token or ask before adding a new one.
- Good: `Icon(Symbols.person_sharp, size: DesignConstants.iconSizeMedium, weight: DesignConstants.iconWeight)`
- Also fine: `Icon(Icons.person, size: DesignConstants.iconSizeMedium)`

**App Theme**

- `AppTheme.current` (`lib/shared/themes/app_theme.dart`) maps DesignConstants into Material 3's `ColorScheme` + `TextTheme` at the active brightness so stock Material widgets auto-theme. `main.dart` wraps `MaterialApp` in a `ListenableBuilder` on `themeController` and passes `theme: AppTheme.current`, so a mode change repaints the whole tree at once (the app never reads `Theme.of(context)` — DesignConstants is the real driver, and it's kept the single source of truth: `AppTheme.current` reflects `themeController.isDark`, never the reverse).
- For widget-specific styling beyond the global theme, reach into `DesignConstants` directly. Don't add one-off overrides at the call site.

**Light / Dark / System (per-employee, persisted)**

- The active mode lives in the global `themeController` (`ThemeController`, a `ChangeNotifier` like `selectedGym`); `DesignConstants.isDark` keys off it. `System` follows the OS — `main.dart`'s root observer feeds platform brightness in via `themeController.setPlatformBrightness`.
- **The choice persists per employee** in `gym_employees.theme_preference` (a `theme_mode` enum: `system`/`light`/`dark`). It rides along on `GET /api/v1/gyms/` (`GymWithRole.themePreference`) and the auth gate's `_activate` hydrates it at login (the **active gym's** value wins); the **Settings → Appearance** control saves changes via `PUT /api/v1/gyms/{gymId}/employees/me/theme` (`features/settings/` — `SettingsBloc` applies the theme optimistically to `themeController`, then persists and reverts on failure).
- **The standalone theme browser is light-only** (a marketing surface matching the landing page): `main_theme_browser.dart` pins `themeController` to `ThemeMode.light` and never mounts the Settings control, so every token resolves light there regardless of the visitor's OS. The `lib/showcase/` member-app preview is unaffected — it resolves the tenant brand through `ShowcaseTokens`, not `DesignConstants`.

## Dart Standards

**Imports**
- **ALWAYS use package imports** (`package:crm/...`) — never relative imports.
- Good: `import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';`
- Bad: `import '../data/repositories/members_list_repository.dart';`

**Naming**
- Files: `member_row.dart`, `members_list_repository.dart`, `member_detail_bloc.dart`.
- Classes: `MemberRow`, `MembersListRepository`, `MemberDetailBloc`.
- Functions/variables: `getMembersList`, `memberCount`.
- Constants: `kMaxItems`. Private: `_internalVar`, `_PrivateWidget`.
- Blocs: `FeatureBloc`, `FeatureEvent`, `FeatureState`.

**Formatting**
- Max 80 characters per line.
- **Hand-format. Do NOT run `dart format` / `make format` in this app.** The repo isn't format-clean, so a blanket format rewrites ~60 files — including the deliberately-forked `design_constants.dart` — and buries your actual change in churn. Match the surrounding style by hand instead.
- **`flutter analyze` (`make analyze`) is the gate, not formatting.** Keep it clean before committing.
- Trailing commas on multi-line widget trees for clean diffs.

**Type Hints**
- Always annotate function parameters and return values.
- Use `?` for nullable types. Use generics (`List<MemberRow>`, `Map<String, int>`).

## Code Complexity & File Organization

- **Prefer deep module trees over flat files** — many small files beats few big ones.
- **Aggressively extract sub-widgets and helper functions.** Each unit short and readable.
- **Extract to a separate file early.** If a widget has a distinct responsibility, give it its own file immediately.
- **Use Column/Row with `spacing:`** to structure layouts — keeps trees shallow.
- Good: A parent widget composing 3–4 named children, each in its own file.
- Bad: A single `build` method with deep nesting and inline widget construction.

**File length**
- Aim for **under ~150 lines per file**.
- One public widget per file. Private helper widgets in the same file are fine only if very small (<30 lines) and tightly coupled.

**Group related widgets into subfolders.** Avoid flat widget directories with many files:
- `presentation/sections/` — `profile_header_section.dart`, `membership_carousel.dart`, `payment_history_section.dart`, etc.
- `presentation/dialogs/` — one dialog per file (`charge_card_dialog.dart`, `freeze_account_dialog.dart`, …).
- Standalone widgets can stay flat.

Helper functions (formatters, display builders) live in their own `*_helpers.dart` / `*_format.dart` file inside the subfolder (e.g. `member_detail_format.dart`, `membership_display_helpers.dart`).

## Screen Layout & Spacing

**Horizontal padding**
- Use `DesignConstants.screenHorizontalPadding` for all screen-level horizontal padding. Visual consistency across screens is non-negotiable.

**Spacing rules**
- **NEVER use `SizedBox` for spacing.** Always use the `spacing:` parameter on `Column`/`Row`.
- **Use `DesignConstants.spacing*` constants for every spacing value.** Available: `spacingBig` (32), `spacingLarge` (16), `spacingMedium` (8), `spacingSmall` (4), `spacingTiny` (2).
- Good: `Column(spacing: DesignConstants.spacingLarge, children: [...])`
- Bad: `SizedBox(height: 16)` between Column children.
- If children need different spacing, restructure into nested Column/Row groups with uniform `spacing:` on each — do not fall back to SizedBox.
- **Exception — `ListView.separated`:** a `SizedBox` returned from its `separatorBuilder` is fine and encouraged (the rule targets one-off `SizedBox`es wedged between `Column`/`Row` children; `ListView.separated` has no `spacing:`). Keep the height on a `DesignConstants.spacing*` constant.
- **Never use `margin`** on Container/DecoratedBox for spacing between widgets — use the parent's `spacing:`.
- **Never use `Padding` to create a gap between sibling widgets** — gaps belong to the parent's `spacing:`, not to either sibling. Padding is only for the *inside* of a single widget (screen-edge containment, internal content padding). If you're adding `EdgeInsets.only(top: ...)` to make space below a previous widget, stop — that's a gap; wrap the siblings in a `Column`/`Row` with `spacing:`. For sliver layouts where you can't share a Column, combine adjacent `SliverToBoxAdapter`s into a single Column with `spacing:` rather than padding each separately.
- If a repeated spacing pattern doesn't match an existing constant, extract a helper. Do not scatter magic numbers.

## Section Structure & Gap Hierarchy

A screen is usually a stack of **Sections**. Each Section is a `Column` with a Title and its Content, using `spacing: DesignConstants.spacingLarge` between them.

The Content is itself a `Column` (or similar) with `spacing: DesignConstants.spacingMedium` between its grouped pieces (subtitles, rows, cards).

Inside those pieces, the innermost groups use `spacing: DesignConstants.spacingSmall` (or `spacingTiny`) for tightly related elements — a label and its value, icon + text, chips in a row.

**Why the cascade**: gap size communicates relationship. Elements that belong together the most get the smallest gap; unrelated things get the biggest. A Title and its Content are *less* tightly related than the items *within* the Content, so the Title→Content gap must be larger than the gaps inside the Content. The same logic applies one level down.

The default cascade as you descend is `spacingLarge → spacingMedium → spacingSmall`. This holds ~90% of the time; it is a default, not a strict rule — skip a level when the design actually calls for it.

**Split widgets at the Title/Content boundary** — the spot where the gap jumps to `spacingLarge` is also the natural boundary for a new widget *class*. A Section's `build` typically returns `Column(spacing: spacingLarge, children: [Text(title, ...), _Content(...)])` and nothing else, with `_Content` handling the medium-gap layer.

Good:
```dart
class ProfileSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge, // title -> content
      children: [
        Text('Profile', style: DesignConstants.h1),
        _ProfileContent(member: member),
      ],
    );
  }
}

class _ProfileContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingMedium, // between content groups
      children: [
        _NameRow(member: member),       // internally: spacingSmall
        _MembershipRow(member: member), // internally: spacingSmall
        _ActionButtonsRow(),
      ],
    );
  }
}
```

Bad: one flat `Column(spacing: spacingMedium, children: [title, subtitle, row1, row2, row3])` — the title gets the same gap as unrelated rows, flattening the hierarchy.

Bad: `spacingSmall` between title and content and `spacingLarge` between rows — inverted cascade.

Bad: nesting the cascade but cramming it into one giant `build` method — the cascade reveals the split points; honor them by extracting each level into its own widget class.

## Screen Architecture

- **Screens are collections of small, focused widgets** — not monolithic build methods.
- Break screens into logical sections (`ProfileHeaderSection`, `MembershipCarousel`, `PaymentHistorySection`).
- Each section has a single, clear responsibility.

**Widget naming**
- Section widgets: `[Content]Section` — `RetentionSection`, `PersonalInfoSection`.
- Item widgets: `[Item]Card`, `[Item]Tile`, `[Item]Item`.
- Grid/List widgets: `[Content]Grid`, `[Content]List`.
- Avoid generic names like `CustomWidget`, `WidgetOne`.

**BLoC integration in widgets**
- **Widgets dispatch events to the bloc** — never call repository methods directly.
- **Widgets listen to state changes** via `BlocBuilder` / `BlocListener` / `BlocConsumer`.
- **No callbacks for business logic** — use bloc events. Callbacks are fine for simple UI interactions (a button `onTap`, a form field `onChanged`).
- Good: `context.read<MemberDetailBloc>().add(MemberActionErrorCleared())`
- Bad: passing an `onSave` business-logic callback through widget layers.

**Widget separation**
- Default to extracting into its own file. If a widget has a clear name and responsibility, it gets a file.
- **Default location is shared.** A widget belongs in `lib/features/<feature>/presentation/widgets/` only if it's specifically tied to that feature's content. Topbars, buttons, cards, list rows, tables, dialogs, dividers, info rows, badges, chips, sections — all live in `lib/shared/widgets/`. **When unsure, prefer shared.** Moving a feature widget to shared later is cheap; building two parallel versions is not.
- One public widget per file.
- **MANDATORY: check `lib/shared/widgets/` before writing a single line of new widget code.** Run `ls lib/shared/widgets/` (and `ls lib/shared/widgets/*/`) BEFORE composing widgets. If a shared widget covers the pattern (cards, buttons, headers, tables, list rows, info rows, dialogs, search boxes, filter bars, view switchers, etc.), USE IT. Do not build a parallel implementation. Pass parameters or extend the shared widget — the point of the library is that every screen looks identical because every screen uses the same primitives.
- **Tables specifically:** any table (header row + data rows + dividers + sticky-or-not + tappable-or-not) is `AppDataTable` from `lib/shared/widgets/app_data_table.dart`. Configure `AppDataTableColumn` and `AppDataTableRow` — do not handroll headers, rows, or dividers.
- **Before building a new shared widget, also check `../MobileApp/lib/shared/widgets/`.** The member app shares this design language. If a version of the pattern exists there, copy and adapt it (rewrite imports `package:mobile_app/` → `package:crm/`) rather than building from scratch. The goal is parity, not divergence.
- **If you skip this check, you will be asked to redo the work.** This has happened — a contributor built a custom table when `AppDataTable` was sitting in shared, and it had to be torn out and rewritten.

## UX Requirement: logout access

Every authenticated screen must offer a way to sign out. Authenticated screens wrap themselves in `AppShell`, which carries the sign-out path in its nav chrome — pinned to the bottom of the left `SectionsBar` rail at desktop widths, and in the hamburger dropdown (`SectionsMobileMenu`) below `navMobileBreakpoint`. Never ship an authenticated screen with no way out.

## UX Requirement: every mutation ends in a visible confirmation, never a silent dismiss

**No data-changing flow may end with just a spinner that then disappears.** Every action that mutates state — charge, refund, upgrade, reprice, cancel, freeze, end, start, mark-paid-cash, save — must resolve to an **explicit terminal state the user sees**: a success confirmation on success, or a clear error with a retry path on failure. A dialog must **never** dispatch its bloc event and immediately `Navigator.pop()` — that reads as "loading… gone" and leaves the user unsure whether it worked. This is non-negotiable for billing, where "did my card actually get charged / refunded?" ambiguity is unacceptable.

- **The shape:** select/preview → **processing** (spinner) → **success / failure** terminal step that the user dismisses. The canonical implementation is the charge-card dialog's `_ChargeStep { payer, payment, processing, success }` (`dialogs/charge_card_dialog.dart`) ending on `ChargeCardSuccessView` (a green `Symbols.check_circle_sharp` naming what happened); the cancel dialog's `_Phase { select, review, complete }` is the same shape with an outcome list.
- **Confirm against COMMITTED state, not "request sent."** Either observe a **dedicated** per-action success channel on `MemberDetailLoaded` (the monotonic-token pattern — `chargeCardSuccess`, snapshotted at open and watched via a `BlocListener`/`BlocConsumer` with `listenWhen`), or `await awaitMemberDetailSettle(bloc, tokenBefore)` (`dialogs/member_detail_bloc_settle.dart`) before showing success.
- **A dialog that owns its own processing→success step must ride a dedicated channel**, not the generic `_runMutation` `isMutating` flag — otherwise the screen-level `_MutationOverlay` spinner and `BillingErrorDialog` fire underneath/alongside it and collide with the dialog's own confirmation. (Charge-card and cancel deliberately route around the screen overlay this way; `update price`/reprice still rides the generic path and is a known gap to close when touched.)
- This is the bar for new flows **and** for any existing fire-and-pop flow you touch.

## Project Structure

```
lib/
├── main.dart                      # admin app entry — Supabase + Stripe + auth gate
├── main_theme_browser.dart        # public theme-browser entry (no auth)
├── core/
│   ├── config/                    # environment + Supabase config
│   ├── constants/                 # design_constants.dart (forked), app/env constants
│   ├── errors/                    # exceptions.dart (typed exception hierarchy)
│   ├── navigation/                # app_routes.dart
│   ├── network/                   # api_client.dart (JWT dio + 401 refresh)
│   ├── state/                     # selected_gym.dart (app-wide gym pick)
│   └── utils/                     # money.dart, validators.dart, ...
├── features/
│   └── <feature>/
│       ├── bloc/                  # CRM features: bloc + event + state
│       ├── data/
│       │   ├── models/            # json_serializable models (+ *.g.dart)
│       │   └── repositories/      # wrap ApiClient, throw typed exceptions
│       └── presentation/
│           ├── screens/
│           ├── sections/
│           ├── dialogs/
│           └── widgets/
├── shared/
│   ├── themes/app_theme.dart      # ThemeData ← DesignConstants
│   └── widgets/                   # cross-feature reusables (AppDataTable, ...)
└── showcase/                      # member-app preview screens for the theme tab
                                   # (see ThemeService integration)
```

## Development Commands

- `make run` — serve the admin web app on `http://localhost:8081`.
- `make run-themes` — serve the standalone theme browser on `http://localhost:8082` (second target). Runs alongside `make run` on its own port.
- `make analyze` — static analysis. **Must be clean before committing — this is the gate.**
- `make format` — `dart format lib test`. **Avoid in this app** (see *Formatting*): it churns ~60 files including the forked `design_constants.dart`. Hand-format instead.
- `make test` — run all tests.
- `make get` — `flutter pub get`.
- `make clean` / `make reset` — clean build artifacts / clean + get.
- `make doctor` — `flutter doctor`.
- Code-gen: `dart run build_runner build --delete-conflicting-outputs` after adding/changing a `json_serializable` model.

## Code Quality

- **Always run `flutter analyze` after making code changes.** Fix every warning and error.
- **Zero warnings policy.** No deprecated APIs (use `.withValues()` instead of `.withOpacity()`, etc.).
- **Const constructors** wherever possible.
- Full null safety.
- No hardcoded values (see *Theming System*).

## Dependencies

- **Add dependencies with `flutter pub add <package>`.** Never edit `pubspec.yaml` by hand. Dev deps: `flutter pub add --dev <package>`.

**This list documents only dependencies that carry rules or scope** — what they're for and where they may (or may not) be used. A routine, self-explanatory UI utility does not need a line here; only document a dependency when its use is scoped, restricted, or architecturally significant.

Scoped / significant dependencies:
- `flutter_bloc` / `equatable` — state management for the CRM feature stack (login, gym setup, members list, member detail + billing). Events/states use `equatable`.
- `dio` — HTTP client behind `ApiClient` for the FastApiBackend (CRM data). Distinct from the `theme_flutter` transitive `dio` — this is the direct CRM dep; route every CRM call through `ApiClient`, not a raw `Dio`.
- `supabase_flutter` — auth (JWT for `ApiClient`, session refresh) and real-time DB for the CRM stack. Gated in `main.dart`; absent from the theme-browser target.
- `flutter_stripe` / `flutter_stripe_web` / `stripe_js` — Stripe payment collection (member-detail billing dialogs).
- `get_it` — service locator for DI across CRM features.
- `json_annotation` / `json_serializable` / `build_runner` — code-gen for API response models (`*.g.dart`).
- `flutter_dotenv` — loads `.env.dev` / `.env.prod` at startup for Supabase / Stripe / `API_BASE_URL` (see *Configuration*).
- `intl` — date/currency formatting. `uuid` — local UUIDs for optimistic creates. `stream_transform` — bloc stream operators (debounce/switchMap).
- `web` — Flutter web interop (required by `stripe_js`).
- `google_fonts` — Geist (the landing typeface) via `GoogleFonts.geist()` / `GoogleFonts.geistMono()` (referenced by `DesignConstants.baseFont` / `monoFont`).
- `material_symbols_icons` — `Symbols.*_sharp` icons.
- `flutter_markdown_plus` — renders the video-agent view's read-only prompt panel (the feed's markdown `videos_desc` / `avoid_desc`). Styling from `DesignConstants`. Used only there.
- `flutter_quill` / `markdown_quill` / `markdown` — **the waiver rich-text editor only** (`features/memberships/.../waiver_editor_screen.dart` + `widgets/waiver_markdown_editor.dart`). The gym owner edits formatted text; the body is stored as a **Markdown string** (`MarkdownToDelta` to load, `DeltaToMarkdown` to save). `appflowy_editor` was evaluated first but does not compile on the pinned Flutter SDK. Scoped to the waiver editor — don't reuse for other rich-text needs without revisiting.
- `http` — **for the public video-template reads only** (see above). Backs `VideoApiClient` / `GymApiClient` / `GymsPager` and nothing else; CRM data goes through `ApiClient`.
- `theme_flutter` (path dep, `../ThemeService/ThemeFlutter`) — **for the live theme preview only** (see *ThemeService integration*). The shared white-label runtime + resolvers (showcase screens live locally in `lib/showcase/`). Transitively pulls `dio`, `flutter_svg`, `get_it` — **not** a license to wire `dio` into screens outside the theme preview.
- `cached_network_image` — **for `lib/showcase/` only** (backs `ShowcaseAsset.network` loading the gym's reward/class photos in the preview). Scoped to the showcase.
- `url_launcher` — **only** the standalone theme browser's top bar (Home / Pricing / Book-a-demo links).

## Configuration (dual: dart-defines + dotenv)

Two config mechanisms, by design:

- **dotenv (`.env.dev` / `.env.prod`)** carries the CRM stack secrets/URLs loaded at startup via `flutter_dotenv`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL`, `STRIPE_PUBLISHABLE` (keys in `lib/core/constants/env_constants.dart`; debug → `.env.dev`, release → `.env.prod`, selected in `lib/core/config/environment.dart`). Never commit real secrets; `.env.example` documents the shape.
- **dart-defines** carry the **edge integration** base URLs (compile-time `String.fromEnvironment`): `BACKEND_BASE_URL` (FastApiBackend public video-templates endpoints; replaces the retired `VIDEO_BASE_URL`), `CUST_BASE_URL`, plus the theme-browser link targets `LANDING_URL` / `PRICING_URL` / `BOOK_URL`. They default to `localhost` (dev) and are overridden at build time for prod (see *Production deployment*). `DEFAULT_VIDEO_GYM` (default `boxing`, in `AppConstants.defaultVideoGymId`) picks the `video_gym` seeded after login — see *Video template integration*.

## Production deployment (web)

The admin app deploys as a static build to **S3 + CloudFront** at `https://app.combatden.net` (mirrors `../LandingPage/deploy/`). See `../DEPLOYMENT.md` for the full runbook.

`web/` is CombatDen-branded (not the Flutter template): the tab `<title>`, `manifest.json`, and the favicon + PWA icons (generated from `assets/images/combatden_logo.png`) all carry the brand. `web/` is shared by both build targets, so the admin app and the theme browser get the same favicon/title.

- **Build for prod with the edge base URLs** (they override the `localhost` defaults): `make build-web` → `flutter build web --release --base-href=/ --no-tree-shake-icons --dart-define=CUST_BASE_URL=https://theme.combatden.net --dart-define=BACKEND_BASE_URL=https://api.combatden.net`, followed by `python3 deploy/prune_web_fonts.py build/web`.
- **`--no-tree-shake-icons` is required, and the font prune that follows it is not optional.** Icon tree-shaking only runs in release builds and corrupts the variable `weight` axis of `MaterialSymbolsSharp` — so every `Symbols.*_sharp` icon (the whole nav bar) renders in debug but **disappears on deploy** (flutter/flutter#183381). The flag ships the full font with its axes intact, but also ships the package's two **unused** families full (Rounded ~15 MB + Outlined ~10 MB), which Flutter web loads eagerly at startup — so `deploy/prune_web_fonts.py` deletes those two `.ttf`s and strips them from the manifest post-build (~25 MB saved; the app uses only Sharp). Both `make build-web` and `make build-themes` run flag + prune. **Don't remove either without restoring the other** — the flag alone bloats the bundle; the prune alone re-breaks icons.
- **Deploy tooling lives in `deploy/`** (boto3, its own `pyproject.toml`): `make deploy-provision` (S3 + ACM cert), `make deploy-finalize` (CloudFront — includes a 403/404 → `/index.html` SPA fallback so deep links and refresh resolve), then `make deploy` (build + upload + invalidate). DNS records are added by hand at Squarespace.
- Both backends are served over HTTPS at their own subdomains (`theme.` / `video.combatden.net`), so there is no mixed-content issue and the APIs' open CORS (`["*"]`) covers the cross-origin calls. **No Dart code changes are needed for prod** — only the dart-defines at build time.

**Second deployment — the standalone theme browser** ships from the **same project, a different `--target`**, to `https://themes.combatden.net`.

- **Build:** `make build-themes` → `flutter build web --release --base-href=/ --target lib/main_theme_browser.dart` plus the same two API dart-defines as the admin build.
- **Deploy tooling lives in `deploy-themes/`** — a copy of `deploy/` whose `config.py` points at bucket `combatden-themes` / domain `themes.combatden.net`. Config-driven and otherwise identical: `make deploy-themes-provision` / `-finalize` / `deploy-themes`.
- Both targets emit to `build/web`, so the admin and themes deploys are **sequential, never simultaneous** (build admin → `deploy`; build themes → `deploy-themes`).

---

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
