"""Orchestrator service for the gyms domain.

Handles:
    * create_gym   — DB-first insert + Stripe Connect Express account
    * list_gyms_for_user / update_gym — basic CRUD
    * get_onboarding_status / get_fresh_onboarding_link — Stripe status
"""

from uuid import UUID

from schema.gym_employee import ThemeMode
from schema.gym_rank import SubRankType
from schema.immutable_columns import GYMS as GYMS_IMMUTABLE
from sqlalchemy import text

from src.classes.service.classes_versions_service import (
    ClassesVersionsService,
)
from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import (
    EmployeeThemeResponse,
    GymAppLinksResponse,
    GymCreateRequest,
    GymCreateResponse,
    GymOnboardingLinkResponse,
    GymOnboardingStatusResponse,
    GymResponse,
    GymThemeResponse,
    GymUpdateData,
    GymWithRoleResponse,
)
from src.gyms.service.gyms_create_service import GymsCreateService
from src.gyms.service.gyms_onboarding_service import GymsOnboardingService
from src.gyms.service.gyms_stripe_connect_service import GymsStripeConnectService
from src.ranks.service.ranks_members import RanksMembers
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.waivers.service.waivers_service import WaiversService


class GymsService:
    """Orchestrates all gym routes.

    A ``GymsStripeConnectService`` is always injected (via
    ``DependencyInjector.gyms_stripe_connect_service``); every gym is
    created with a Stripe Connect Express account.

    Args:
        db_pool: Injected database connection pool.
        stripe_connect_service: Injected Stripe Connect wrapper.
        waivers_service: Injected waivers service; forwarded to
            ``GymsCreateService`` so the default authorized-payer waiver
            is seeded atomically (before the Stripe account) and torn
            down cleanly if creation fails.
        classes_versions_service: Injected schedule-version mint engine —
            the documented ``gyms -> classes`` edge: a gym TIMEZONE change
            re-mints a same-shape schedule version (new tz) for every live
            class, so the class system's frozen-per-version timezones track
            the gym going forward while every existing version (the past)
            stays untouched. The wall-clock exact-slot match keeps every
            future sign-up / check-in — nothing is wiped.
        ranks_members: Injected ranks member-rank concern — the documented
            ``gyms -> ranks`` edge: a gym ``sub_rank_type`` change reconciles
            every member's ``current_sub_index`` so the leaf invariant stays
            valid (→ ``'none'`` clears all sub-indices; → stripes/div fills
            the base leaf where a rank has sub-ranks), never touching the
            persisted per-rank counts / image overrides.
        combatden_app_store_url: CombatDen's default iOS App Store listing —
            the fallback ``get_app_links`` returns when a gym has not set its
            own ``gyms.app_store_url`` (placeholder until the app ships).
        combatden_play_store_url: CombatDen's default Google Play listing —
            the fallback for a gym with no ``gyms.play_store_url``.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: GymsStripeConnectService,
        waivers_service: WaiversService,
        classes_versions_service: ClassesVersionsService,
        ranks_members: RanksMembers,
        combatden_app_store_url: str,
        combatden_play_store_url: str,
    ) -> None:
        self._db_pool = db_pool
        self._classes_versions_service = classes_versions_service
        self._ranks_members = ranks_members
        self._combatden_app_store_url = combatden_app_store_url
        self._combatden_play_store_url = combatden_play_store_url
        self._create_service = GymsCreateService(
            db_pool=db_pool,
            stripe_connect_service=stripe_connect_service,
            waivers_service=waivers_service,
        )
        self._onboarding_service = GymsOnboardingService(
            db_pool=db_pool,
            stripe_connect_service=stripe_connect_service,
        )

    # ── Create ─────────────────────────────────────────────────

    async def create_gym(
        self,
        request: GymCreateRequest,
        user_email: str,
    ) -> GymCreateResponse:
        """Create a gym and begin Stripe Express onboarding.

        Identity is the caller's verified email — the owner
        ``gym_employees`` row is keyed on it. A user may own multiple
        gyms, so this does not pre-check for an existing gym. Delegates
        to ``GymsCreateService`` for the DB-first insert + default-waiver
        seed + Stripe account + AccountLink flow (waiver is seeded before
        Stripe so a failure tears down cleanly with no orphaned Stripe
        account).

        Raises:
            ValueError: If ``user_email`` is empty.
        """
        if not user_email:
            raise ValueError("user_email is required for Stripe onboarding")

        return await self._create_service.create_gym(
            request=request,
            user_email=user_email,
        )

    # ── Onboarding status ──────────────────────────────────────

    async def get_onboarding_status(
        self,
        gym_id: UUID,
    ) -> GymOnboardingStatusResponse:
        """Fetch + refresh a gym's onboarding status.

        The caller's ownership of ``gym_id`` is verified at the
        router layer before this runs.
        """
        return await self._onboarding_service.refresh(gym_id)

    async def get_fresh_onboarding_link(
        self,
        gym_id: UUID,
    ) -> GymOnboardingLinkResponse:
        """Mint a new AccountLink without re-reading the account.

        The caller's ownership of ``gym_id`` is verified at the
        router layer before this runs.
        """
        return await self._onboarding_service.new_link(gym_id)

    # ── Basic CRUD ─────────────────────────────────────────────

    async def list_gyms_for_user(
        self,
        user_email: str,
        caller_id: str,
    ) -> list[GymWithRoleResponse]:
        """Return every gym the caller is an employee of.

        Identity is the caller's verified email (matched lowercase). Each
        gym is annotated with the caller's ``employee_type`` for it — all
        roles enter the CRM. Returns an empty list when the caller is an
        employee of no gyms.

        ``caller_id`` is the JWT ``sub`` — the confirmed-account ``EXISTS``
        pins on it so the query proves the CALLER's own account is confirmed,
        not merely that some confirmed account holds this email.
        """
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "gyms_list_for_user.sql")),
                        {"email": user_email.lower(), "caller_id": caller_id},
                    )
                )
                .mappings()
                .fetchall()
            )

        return [GymWithRoleResponse(**row) for row in rows]

    async def get_app_links(
        self,
        gym_id: UUID,
    ) -> GymAppLinksResponse:
        """Resolve a gym's member-app store links (public read).

        Each link is the gym's own white-label listing when set, else the
        CombatDen default (injected placeholder until the app ships). The
        resolution is a NULL fallback on the COLUMN, not on the gym itself:
        an unknown ``gym_id`` is a 404, never a default-filled response, so
        the public download page can't silently succeed for a bad QR code.

        Raises:
            ValueError: If no gym has ``gym_id`` (mapped to 404 at the router).
        """
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "gyms_get_app_links.sql")),
                        {"gym_id": str(gym_id)},
                    )
                )
                .mappings()
                .fetchone()
            )

        if row is None:
            raise ValueError("Gym not found")

        return GymAppLinksResponse(
            ios_url=row["app_store_url"] or self._combatden_app_store_url,
            android_url=row["play_store_url"] or self._combatden_play_store_url,
        )

    async def update_gym(
        self,
        gym_id: UUID,
        data: GymUpdateData,
    ) -> GymResponse:
        """Update mutable fields on a gym row.

        ``sub_rank_type`` (none / stripes / div) rides the same dynamic
        SET clause as every other mutable field here; it is NOT NULL on
        the gyms row, so ``GymUpdateData`` rejects an explicit ``null``
        for it the same way it does for ``gym_name`` / ``timezone``. A
        save that CHANGES it additionally reconciles every member's
        ``current_sub_index`` to the new style (the ``gyms -> ranks``
        edge) AFTER the gyms row commits — → ``'none'`` clears all
        sub-indices, → stripes/div fills the base leaf on ranks that have
        sub-ranks — never touching the persisted per-rank counts /
        overrides. It runs on EVERY sub_rank_type-carrying save (not
        gated on "did it change"): the reconcile is idempotent, so a
        re-save is a cheap self-heal, exactly like the timezone re-mint.

        A save that carries a TIMEZONE additionally re-mints every live
        class's schedule version with that zone (see the constructor note)
        AFTER the gym row commits. The re-mint runs on EVERY
        timezone-carrying save — deliberately not gated on "did the value
        change": the gyms row commits first and the remint loop is one
        transaction per class, so a partial remint failure leaves the row
        already updated; a changed-value gate would then skip the retry
        forever, stranding the remaining classes on the old zone. Because
        the per-class mint is deep-equal-skipping (timezone included), a
        re-save is cheap — already-reminted classes no-op, the rest catch
        up — which is what makes the retry self-heal.

        Uses ``exclude_unset=True`` only (no ``exclude_none``), matching
        ``RewardsService``/``MembersManagementUpdate``/``RanksService``:
        an explicitly-sent ``null`` for a nullable column (e.g. ``logo_url``)
        is a real instruction to clear that column, distinct from the field
        being absent (unchanged). A NOT NULL column sent as ``null`` still
        fails at the DB constraint.
        """
        update_fields = data.model_dump(exclude_unset=True)

        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(GYMS_IMMUTABLE, set(update_fields.keys()))

        new_timezone = update_fields.get("timezone")
        new_sub_rank_type = update_fields.get("sub_rank_type")

        set_clause = ", ".join(f"{col} = :{col}" for col in update_fields)
        sql = load_sql(
            SQL_DIR / "update_gym.sql",
            {"set_clause": set_clause},
        )

        params = {**update_fields, "gym_id": str(gym_id)}
        row = await self._db_pool.execute_with_retry(sql, params)

        if not row:
            raise ValueError("Gym not found")

        if new_timezone is not None:
            await self._classes_versions_service.remint_timezone(
                gym_id, new_timezone
            )

        if new_sub_rank_type is not None:
            await self._ranks_members.reconcile_sub_index_for_gym(
                gym_id, SubRankType(new_sub_rank_type)
            )

        return GymResponse(**row)

    async def update_gym_theme(
        self,
        gym_id: UUID,
        theme_design_id: str,
    ) -> GymThemeResponse:
        """Save the gym's chosen ThemeService design id.

        The caller's employment at ``gym_id`` is verified at the
        router layer. ``theme_design_id`` is the only field this
        writes; the guard call is defense-in-depth consistency with
        ``update_gym`` even though the field is fixed here.
        """
        validate_mutable_columns(GYMS_IMMUTABLE, {"theme_design_id"})

        sql = load_sql(SQL_DIR / "update_gym_theme.sql")
        params = {
            "theme_design_id": theme_design_id,
            "gym_id": str(gym_id),
        }
        row = await self._db_pool.execute_with_retry(sql, params)

        if not row:
            raise ValueError("Gym not found")

        return GymThemeResponse(**row)

    async def update_employee_theme(
        self,
        gym_id: UUID,
        user_email: str,
        theme_preference: ThemeMode,
    ) -> EmployeeThemeResponse:
        """Save the caller's CRM theme preference for one gym.

        The caller's employment at ``gym_id`` is verified at the router
        layer; the WHERE clause scopes the write to the caller's own
        ``gym_employees`` row, matched by verified email (lowercase).
        """
        sql = load_sql(SQL_DIR / "update_employee_theme.sql")
        params = {
            "theme_preference": theme_preference.value,
            "email": user_email.lower(),
            "gym_id": str(gym_id),
        }
        row = await self._db_pool.execute_with_retry(sql, params)

        if not row:
            raise ValueError("Employee not found for this gym")

        return EmployeeThemeResponse(**row)
