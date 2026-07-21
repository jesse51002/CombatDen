"""Structural guards on the growth-metric registry.

The registry is the single source of display metadata AND of which model each
payload is validated against, so a mismatched pairing (a ``line`` metric
validated as a breakdown, say) would silently drop every one of that metric's
rows at serve time. These tests are hermetic — no DB, no SQL execution.
"""

from src.growth import SQL_DIR
from src.growth.schema.growth_schema import (
    BarsData,
    BreakdownData,
    DonutPairData,
    GrowthMetricType,
    HeatmapData,
    HeroSplitData,
    KpiGroupData,
    LineData,
    MemberListData,
)
from src.growth.service.growth_registry import (
    DORMANT_CTE,
    GROWTH_REGISTRY,
    REGISTRY_BY_KEY,
)

# The one legal model per render type. A new type must be added here in the
# same change that adds it to GrowthMetricType.
MODEL_FOR_TYPE = {
    GrowthMetricType.kpi_group: KpiGroupData,
    GrowthMetricType.hero_split: HeroSplitData,
    GrowthMetricType.line: LineData,
    GrowthMetricType.bars: BarsData,
    GrowthMetricType.breakdown: BreakdownData,
    GrowthMetricType.donut_pair: DonutPairData,
    GrowthMetricType.heatmap: HeatmapData,
    GrowthMetricType.member_list: MemberListData,
}

# Every bind name the compute service can supply.
KNOWN_PARAMS = {"gym_id", "dormancy_days", "at_risk_days"}


def test_every_type_has_a_model_mapping() -> None:
    """The test's own mapping covers every declared render type."""
    assert set(MODEL_FOR_TYPE) == set(GrowthMetricType)


def test_model_matches_type_for_every_entry() -> None:
    """Each entry validates against the model its render type requires."""
    mismatched = [
        definition.key
        for definition in GROWTH_REGISTRY
        if definition.model is not MODEL_FOR_TYPE[definition.type]
    ]
    assert not mismatched, f"model/type mismatch: {mismatched}"


def test_keys_are_unique() -> None:
    """Keys are the UPSERT conflict target — duplicates would overwrite."""
    keys = [definition.key for definition in GROWTH_REGISTRY]
    assert len(keys) == len(set(keys))
    assert len(REGISTRY_BY_KEY) == len(GROWTH_REGISTRY)


def test_orders_are_unique() -> None:
    """Order values are the page's sort key — ties would render nondeterministically."""
    orders = [definition.order for definition in GROWTH_REGISTRY]
    assert len(orders) == len(set(orders))


def test_every_entry_declares_categories() -> None:
    """A metric with no category could never be reached from any tab."""
    orphans = [
        definition.key
        for definition in GROWTH_REGISTRY
        if not definition.categories
    ]
    assert not orphans


def test_params_are_known_and_include_gym_id() -> None:
    """Declared binds must be suppliable, and every metric is gym-scoped."""
    for definition in GROWTH_REGISTRY:
        assert set(definition.params) <= KNOWN_PARAMS, definition.key
        assert "gym_id" in definition.params, definition.key


def test_sql_file_matches_key() -> None:
    """The file name is derived from the key — keeps the two from drifting."""
    for definition in GROWTH_REGISTRY:
        assert definition.sql_file == f"{definition.key}.sql"


def test_existing_sql_files_are_readable_and_non_empty() -> None:
    """A registered .sql that exists must be a real, readable file.

    Files that do not exist yet are legal: the compute service logs and skips
    them while the remaining metrics land.
    """
    for definition in GROWTH_REGISTRY:
        path = SQL_DIR / definition.sql_file
        if not path.exists():
            continue
        assert path.is_file(), definition.sql_file
        assert path.read_text().strip(), definition.sql_file


def test_dormancy_keeps_the_never_attended_guard() -> None:
    """Case (b) anchors on GREATEST(last check-in, newest live pack start).

    A brand-new trial member with no check-ins yet must NOT count as dormant:
    branding day-one leads as lost is the exact failure this guard exists to
    prevent. The rule can only be exercised end-to-end against a database, so
    this hermetic check locks the shape so it cannot be quietly simplified
    back into a bare "no check-in means dormant" test.
    """
    assert "GREATEST(" in DORMANT_CTE
    assert "latest_live_start" in DORMANT_CTE
    # The old, wrong form: dormancy decided by a null check-in alone.
    assert "m.last_class IS NULL" not in DORMANT_CTE


def test_templated_files_declare_their_variables() -> None:
    """A file using a template variable declares it; an untemplated one does not.

    ``load_sql`` runs ``str.format_map``, so calling it with variables on a
    file that has none (or without them on a file that does) is a live bug.
    """
    for definition in GROWTH_REGISTRY:
        path = SQL_DIR / definition.sql_file
        if not path.exists():
            continue
        has_brace = "{" in path.read_text()
        declares = definition.sql_variables is not None
        assert has_brace == declares, definition.sql_file
