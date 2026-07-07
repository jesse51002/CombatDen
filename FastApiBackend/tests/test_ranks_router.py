"""Smoke + edge tests for the ranks router (two-level rank model)."""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from tests.conftest import make_rank_row


def _one(value: object) -> MagicMock:
    """A session.execute() result whose mappings().fetchone() → value."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = value
    return result


def _many(value: list) -> MagicMock:
    """A session.execute() result whose mappings().all() → value."""
    result = MagicMock()
    result.mappings.return_value.all.return_value = value
    return result


def _sub_type(value: str = "stripes") -> MagicMock:
    """A get_gym_sub_rank_type.sql result → {'sub_rank_type': value}."""
    return _one({"sub_rank_type": value})


def _enabled(gym_id: str, *, value: bool) -> MagicMock:
    return _one({"gym_id": gym_id, "is_rank_enabled": value})


# ---------- list / create ----------


def test_list_ranks_returns_items(client, db_pool_mock, auth_headers, fake_gym_id):
    """GET /api/v1/ranks/?gym_id=... returns the gym's ladder + sub_rank_type."""
    rank_id = str(uuid4())
    rows = [make_rank_row(rank_id=rank_id, gym_id=fake_gym_id)]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[_many(rows), _sub_type()])

    response = client.get(
        f"/api/v1/ranks/?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["rank_id"] == rank_id
    assert body["sub_rank_type"] == "stripes"


def test_create_rank_returns_201_with_backfill(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/ranks/ inserts the row and runs the in-session backfill
    (we just assert 201 + body shape; backfill behavior is asserted at the
    service level)."""
    rank_id = str(uuid4())
    row = make_rank_row(rank_id=rank_id, gym_id=fake_gym_id, name="White")

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(row),  # insert_rank
            _enabled(fake_gym_id, value=True),  # is_rank_enabled
            _many([]),  # backfill ladder read (empty)
            _one(None),  # backfill SQL
        ],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            "name": "White",
            "classes_to_next_major": 15,
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert body["rank_id"] == rank_id
    assert body["name"] == "White"


def test_create_rank_422_when_missing_required_field(client, auth_headers, fake_gym_id):
    """POST /api/v1/ranks/ rejects payloads missing required fields."""
    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            # missing name + classes_to_next_major
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_create_rank_negative_order_rejected(client, auth_headers, fake_gym_id):
    """main_rank_num_order must be >= 0."""
    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": -1,
            "name": "X",
            "classes_to_next_major": 0,
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_create_rank_empty_name_rejected(client, auth_headers, fake_gym_id):
    """Empty name rejected by min_length."""
    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            "name": "",
            "classes_to_next_major": 0,
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


# ---------- update ----------


def test_update_rank_200(client, db_pool_mock, auth_headers, fake_gym_id, fake_rank_id):
    """PUT /api/v1/ranks/{rank_id} updates mutable fields."""
    existing = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id)
    updated = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id, name="Blue")

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(existing),  # router get_rank (auth/exists)
            _one(updated),  # update_rank
        ],
    )
    session.commit = AsyncMock()

    response = client.put(
        f"/api/v1/ranks/{fake_rank_id}",
        json={"data": {"name": "Blue"}},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Blue"


def test_update_rank_400_when_empty_data(client, auth_headers, fake_rank_id):
    """PUT with empty data → 400 (no fields to update)."""
    fake_gym_id = str(uuid4())
    from src.main import app  # noqa: PLC0415 — local import to avoid cycle

    app.container.ranks_service.override(
        MagicMock(
            get_rank=AsyncMock(
                return_value=MagicMock(gym_id=fake_gym_id),
            ),
            update_rank=AsyncMock(
                side_effect=ValueError("No fields provided to update"),
            ),
        )
    )
    try:
        response = client.put(
            f"/api/v1/ranks/{fake_rank_id}",
            json={"data": {}},
            headers=auth_headers,
        )
        assert response.status_code == 400
    finally:
        app.container.ranks_service.reset_override()


# ---------- delete ----------


def test_delete_rank_204(client, db_pool_mock, auth_headers, fake_gym_id, fake_rank_id):
    """DELETE /api/v1/ranks/{rank_id} returns 204 on success."""
    existing = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id)

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(existing),  # get_rank in router
            _one(
                {
                    "gym_id": fake_gym_id,
                    "lower_rank_id": None,
                    "higher_rank_id": None,
                }
            ),  # get_neighbor_ranks
            _one(None),  # reassign_members_rank
            _one(None),  # delete_rank
        ],
    )
    session.commit = AsyncMock()

    response = client.delete(
        f"/api/v1/ranks/{fake_rank_id}",
        headers=auth_headers,
    )
    assert response.status_code == 204


# ---------- preset flows ----------


def test_seed_from_preset_returns_seeded_list(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/ranks/from-preset clones the ladder and returns the
    gym's full rank list."""
    seeded_rows = [
        make_rank_row(
            rank_id=str(uuid4()),
            gym_id=fake_gym_id,
            main_rank_num_order=0,
            name="White",
        ),
        make_rank_row(
            rank_id=str(uuid4()),
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            name="Blue",
        ),
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(None),  # insert_ranks_from_preset
            _one(None),  # set_gym_sub_rank_type_from_preset
            _sub_type(),  # get_gym_sub_rank_type (reconcile read + response)
            _one(None),  # reconcile_member_sub_index_for_gym
            _enabled(fake_gym_id, value=True),  # is_rank_enabled
            _many([]),  # backfill ladder read (empty)
            _one(None),  # backfill SQL
            _many(seeded_rows),  # response ladder
        ],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/from-preset",
        json={"gym_id": fake_gym_id, "preset_kind": "bjj_belts"},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 2
    assert body["sub_rank_type"] == "stripes"


def test_list_presets_flat(client, db_pool_mock, auth_headers):
    """GET /api/v1/ranks/presets?preset_kind=bjj_belts returns a flat list."""
    preset_rows = [
        {
            "preset_id": str(uuid4()),
            "preset_kind": "bjj_belts",
            "main_rank_num_order": 0,
            "name": "White",
            "image_url": None,
            "classes_to_next_major": 15,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        }
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=_many(preset_rows))

    response = client.get(
        "/api/v1/ranks/presets?preset_kind=bjj_belts",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["name"] == "White"


def test_get_presets_grouped_builds_nested_structure(client, db_pool_mock, auth_headers):
    """GET /api/v1/ranks/presets/grouped groups flat main rows by
    preset_kind. Hand-crafted dataset to verify the single-pass grouper
    crosses preset-kind boundaries correctly."""
    rows = [
        {
            "preset_id": str(uuid4()),
            "preset_kind": "bjj_belts",
            "main_rank_num_order": 0,
            "name": "White",
            "image_url": None,
            "classes_to_next_major": 15,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        },
        {
            "preset_id": str(uuid4()),
            "preset_kind": "bjj_belts",
            "main_rank_num_order": 1,
            "name": "Blue",
            "image_url": None,
            "classes_to_next_major": 20,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        },
        {
            "preset_id": str(uuid4()),
            "preset_kind": "flat",
            "main_rank_num_order": 0,
            "name": "Member",
            "image_url": None,
            "classes_to_next_major": 20,
            "sub_rank_count": 0,
            "implied_sub_rank_type": None,
        },
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=_many(rows))

    response = client.get(
        "/api/v1/ranks/presets/grouped",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()["presets"]

    assert set(body.keys()) == {"bjj_belts", "flat"}
    bjj = body["bjj_belts"]
    assert [p["name"] for p in bjj] == ["White", "Blue"]
    assert body["flat"][0]["name"] == "Member"


# ---------- enabled toggle ----------


def test_get_rank_enabled_returns_state(client, db_pool_mock, auth_headers, fake_gym_id):
    """GET /api/v1/ranks/enabled returns the gym's flag."""
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=_enabled(fake_gym_id, value=True))

    response = client.get(
        f"/api/v1/ranks/enabled?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json() == {
        "gym_id": fake_gym_id,
        "is_rank_enabled": True,
    }


def test_set_rank_enabled_round_trip(client, db_pool_mock, auth_headers, fake_gym_id):
    """PUT /api/v1/ranks/enabled flips the flag and returns it."""
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _enabled(fake_gym_id, value=False),  # current
            _enabled(fake_gym_id, value=True),  # update
            _many([]),  # backfill ladder read (empty)
            _one(None),  # backfill SQL
        ],
    )
    session.commit = AsyncMock()

    response = client.put(
        "/api/v1/ranks/enabled",
        json={"gym_id": fake_gym_id, "is_rank_enabled": True},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json() == {
        "gym_id": fake_gym_id,
        "is_rank_enabled": True,
    }


# ---------- promote-member ----------


def test_promote_member_200_with_new_rank(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id
):
    """POST /api/v1/ranks/promote-member advances a rank-less member to the
    lowest rank and returns the new rank."""
    low_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=low_id, gym_id=fake_gym_id, name="White"),
        make_rank_row(
            rank_id=str(uuid4()),
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            name="Blue",
        ),
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(
                {
                    "current_rank_id": None,
                    "current_sub_index": None,
                    "gym_id": fake_gym_id,
                }
            ),  # get_member_current_rank
            _many(ladder),  # list_ranks
            _sub_type(),  # get_gym_sub_rank_type
            _one({"member_id": fake_member_id}),  # set_member_rank (truthy row)
            _one(None),  # insert_rank_activity
        ],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/promote-member",
        json={"gym_id": fake_gym_id, "member_id": fake_member_id},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["member_id"] == fake_member_id
    assert body["new_rank"]["rank_id"] == low_id


def test_promote_member_409_when_at_top(client, auth_headers, fake_gym_id, fake_member_id):
    """The router maps the 'highest rank' ValueError to 409."""
    from src.main import app  # noqa: PLC0415 — local import to avoid cycle

    app.container.ranks_service.override(
        MagicMock(
            promote_member=AsyncMock(
                side_effect=ValueError("Member is already at the highest rank"),
            ),
        )
    )
    try:
        response = client.post(
            "/api/v1/ranks/promote-member",
            json={"gym_id": fake_gym_id, "member_id": fake_member_id},
            headers=auth_headers,
        )
        assert response.status_code == 409
    finally:
        app.container.ranks_service.reset_override()


def test_promote_member_404_when_member_missing(
    client, auth_headers, fake_gym_id, fake_member_id
):
    """The router maps a 'Member not found' ValueError to 404."""
    from src.main import app  # noqa: PLC0415

    app.container.ranks_service.override(
        MagicMock(
            promote_member=AsyncMock(side_effect=ValueError("Member not found")),
        )
    )
    try:
        response = client.post(
            "/api/v1/ranks/promote-member",
            json={"gym_id": fake_gym_id, "member_id": fake_member_id},
            headers=auth_headers,
        )
        assert response.status_code == 404
    finally:
        app.container.ranks_service.reset_override()


# ---------- set-member-rank ----------


def test_set_member_rank_200(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id
):
    """POST /api/v1/ranks/set-member-rank sets an explicit rank."""
    target_id = str(uuid4())
    ladder = [make_rank_row(rank_id=target_id, gym_id=fake_gym_id)]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(
                {
                    "current_rank_id": None,
                    "current_sub_index": None,
                    "gym_id": fake_gym_id,
                }
            ),  # get_member_current_rank
            _many(ladder),  # list_ranks
            _sub_type(),  # get_gym_sub_rank_type
            _one({"member_id": fake_member_id}),  # set_member_rank (truthy row)
            _one(None),  # insert_rank_activity
        ],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/set-member-rank",
        json={
            "gym_id": fake_gym_id,
            "member_id": fake_member_id,
            "rank_id": target_id,
        },
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["new_rank"]["rank_id"] == target_id


# ---------- reorder ----------


def test_reorder_ranks_200_returns_list(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/ranks/reorder applies the new ordering and returns the
    reordered ladder."""
    rank_a = str(uuid4())
    rank_b = str(uuid4())
    ladder = [
        make_rank_row(rank_id=rank_a, gym_id=fake_gym_id, name="Blue"),
        make_rank_row(
            rank_id=rank_b,
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            name="White",
        ),
    ]
    reordered = [
        make_rank_row(rank_id=rank_b, gym_id=fake_gym_id, name="White"),
        make_rank_row(
            rank_id=rank_a,
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            name="Blue",
        ),
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _many(ladder),  # validation pre-read
            _one(None),  # shift
            _one(None),  # finalize
            _many(reordered),  # response ladder
            _sub_type(),  # response sub_rank_type
        ],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/reorder",
        json={
            "gym_id": fake_gym_id,
            "ranks": [
                {"rank_id": rank_a, "main_rank_num_order": 1},
                {"rank_id": rank_b, "main_rank_num_order": 0},
            ],
        },
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert len(response.json()["items"]) == 2


def test_reorder_ranks_400_on_partial_payload(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """A reorder payload that misses part of the ladder is a clean 400, not
    a constraint 500."""
    rank_a = str(uuid4())
    rank_b = str(uuid4())
    ladder = [
        make_rank_row(rank_id=rank_a, gym_id=fake_gym_id),
        make_rank_row(rank_id=rank_b, gym_id=fake_gym_id, main_rank_num_order=1),
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[_many(ladder)])
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/reorder",
        json={
            "gym_id": fake_gym_id,
            "ranks": [
                {"rank_id": rank_a, "main_rank_num_order": 0},
            ],
        },
        headers=auth_headers,
    )
    assert response.status_code == 400
    assert "entire ladder" in response.json()["detail"]


# ---------- ready-to-promote board ----------


def test_ready_to_promote_200(client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id):
    """GET /api/v1/ranks/ready-to-promote returns the paginated board."""
    rows = [
        {
            "member_id": fake_member_id,
            "name": "Ada Lovelace",
            "avatar_url": None,
            "main_rank_id": str(uuid4()),
            "main_name": "White",
            "current_sub_index": 1,
            "image_url": None,
            "classes_since": 8,
            "step_denominator": 10,
            "total_count": 1,
        }
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[_sub_type(), _many(rows)])

    response = client.get(
        f"/api/v1/ranks/ready-to-promote?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total_count"] == 1
    assert body["items"][0]["member_id"] == fake_member_id
    # stripes sub_index 1 → "1 Stripe"
    assert body["items"][0]["sub_label"] == "1 Stripe"


# ---------- members-in-rank roster ----------


def test_members_in_rank_200(
    client,
    db_pool_mock,
    auth_headers,
    fake_gym_id,
    fake_member_id,
    fake_rank_id,
):
    """GET /api/v1/ranks/{rank_id}/members returns the paginated roster."""
    rank_row = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id)
    rows = [
        {
            "member_id": fake_member_id,
            "name": "Ada Lovelace",
            "avatar_url": None,
            "current_sub_index": None,
            "classes_since": 3,
            "step_denominator": 15,
            "total_count": 1,
        }
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(rank_row),  # router get_rank (auth/gym resolution)
            _sub_type(),  # get_gym_sub_rank_type
            _many(rows),  # list_members_in_rank
        ],
    )

    response = client.get(
        f"/api/v1/ranks/{fake_rank_id}/members",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total_count"] == 1
    assert body["items"][0]["member_id"] == fake_member_id


def test_members_in_rank_404_when_rank_missing(client, db_pool_mock, auth_headers, fake_rank_id):
    """A rank_id that doesn't resolve returns 404 (router get_rank guard)."""
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[_one(None)])  # get_rank → not found

    response = client.get(
        f"/api/v1/ranks/{fake_rank_id}/members",
        headers=auth_headers,
    )
    assert response.status_code == 404


# ---------- per-sub-index counts ----------


def test_sub_rank_counts_200(client, db_pool_mock, auth_headers, fake_gym_id, fake_rank_id):
    """GET /api/v1/ranks/{rank_id}/sub-rank-counts returns the total on the
    rank plus a sparse per-sub-index breakdown (the total is summed). The
    gym is derived from the rank (resolved first), not a query param."""
    rank_row = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id)
    rows = [
        {"sub_index": 0, "count": 3},
        {"sub_index": 1, "count": 2},
    ]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(rank_row),  # router get_rank (auth/gym resolution)
            _many(rows),  # count_members_by_sub_index
        ],
    )

    response = client.get(
        f"/api/v1/ranks/{fake_rank_id}/sub-rank-counts",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total_count"] == 5
    assert body["counts"] == [
        {"sub_index": 0, "count": 3},
        {"sub_index": 1, "count": 2},
    ]


def test_sub_rank_counts_none_gym_single_null_row(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_rank_id
):
    """On a 'none' gym members carry a NULL sub-index, so the breakdown is a
    single {null, total} row."""
    rank_row = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id)
    rows = [{"sub_index": None, "count": 7}]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            _one(rank_row),  # router get_rank (auth/gym resolution)
            _many(rows),  # count_members_by_sub_index
        ],
    )

    response = client.get(
        f"/api/v1/ranks/{fake_rank_id}/sub-rank-counts",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total_count"] == 7
    assert body["counts"] == [{"sub_index": None, "count": 7}]


def test_sub_rank_counts_404_when_rank_missing(client, db_pool_mock, auth_headers, fake_rank_id):
    """A rank_id that doesn't resolve returns 404 (router get_rank guard)."""
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[_one(None)])  # get_rank → not found

    response = client.get(
        f"/api/v1/ranks/{fake_rank_id}/sub-rank-counts",
        headers=auth_headers,
    )
    assert response.status_code == 404
