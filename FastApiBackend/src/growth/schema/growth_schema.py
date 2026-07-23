"""Pydantic models for the growth (per-gym analytics) domain.

Every metric type owns ONE ``*Data`` model describing the shape of its
``gym_growth_metrics.data`` jsonb payload. Those models are the validation
contract in both directions: the compute path validates a freshly computed
payload before writing it, and the serve path validates the stored payload
before handing it to the CRM. A payload that no longer matches its model is
skipped at serve time and self-heals on the next compute.

Field names are plain snake_case with NO alias generator — the CRM converts on
its side (``FieldRename.snake``), so the wire shape is exactly what is declared
here.
"""

from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel


class GrowthMetricType(StrEnum):
    """The renderer a metric's payload is drawn with."""

    kpi_group = "kpi_group"
    hero_split = "hero_split"
    line = "line"
    bars = "bars"
    breakdown = "breakdown"
    donut_pair = "donut_pair"
    heatmap = "heatmap"
    member_list = "member_list"


class GrowthCategory(StrEnum):
    """The Growth-page tab(s) a metric appears under."""

    overview = "overview"
    members = "members"
    revenue = "revenue"
    attendance = "attendance"
    trial = "trial"
    retention = "retention"


class MetricUnit(StrEnum):
    """How a metric's numeric values should be formatted."""

    count = "count"
    cents = "cents"
    percent = "percent"


class Granularity(StrEnum):
    """The time bucket a ``line`` / ``bars`` series steps by."""

    month = "month"
    week = "week"


class KpiTile(BaseModel):
    """One headline number inside a ``kpi_group``."""

    key: str
    label: str
    value: float
    unit: MetricUnit
    delta_pct: float | None = None
    delta_abs: float | None = None
    compare_label: str | None = None


class KpiGroupData(BaseModel):
    """Payload for ``kpi_group`` — a row of headline tiles."""

    tiles: list[KpiTile]


class HeroSegment(BaseModel):
    """One slice of a ``hero_split`` total."""

    key: str
    label: str
    value: float
    tone: str | None = None


class HeroSplitData(BaseModel):
    """Payload for ``hero_split`` — one big total broken into segments."""

    total: float
    unit: MetricUnit
    caption: str | None = None
    segments: list[HeroSegment]


class MemberListColumnType(StrEnum):
    """How one tabular column's cells should be rendered.

    Shared by ``member_list`` and by the optional companion ``table`` a
    ``line`` / ``bars`` metric may carry.
    """

    text = "text"
    number = "number"
    cents = "cents"
    date = "date"


class TableOrientation(StrEnum):
    """Where a metric's companion table sits relative to its chart."""

    stacked = "stacked"
    beside = "beside"


class ColumnAlign(StrEnum):
    """Horizontal text-alignment of a tabular column's cells.

    The complete CSS ``text-align`` set (forward-compatible); the growth SQL
    currently emits only ``right``.
    """

    left = "left"
    right = "right"
    center = "center"


class MetricTableColumn(BaseModel):
    """One column header of a metric's companion ``table``.

    ``tone`` is an optional semantic color hint for the column's values
    (``'good'`` / ``'bad'`` / ``'warn'`` / ``'neutral'`` — the same vocabulary
    a ``hero_split`` segment's ``tone`` uses); ``None`` leaves the default.
    """

    key: str
    label: str
    type: MemberListColumnType
    align: ColumnAlign | None = None
    tone: str | None = None


class MetricTableRow(BaseModel):
    """One companion-table row; ``cells`` is positional against ``columns``."""

    cells: list[str | float | None]


class MetricTable(BaseModel):
    """A data table rendered alongside a chart (under it, or beside it)."""

    orientation: TableOrientation
    columns: list[MetricTableColumn]
    rows: list[MetricTableRow]


class SeriesPoint(BaseModel):
    """One (date, value) sample.

    ``date`` is an ISO date STRING, not a ``date`` object: the payload round-
    trips through jsonb, which has no date type.
    """

    date: str
    value: float


class MetricSeries(BaseModel):
    """A named run of points inside a ``line`` / ``bars`` payload."""

    key: str
    label: str
    points: list[SeriesPoint]


class ClassSeries(BaseModel):
    """The same series set, restricted to a single class."""

    class_id: str
    class_name: str
    series: list[MetricSeries]


class LineData(BaseModel):
    """Payload for ``line`` — one or more time series drawn as lines.

    ``table`` is an optional companion data table rendered alongside the chart
    (e.g. a per-month breakdown under the line). ``None`` when the metric has
    no table.
    """

    unit: MetricUnit
    granularity: Granularity
    series: list[MetricSeries]
    by_class: list[ClassSeries] | None = None
    table: MetricTable | None = None


class BarsData(BaseModel):
    """Payload for ``bars`` — one or more time series drawn as bars.

    Structurally identical to ``LineData`` but declared separately: the two
    renderers evolve independently, and an alias would couple them.

    ``table`` is the same optional companion data table ``LineData`` carries.
    """

    unit: MetricUnit
    granularity: Granularity
    series: list[MetricSeries]
    by_class: list[ClassSeries] | None = None
    table: MetricTable | None = None


class BreakdownItem(BaseModel):
    """One labelled slice of a ``breakdown``."""

    key: str
    label: str
    value: float
    color_hint: str | None = None


class BreakdownData(BaseModel):
    """Payload for ``breakdown`` — a ranked list of labelled values."""

    unit: MetricUnit
    items: list[BreakdownItem]


class DonutSpec(BaseModel):
    """One donut in a ``donut_pair``; ``pct`` is a 0-100 percentage."""

    key: str
    label: str
    pct: float
    caption: str | None = None


class DonutPairData(BaseModel):
    """Payload for ``donut_pair`` — two side-by-side percentage donuts."""

    donuts: list[DonutSpec]


class ClassHeatmap(BaseModel):
    """The same heatmap grid, restricted to a single class."""

    class_id: str
    class_name: str
    cells: list[list[float | None]]


class HeatmapData(BaseModel):
    """Payload for ``heatmap`` — a ``rows`` x ``cols`` grid of values.

    A cell is ``None`` when the value is genuinely UNKNOWN rather than zero —
    a cohort too young to have reached that age, say. The distinction matters:
    rendering an immature cohort as 0% would read as total churn. A renderer
    must draw ``None`` as an absent cell, never as the bottom of the scale.
    Grids where every cell is measurable (attendance density) simply never
    emit one.
    """

    unit: MetricUnit
    rows: list[str]
    cols: list[str]
    cells: list[list[float | None]]
    by_class: list[ClassHeatmap] | None = None


class MemberListColumn(BaseModel):
    """One column header of a ``member_list``."""

    key: str
    label: str
    type: MemberListColumnType
    align: ColumnAlign | None = None


class MemberListRow(BaseModel):
    """One member row; ``cells`` is positional against ``columns``.

    ``member_id`` is carried separately so the CRM can deep-link the row to the
    member detail page without a magic cell index.
    """

    member_id: str
    cells: list[str | float | None]


class MemberListData(BaseModel):
    """Payload for ``member_list`` — a small tabular list of members."""

    columns: list[MemberListColumn]
    rows: list[MemberListRow]


class GrowthMetric(BaseModel):
    """One served metric: registry-owned display metadata + its payload.

    ``data`` is the already-validated payload serialized back out, so the
    envelope stays type-agnostic while the payload is guaranteed to match
    ``type``'s model.
    """

    key: str
    name: str
    categories: list[GrowthCategory]
    type: GrowthMetricType
    order: int
    computed_at: datetime
    data: dict[str, Any]


class GrowthResponse(BaseModel):
    """The whole Growth page for one gym.

    ``computed_at`` is the OLDEST surviving metric's compute time (the staleness
    floor the CRM shows), or ``None`` when nothing has been computed yet.
    """

    computed_at: datetime | None
    metrics: list[GrowthMetric]
