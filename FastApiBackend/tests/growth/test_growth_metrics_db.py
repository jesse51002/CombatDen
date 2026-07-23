"""Real-DB integration tests for the growth REVENUE SQL and the write-path
(upsert / prune) SQL.

The rest of ``tests/growth/`` mocks ``db_pool`` and only proves the ``.sql``
files load and template cleanly. Nothing there executes the revenue queries
against Postgres, so a regression that summed GROSS instead of NET money, or
dropped refund rows, or bucketed charges by UTC instead of the gym-local month,
would ship green. These tests close that gap by running the REAL ``.sql`` files
(loaded through ``load_sql`` with the registry's own binds, exactly as
``GrowthComputeService`` does) against the shared seeded gym.

Because the seeded gym already carries revenue, every revenue assertion is a
BEFORE/AFTER **delta** around a scenario this test seeds and tears down — the
delta is determined entirely by the rows seeded here, never by seed luck. Each
seeded charge/invoice/membership is cleaned up by the ``created`` fixture
(``delete_member_data`` + ``delete_plan_data``); the metric-cache rows the
upsert/prune tests write are removed by a precise ``try/finally``. No Stripe
object is created — every row is a direct insert of the shape the webhook mirror
/ payment sync would have written.

What each test proves:

* ``test_collected_revenue_is_net_of_refunds`` — collected revenue is the NET
  sum of charges: a +payment and a -refund net out (gross-vs-net regression),
  and the refund REDUCES collected (dropped-refund regression). Covers
  ``revenue_hero`` and ``revenue_kpis``.
* ``test_mrr_uses_net_total_price`` — the MRR tile sums
  ``member_memberships.total_price`` (already NET / post-discount), never the
  plan's gross list price. Covers the "sums GROSS instead of NET total_price"
  regression on ``revenue_kpis``.
* ``test_revenue_buckets_by_gym_local_month`` — the monthly series buckets a
  charge by the gym's LOCAL month (``AT TIME ZONE``), not UTC. Covers
  ``mrr_trend``.
* ``test_all_revenue_metrics_execute_and_validate`` — all six revenue ``.sql``
  files run against the real DB and return a payload that validates against
  their registry model (a read-only smoke that a SQL/shape break can't pass).
* ``test_upsert_metric_overwrites_in_place`` /
  ``test_prune_deletes_retired_keeps_registry`` — the two write-path SQL files
  executed against Postgres, not just bind-checked.
"""

import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from dateutil.relativedelta import relativedelta
from sqlalchemy import text

from src.growth import SQL_DIR as GROWTH_SQL_DIR
from src.growth.service.growth_registry import (
    GROWTH_REGISTRY,
    REGISTRY_BY_KEY,
    GrowthMetricDef,
)
from src.shared.sql_loader import load_sql
from tests.seed_constants import SEEDED_GYM_ID

GYM = UUID(SEEDED_GYM_ID)

# The full bind set the compute service can supply; a metric takes the subset it
# declares in ``definition.params`` (mirrors GrowthComputeService._build_params).
DORMANCY_DAYS = 30
AT_RISK_DAYS = 14

# The six revenue metrics the review flagged as never executed against a real DB.
REVENUE_KEYS = (
    "revenue_hero",
    "revenue_kpis",
    "mrr_trend",
    "revenue_collected",
    "revenue_by_plan",
    "revenue_quality_kpis",
)


# ── Running a metric the way production does ─────────────────────────


async def _run_metric(db_pool, definition: GrowthMetricDef) -> dict:
    """Load + bind + execute one metric's ``.sql`` exactly as the compute
    service does, and return its single ``data`` payload.

    Uses ``load_sql`` with the definition's own ``sql_variables`` and binds only
    the params it declares — the same machinery ``GrowthComputeService`` runs, so
    the test can never diverge from production's query text or binds.
    """
    path = GROWTH_SQL_DIR / definition.sql_file
    sql = (
        load_sql(path, definition.sql_variables)
        if definition.sql_variables is not None
        else load_sql(path)
    )
    available = {
        "gym_id": str(GYM),
        "dormancy_days": DORMANCY_DAYS,
        "at_risk_days": AT_RISK_DAYS,
    }
    binds = {name: available[name] for name in definition.params}
    async with db_pool.session() as session:
        rows = (await session.execute(text(sql), binds)).mappings().all()
    assert rows, f"metric {definition.key} returned no row"
    return rows[0]["data"]


def _segment(hero: dict, key: str) -> float:
    """The ``value`` of one ``hero_split`` segment by key."""
    return next(s["value"] for s in hero["segments"] if s["key"] == key)


def _tile(group: dict, key: str) -> float:
    """The ``value`` of one ``kpi_group`` tile by key."""
    return next(t["value"] for t in group["tiles"] if t["key"] == key)


def _series_points(chart: dict, series_key: str) -> dict[str, float]:
    """A ``line`` / ``bars`` series flattened to ``{date: value}``."""
    series = next(s for s in chart["series"] if s["key"] == series_key)
    return {p["date"]: p["value"] for p in series["points"]}


# ── Direct row inserts (the shape the webhook mirror / sync would write) ──


async def _insert_member(session) -> UUID:
    """A bare engagement-only member row (no Stripe customer needed for the
    charge / invoice / membership FKs these tests use)."""
    row = (
        await session.execute(
            text(
                "INSERT INTO members (gym_id, first_name, last_name) "
                "VALUES (:g, 'Growth', 'RevenueTest') RETURNING member_id"
            ),
            {"g": str(GYM)},
        )
    ).mappings().one()
    return UUID(str(row["member_id"]))


async def _insert_invoice(
    session, member_id: UUID, total_amount: int
) -> UUID:
    """A paid invoice billed to ``member_id`` (the payer)."""
    row = (
        await session.execute(
            text(
                "INSERT INTO member_invoices "
                "(gym_id, paid_by_member_id, status, total_amount) "
                "VALUES (:g, :m, 'paid', :amt) RETURNING invoice_id"
            ),
            {"g": str(GYM), "m": str(member_id), "amt": total_amount},
        )
    ).mappings().one()
    return UUID(str(row["invoice_id"]))


async def _insert_payment(
    session,
    invoice_id: UUID,
    member_id: UUID,
    amount: int,
    charge_time: datetime,
) -> UUID:
    """A succeeded card payment (amount >= 0), carrying a unique stripe id so
    the cash-dedup partial index never applies."""
    row = (
        await session.execute(
            text(
                "INSERT INTO member_charges "
                "(invoice_id, gym_id, paid_by_member_id, kind, status, amount, "
                " payment_method_type, stripe_charge_id, charge_time) "
                "VALUES (:inv, :g, :m, 'payment', 'succeeded', :amt, 'card', "
                " :sid, :ct) RETURNING charge_id"
            ),
            {
                "inv": str(invoice_id),
                "g": str(GYM),
                "m": str(member_id),
                "amt": amount,
                "sid": f"ch_test_{uuid4().hex}",
                "ct": charge_time,
            },
        )
    ).mappings().one()
    return UUID(str(row["charge_id"]))


async def _insert_refund(
    session,
    invoice_id: UUID,
    member_id: UUID,
    amount: int,
    charge_time: datetime,
    parent_charge_id: UUID,
) -> None:
    """A succeeded refund (amount <= 0) against ``parent_charge_id`` — stored
    NEGATIVE, so a plain SUM over charges is already net of it."""
    await session.execute(
        text(
            "INSERT INTO member_charges "
            "(invoice_id, gym_id, paid_by_member_id, kind, status, amount, "
            " payment_method_type, stripe_refund_id, refunds_charge_id, "
            " charge_time) "
            "VALUES (:inv, :g, :m, 'refund', 'succeeded', :amt, 'card', "
            " :rid, :parent, :ct)"
        ),
        {
            "inv": str(invoice_id),
            "g": str(GYM),
            "m": str(member_id),
            "amt": amount,
            "rid": f"re_test_{uuid4().hex}",
            "parent": str(parent_charge_id),
            "ct": charge_time,
        },
    )


async def _insert_recurring_plan(
    session, list_price: int
) -> tuple[UUID, UUID]:
    """A visible recurring plan + active price (``stripe_product_id`` set so the
    filtered ``membership_plans`` view surfaces it). Returns (plan_id, price_id).
    """
    plan = (
        await session.execute(
            text(
                "INSERT INTO membership_plans_unfiltered "
                "(gym_id, plan_name, image_url, plan_type, duration_amount, "
                " duration_unit, is_public, stripe_product_id) "
                "VALUES (:g, 'Growth Test Recurring', :img, 'recurring', 1, "
                " 'month', true, :prod) RETURNING plan_id"
            ),
            {
                "g": str(GYM),
                "img": "https://cdn.combatden.net/membership/presets/activity-01.jpg",
                "prod": f"prod_test_{uuid4().hex}",
            },
        )
    ).mappings().one()
    plan_id = UUID(str(plan["plan_id"]))
    price = (
        await session.execute(
            text(
                "INSERT INTO membership_plan_prices_unfiltered "
                "(plan_id, gym_id, stripe_price_id, price, is_active) "
                "VALUES (:p, :g, :sp, :price, true) RETURNING price_id"
            ),
            {
                "p": str(plan_id),
                "g": str(GYM),
                "sp": f"price_test_{uuid4().hex}",
                "price": list_price,
            },
        )
    ).mappings().one()
    return plan_id, UUID(str(price["price_id"]))


async def _insert_membership(
    session,
    member_id: UUID,
    plan_id: UUID,
    price_id: UUID,
    total_price: int,
    start_date: date,
) -> UUID:
    """An active, synced recurring membership (``stripe_item_id`` set + status
    ``applied`` so it surfaces in the filtered ``member_memberships`` view and
    thus in ``member_memberships_status``)."""
    row = (
        await session.execute(
            text(
                "INSERT INTO member_memberships_unfiltered "
                "(member_id, gym_id, plan_id, price_id, paid_by_member_id, "
                " start_date, total_price, stripe_item_id, stripe_sync_status) "
                "VALUES (:m, :g, :p, :pr, :m, :sd, :tp, :si, 'applied') "
                "RETURNING item_id"
            ),
            {
                "m": str(member_id),
                "g": str(GYM),
                "p": str(plan_id),
                "pr": str(price_id),
                "sd": start_date,
                "tp": total_price,
                "si": f"si_test_{uuid4().hex}",
            },
        )
    ).mappings().one()
    return UUID(str(row["item_id"]))


async def _delete_metric_row(db_pool, key: str) -> None:
    """Delete exactly the (seeded gym, key) growth-cache row a test wrote."""
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM gym_growth_metrics "
                "WHERE gym_id = :g AND key = :k"
            ),
            {"g": str(GYM), "k": key},
        )
        await session.commit()


# ── Revenue: net-of-refunds, net total_price, gym-local buckets ──────


async def test_collected_revenue_is_net_of_refunds(db_pool, created) -> None:
    """Collected revenue is the NET sum of charges, refunds included.

    Seeds one invoice with a +12000 payment and a -3000 refund, both dated now
    (current gym-local month / trailing 30 days). Net contribution is 9000.

    * ``revenue_hero`` collected segment rises by exactly 9000 — proving it sums
      net charge amounts (a gross reading would be 12000; dropping the refund
      would also be 12000).
    * ``revenue_kpis`` collected_30d rises by 9000 (net) and refunds_30d rises by
      3000 (the refund magnitude, reported positive) — locking that the refund
      both reduces collected AND is surfaced.
    """
    hero_def = REGISTRY_BY_KEY["revenue_hero"]
    kpis_def = REGISTRY_BY_KEY["revenue_kpis"]
    before_hero = await _run_metric(db_pool, hero_def)
    before_kpis = await _run_metric(db_pool, kpis_def)

    now = datetime.now(UTC)
    async with db_pool.session() as session:
        member_id = await _insert_member(session)
        invoice_id = await _insert_invoice(session, member_id, 12000)
        payment_id = await _insert_payment(
            session, invoice_id, member_id, 12000, now
        )
        await _insert_refund(
            session, invoice_id, member_id, -3000, now, payment_id
        )
        await session.commit()
    created.track_member(member_id)

    after_hero = await _run_metric(db_pool, hero_def)
    after_kpis = await _run_metric(db_pool, kpis_def)

    assert (
        _segment(after_hero, "collected") - _segment(before_hero, "collected")
        == 9000
    )
    assert (
        _tile(after_kpis, "collected_30d")
        - _tile(before_kpis, "collected_30d")
        == 9000
    )
    assert (
        _tile(after_kpis, "refunds_30d") - _tile(before_kpis, "refunds_30d")
        == 3000
    )


async def test_mrr_uses_net_total_price(db_pool, created) -> None:
    """The MRR tile sums the NET per-membership price, not the gross list price.

    Seeds a recurring plan whose list price is 5000 and one active membership on
    it whose stamped ``total_price`` (post-discount, NET) is 4200. The MRR tile
    must rise by 4200 — a regression that summed the plan's list price would
    rise by 5000.
    """
    kpis_def = REGISTRY_BY_KEY["revenue_kpis"]
    before = await _run_metric(db_pool, kpis_def)

    start = date.today() - timedelta(days=5)
    async with db_pool.session() as session:
        member_id = await _insert_member(session)
        plan_id, price_id = await _insert_recurring_plan(
            session, list_price=5000
        )
        await _insert_membership(
            session, member_id, plan_id, price_id, total_price=4200,
            start_date=start,
        )
        await session.commit()
    created.track_member(member_id)
    created.track_plan_db(plan_id)

    after = await _run_metric(db_pool, kpis_def)

    assert _tile(after, "mrr") - _tile(before, "mrr") == 4200


async def test_revenue_buckets_by_gym_local_month(db_pool, created) -> None:
    """A charge is bucketed by the gym's LOCAL month, not by UTC.

    Reads the gym's timezone and builds a charge instant one hour before the
    local month start — the PREVIOUS local month, but (for a UTC-behind tz like
    the seeded gym's America/Chicago) still the CURRENT UTC month. The charge
    rides an empty invoice, so ``mrr_trend`` attributes it fully to recurring
    and drops it into exactly one month bucket:

    * the GYM-LOCAL month bucket rises by the charge amount, and
    * the UTC month bucket does NOT move.

    A metric that bucketed by UTC would flip these two.
    """
    async with db_pool.session() as session:
        tz_name = (
            await session.execute(
                text("SELECT timezone FROM gyms WHERE gym_id = :g"),
                {"g": str(GYM)},
            )
        ).scalar_one()

    tz = ZoneInfo(tz_name)
    now_local = datetime.now(tz)
    local_month_start = now_local.replace(
        day=1, hour=0, minute=0, second=0, microsecond=0
    )
    instant = local_month_start - timedelta(hours=1)  # previous local month
    instant_utc = instant.astimezone(UTC)
    local_bucket = (local_month_start - relativedelta(months=1)).strftime(
        "%Y-%m-%d"
    )
    utc_bucket = instant_utc.replace(day=1).strftime("%Y-%m-%d")
    # Only meaningful if the two months genuinely differ at this instant (true
    # for a UTC-behind tz). Fail loudly rather than pass vacuously if the seeded
    # gym's tz ever changes to one where this boundary does not cross.
    assert local_bucket != utc_bucket, (
        f"tz {tz_name}: instant {instant_utc} has the same local and UTC "
        "month — choose a boundary instant that crosses the month line"
    )

    trend_def = REGISTRY_BY_KEY["mrr_trend"]
    before = _series_points(await _run_metric(db_pool, trend_def), "mrr")

    amount = 4237
    async with db_pool.session() as session:
        member_id = await _insert_member(session)
        invoice_id = await _insert_invoice(session, member_id, amount)
        await _insert_payment(
            session, invoice_id, member_id, amount, instant_utc
        )
        await session.commit()
    created.track_member(member_id)

    after = _series_points(await _run_metric(db_pool, trend_def), "mrr")

    assert after.get(local_bucket, 0) - before.get(local_bucket, 0) == amount
    assert after.get(utc_bucket, 0) - before.get(utc_bucket, 0) == 0


async def test_all_revenue_metrics_execute_and_validate(db_pool) -> None:
    """Every revenue ``.sql`` runs against the real DB and validates.

    Read-only smoke over all six revenue metrics: each query executes against
    the seeded gym and its returned payload validates against the registry model
    the compute + serve paths use. A SQL error or a payload-shape regression
    fails here loudly, where the mocked-``db_pool`` unit tests can't see it.
    """
    for key in REVENUE_KEYS:
        definition = REGISTRY_BY_KEY[key]
        data = await _run_metric(db_pool, definition)
        definition.model.model_validate(data)


# ── Write path: upsert idempotency + prune-retired ───────────────────


async def test_upsert_metric_overwrites_in_place(db_pool) -> None:
    """``upsert_metric.sql`` run twice for one (gym, key) leaves ONE row holding
    the SECOND payload — the idempotent overwrite the sweep relies on."""
    key = "__test_upsert_idem__"
    sql = load_sql(GROWTH_SQL_DIR / "upsert_metric.sql")
    try:
        await db_pool.execute_with_retry(
            sql,
            {
                "gym_id": str(GYM),
                "key": key,
                "type": "breakdown",
                "data": json.dumps({"v": 1}),
            },
        )
        await db_pool.execute_with_retry(
            sql,
            {
                "gym_id": str(GYM),
                "key": key,
                "type": "kpi_group",
                "data": json.dumps({"v": 2}),
            },
        )

        async with db_pool.session() as session:
            rows = (
                await session.execute(
                    text(
                        "SELECT type, data FROM gym_growth_metrics "
                        "WHERE gym_id = :g AND key = :k"
                    ),
                    {"g": str(GYM), "k": key},
                )
            ).mappings().all()

        assert len(rows) == 1
        assert rows[0]["data"] == {"v": 2}
        assert rows[0]["type"] == "kpi_group"
    finally:
        await _delete_metric_row(db_pool, key)


async def test_prune_deletes_retired_keeps_registry(db_pool) -> None:
    """``prune_retired_metrics.sql`` with the live registry key list deletes a
    row whose key is no longer registered and keeps a registry-key row.

    The survivor uses a real registry key inserted ``ON CONFLICT DO NOTHING``: if
    a prior sweep already wrote that gym/key row it is reused (and never deleted
    on teardown), so the test never touches shared seed-written data.
    """
    bogus = "__test_prune_bogus__"
    survivor = GROWTH_REGISTRY[0].key  # a real, still-registered key
    upsert = load_sql(GROWTH_SQL_DIR / "upsert_metric.sql")
    prune = load_sql(GROWTH_SQL_DIR / "prune_retired_metrics.sql")
    survivor_created = False
    try:
        await db_pool.execute_with_retry(
            upsert,
            {
                "gym_id": str(GYM),
                "key": bogus,
                "type": "breakdown",
                "data": json.dumps({"v": 1}),
            },
        )
        async with db_pool.session() as session:
            inserted = (
                await session.execute(
                    text(
                        "INSERT INTO gym_growth_metrics "
                        "(gym_id, key, type, data) "
                        "VALUES (:g, :k, :t, CAST(:d AS JSONB)) "
                        "ON CONFLICT (gym_id, key) DO NOTHING "
                        "RETURNING metric_id"
                    ),
                    {
                        "g": str(GYM),
                        "k": survivor,
                        "t": "hero_split",
                        "d": json.dumps({"v": 1}),
                    },
                )
            ).mappings().all()
            await session.commit()
        survivor_created = bool(inserted)

        # Prune with the ACTUAL registry key list, exactly as the compute
        # service does — the list includes ``survivor`` and excludes ``bogus``.
        await db_pool.execute_with_retry(
            prune,
            {
                "gym_id": str(GYM),
                "keys": [definition.key for definition in GROWTH_REGISTRY],
            },
        )

        async with db_pool.session() as session:
            remaining = {
                r["key"]
                for r in (
                    await session.execute(
                        text(
                            "SELECT key FROM gym_growth_metrics "
                            "WHERE gym_id = :g AND key IN (:bogus, :survivor)"
                        ),
                        {
                            "g": str(GYM),
                            "bogus": bogus,
                            "survivor": survivor,
                        },
                    )
                ).mappings().all()
            }

        assert bogus not in remaining
        assert survivor in remaining
    finally:
        await _delete_metric_row(db_pool, bogus)
        if survivor_created:
            await _delete_metric_row(db_pool, survivor)
