from enum import StrEnum


class TaskType(StrEnum):
    """Mirrors the Postgres `task_type` enum.

    What operation a task performs. Each value has a registered executor in
    the backend (`src/tasks/service/tasks_executor.py`).
    """

    membership_reprice = "membership_reprice"


class TaskStatus(StrEnum):
    """Mirrors the Postgres `task_status` enum.

    Lifecycle of a task and of each of its items. Items: `pending` = queued
    (also the state a retryable failure returns to), `running` = claimed by an
    executor, then `completed` or `failed` (terminal, after max attempts).
    Tasks: `pending` until the first item is claimed, `running` while items
    are in flight, then `completed` (all items completed) or `failed` (any
    item failed).
    """

    pending = "pending"
    running = "running"
    completed = "completed"
    failed = "failed"


class ProrationBehavior(StrEnum):
    """Mirrors the Postgres `proration_behavior` enum.

    How a membership's first (or repriced) recurring charge is handled
    relative to the billing anchor (the date the next full cycle bills).
    `prorate_to_anchor` invoices the partial period from today through the
    anchor immediately; `no_charge` charges nothing now — the membership
    still starts and the first full bill lands on the anchor. Maps to
    Stripe's `proration_behavior` (`always_invoice` / `none`) only at the
    Stripe SDK boundary.
    """

    prorate_to_anchor = "prorate_to_anchor"
    no_charge = "no_charge"
