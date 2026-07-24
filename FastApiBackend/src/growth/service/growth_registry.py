"""The frozen growth-metric registry — the single source of display metadata.

Nothing about a metric's presentation is stored in ``gym_growth_metrics``: the
name, the categories it appears under, its render type and its sort order all
live here and are attached at serve time. A rename or a reorder is therefore a
code change with no recompute and no migration.

Each entry also names the ``.sql`` file that computes it, the ``*Data`` model
its payload is validated against, and the bind parameters that file uses.

Two entry knobs are deliberately narrow:

* ``params`` — the binds the file actually references. SQLAlchemy's ``text()``
  raises on a param it cannot find in the statement, so the compute service
  builds the param dict from exactly this tuple instead of always passing all
  three.
* ``sql_variables`` — structural ``load_sql`` template variables. ``None``
  means ``load_sql`` is called with NO variables dict at all, because
  ``load_sql`` runs ``str.format_map`` and a file containing a literal brace
  would explode. Only a file that genuinely templates something declares it.

A registered metric whose ``.sql`` file does not exist yet is logged and
skipped by the compute service — the registry lists the full target set while
the SQL lands incrementally.
"""

from dataclasses import dataclass

from pydantic import BaseModel

from src.growth import SQL_DIR
from src.growth.schema.growth_schema import (
    BarsData,
    BreakdownData,
    GrowthCategory,
    GrowthMetricType,
    HeatmapData,
    HeroSplitData,
    KpiGroupData,
    LineData,
    MemberListData,
)
from src.shared.membership_status import load_membership_overdue_sql
from src.shared.sql_loader import load_sql

# The canonical DORMANT / lost-member derivation, written once and injected
# into every consumer as a structural template variable. Loaded at import so
# the file read happens exactly once per process.
DORMANT_CTE = load_sql(SQL_DIR / "_dormant_members.sql")

# The template-variable dict every dormancy-aware metric declares. Consumers
# reference it as ``{dormant_cte}`` and must therefore escape any literal
# brace — in practice they simply contain none.
DORMANT_SQL_VARIABLES: dict[str, str] = {"dormant_cte": DORMANT_CTE}

# The canonical OVERDUE predicate (src/shared/membership_status.py) — the SAME
# one text the members list, its tally, its status filter and the check-in gate
# use, so the money tiles can no longer drift from what the Overdue tab lists.
# Rendered once per date-CTE alias, because the metric files name their
# gym-local "today" differently; every one of them aliases the membership row
# as ``mms``. Consumers reference it as ``{is_overdue}``.
OVERDUE_VS_BOUNDS: dict[str, str] = {
    "is_overdue": load_membership_overdue_sql("mms", "b.today"),
}
OVERDUE_VS_GYM_DAY: dict[str, str] = {
    "is_overdue": load_membership_overdue_sql("mms", "gd.today"),
}
DORMANT_AND_OVERDUE_VS_GYM_DAY: dict[str, str] = {
    **DORMANT_SQL_VARIABLES,
    **OVERDUE_VS_GYM_DAY,
}

# The bind sets a metric file may declare, named once so the entries below
# stay readable.
GYM_ONLY: tuple[str, ...] = ("gym_id",)
GYM_AND_DORMANCY: tuple[str, ...] = ("gym_id", "dormancy_days")
GYM_AND_AT_RISK: tuple[str, ...] = ("gym_id", "at_risk_days")
GYM_DORMANCY_AND_AT_RISK: tuple[str, ...] = (
    "gym_id",
    "dormancy_days",
    "at_risk_days",
)


@dataclass(frozen=True)
class GrowthMetricDef:
    """One registered metric: how to compute it and how to present it."""

    key: str
    name: str
    type: GrowthMetricType
    categories: tuple[GrowthCategory, ...]
    order: int
    sql_file: str
    model: type[BaseModel]
    params: tuple[str, ...] = GYM_ONLY
    sql_variables: dict[str, str] | None = None


GROWTH_REGISTRY: tuple[GrowthMetricDef, ...] = (
    # ── Overview ────────────────────────────────────────────────
    GrowthMetricDef(
        key="revenue_hero",
        name="Monthly Revenue",
        type=GrowthMetricType.hero_split,
        categories=(GrowthCategory.overview,),
        order=10,
        sql_file="revenue_hero.sql",
        model=HeroSplitData,
        sql_variables=OVERDUE_VS_BOUNDS,
    ),
    GrowthMetricDef(
        key="members_kpis",
        name="Members",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.overview, GrowthCategory.members),
        order=20,
        sql_file="members_kpis.sql",
        model=KpiGroupData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    GrowthMetricDef(
        key="members_trend",
        name="Members Over Time",
        type=GrowthMetricType.line,
        categories=(GrowthCategory.overview, GrowthCategory.members),
        order=30,
        sql_file="members_trend.sql",
        model=LineData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    # ── Members ─────────────────────────────────────────────────
    GrowthMetricDef(
        key="members_gained_lost",
        name="Gained vs Lost",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.members,),
        order=110,
        sql_file="members_gained_lost.sql",
        model=BarsData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    GrowthMetricDef(
        key="members_by_plan",
        name="Members by Plan",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.members,),
        order=120,
        sql_file="members_by_plan.sql",
        model=BreakdownData,
    ),
    GrowthMetricDef(
        key="membership_status_mix",
        name="Status Mix",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.members,),
        order=130,
        sql_file="membership_status_mix.sql",
        model=BreakdownData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_AND_OVERDUE_VS_GYM_DAY,
    ),
    GrowthMetricDef(
        key="member_tenure",
        name="Member Tenure",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.members,),
        order=140,
        sql_file="member_tenure.sql",
        model=BreakdownData,
    ),
    # ── Revenue ─────────────────────────────────────────────────
    GrowthMetricDef(
        key="revenue_kpis",
        name="Revenue",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.revenue,),
        order=200,
        sql_file="revenue_kpis.sql",
        model=KpiGroupData,
    ),
    GrowthMetricDef(
        key="revenue_trend",
        # "Billed" is load-bearing, not decoration: this series is money that
        # ACTUALLY changed hands per month, while the forward-run-rate
        # Recurring Revenue KPI tile is what the gym bills per month going
        # forward. The two legitimately differ, and the label is what stops
        # that reading as a bug. It is now ALL revenue (recurring + one-time +
        # trial + cash), not just recurring. The newest point is always
        # month-to-date and therefore low by construction.
        name="Revenue Billed",
        type=GrowthMetricType.line,
        categories=(GrowthCategory.overview, GrowthCategory.revenue),
        order=210,
        sql_file="revenue_trend.sql",
        model=LineData,
    ),
    GrowthMetricDef(
        key="revenue_collected",
        name="Recurring vs One-time",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.revenue,),
        order=220,
        sql_file="revenue_collected.sql",
        model=BarsData,
    ),
    GrowthMetricDef(
        key="revenue_by_plan",
        name="Revenue by Plan",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.revenue,),
        order=230,
        sql_file="revenue_by_plan.sql",
        model=BreakdownData,
    ),
    GrowthMetricDef(
        key="revenue_quality_kpis",
        name="Revenue Quality",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.revenue,),
        order=240,
        sql_file="revenue_quality_kpis.sql",
        model=KpiGroupData,
        sql_variables=OVERDUE_VS_GYM_DAY,
    ),
    # ── Attendance ──────────────────────────────────────────────
    GrowthMetricDef(
        key="attendance_kpis",
        name="Attendance",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.attendance,),
        order=300,
        sql_file="attendance_kpis.sql",
        model=KpiGroupData,
    ),
    GrowthMetricDef(
        key="checkins_trend",
        name="Check-ins",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.attendance,),
        order=310,
        sql_file="checkins_trend.sql",
        model=BarsData,
    ),
    GrowthMetricDef(
        key="attendance_heatmap",
        name="Busy Times",
        type=GrowthMetricType.heatmap,
        categories=(GrowthCategory.attendance,),
        order=320,
        sql_file="attendance_heatmap.sql",
        model=HeatmapData,
    ),
    GrowthMetricDef(
        key="attendance_by_class",
        name="By Class",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.attendance,),
        order=330,
        sql_file="attendance_by_class.sql",
        model=BreakdownData,
    ),
    GrowthMetricDef(
        key="class_fill_rate",
        name="Class Fill Rate",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.attendance,),
        order=340,
        sql_file="class_fill_rate.sql",
        model=BreakdownData,
    ),
    GrowthMetricDef(
        key="signups_vs_checkins",
        name="Sign-ups vs Check-ins",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.attendance,),
        order=350,
        sql_file="signups_vs_checkins.sql",
        model=BarsData,
    ),
    # ── Trial ───────────────────────────────────────────────────
    GrowthMetricDef(
        key="trial_kpis",
        name="Trials",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.trial,),
        order=400,
        sql_file="trial_kpis.sql",
        model=KpiGroupData,
    ),
    GrowthMetricDef(
        key="trials_started_vs_converted",
        name="Started vs Converted",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.trial,),
        order=410,
        sql_file="trials_started_vs_converted.sql",
        model=BarsData,
    ),
    GrowthMetricDef(
        key="trial_conversion_trend",
        name="Conversion Rate",
        type=GrowthMetricType.line,
        categories=(GrowthCategory.trial,),
        order=420,
        sql_file="trial_conversion_trend.sql",
        model=LineData,
    ),
    GrowthMetricDef(
        key="trial_outcomes",
        name="Trial Outcomes",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.trial,),
        order=430,
        sql_file="trial_outcomes.sql",
        model=BreakdownData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    GrowthMetricDef(
        key="trial_engagement",
        name="Trial Engagement",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.trial,),
        order=440,
        sql_file="trial_engagement.sql",
        model=BreakdownData,
    ),
    GrowthMetricDef(
        key="active_trials",
        name="Active Trials",
        type=GrowthMetricType.member_list,
        categories=(GrowthCategory.trial,),
        order=450,
        sql_file="active_trials.sql",
        model=MemberListData,
    ),
    # ── Retention ───────────────────────────────────────────────
    GrowthMetricDef(
        key="retention_kpis",
        name="Retention",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.retention,),
        order=500,
        sql_file="retention_kpis.sql",
        model=KpiGroupData,
        params=GYM_DORMANCY_AND_AT_RISK,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    GrowthMetricDef(
        key="churn_trend",
        name="Churn Rate",
        type=GrowthMetricType.line,
        # Retention-only: churn % is the analyst's lens. Overview leads with
        # Average Membership Length instead — owners read "members stay N
        # months" more readily than a churn percentage.
        categories=(GrowthCategory.retention,),
        order=510,
        sql_file="churn_trend.sql",
        model=LineData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    GrowthMetricDef(
        key="avg_membership_length",
        name="Average Membership Length",
        type=GrowthMetricType.line,
        # Overview's retention read (replaces the churn graph — more
        # intuitive for owners) as well as the Retention tab.
        categories=(GrowthCategory.overview, GrowthCategory.retention),
        order=515,
        sql_file="avg_membership_length.sql",
        model=LineData,
    ),
    GrowthMetricDef(
        key="cohort_retention",
        name="Cohort Retention",
        type=GrowthMetricType.heatmap,
        categories=(GrowthCategory.retention,),
        order=520,
        sql_file="cohort_retention.sql",
        model=HeatmapData,
        params=GYM_AND_DORMANCY,
        sql_variables=DORMANT_SQL_VARIABLES,
    ),
    GrowthMetricDef(
        key="at_risk_members",
        name="At-Risk Members",
        type=GrowthMetricType.member_list,
        categories=(GrowthCategory.retention,),
        order=530,
        sql_file="at_risk_members.sql",
        model=MemberListData,
        params=GYM_AND_AT_RISK,
    ),
    GrowthMetricDef(
        key="engagement_kpis",
        name="Engagement",
        type=GrowthMetricType.kpi_group,
        categories=(GrowthCategory.retention,),
        order=540,
        sql_file="engagement_kpis.sql",
        model=KpiGroupData,
    ),
    GrowthMetricDef(
        key="rank_distribution",
        name="Rank Distribution",
        type=GrowthMetricType.breakdown,
        categories=(GrowthCategory.retention,),
        order=550,
        sql_file="rank_distribution.sql",
        model=BreakdownData,
    ),
    GrowthMetricDef(
        key="promotions_trend",
        name="Promotions",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.retention,),
        order=560,
        sql_file="promotions_trend.sql",
        model=BarsData,
    ),
    GrowthMetricDef(
        key="redemptions_trend",
        name="Reward Redemptions",
        type=GrowthMetricType.bars,
        categories=(GrowthCategory.retention,),
        order=570,
        sql_file="redemptions_trend.sql",
        model=BarsData,
    ),
    GrowthMetricDef(
        key="video_engagement",
        name="Video Engagement",
        type=GrowthMetricType.line,
        categories=(GrowthCategory.retention,),
        order=580,
        sql_file="video_engagement.sql",
        model=LineData,
    ),
)


REGISTRY_BY_KEY: dict[str, GrowthMetricDef] = {
    definition.key: definition for definition in GROWTH_REGISTRY
}
