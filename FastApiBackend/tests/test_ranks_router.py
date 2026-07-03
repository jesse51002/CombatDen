"""Smoke + edge tests for the ranks router."""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from tests.conftest import make_rank_row

# ---------- list / create ----------


def test_list_ranks_returns_items(client, db_pool_mock, auth_headers, fake_gym_id):
    """GET /api/v1/ranks/?gym_id=... returns the gym's rank ladder."""
    rank_id = str(uuid4())
    rows = [make_rank_row(rank_id=rank_id, gym_id=fake_gym_id)]

    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = rows

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=list_result)

    response = client.get(
        f"/api/v1/ranks/?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["rank_id"] == rank_id


def test_create_rank_returns_201_with_backfill(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/ranks/ inserts the row and runs the in-session
    backfill (we just assert 201 + body shape; backfill behavior is
    asserted at the service level)."""
    rank_id = str(uuid4())
    row = make_rank_row(
        rank_id=rank_id,
        gym_id=fake_gym_id,
        main_name="White",
        sub_name="0 stripes",
    )

    insert_result = MagicMock()
    insert_result.mappings.return_value.fetchone.return_value = row
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "is_rank_enabled": True,
    }
    backfill_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[insert_result, enabled_result, backfill_result],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "White",
            "sub_name": "0 stripes",
            "classes_till_rankup": 15,
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert body["rank_id"] == rank_id
    assert body["main_name"] == "White"


def test_create_rank_422_when_missing_required_field(client, auth_headers, fake_gym_id):
    """POST /api/v1/ranks/ rejects payloads missing required fields."""
    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            # missing sub_rank_num_order, main_name, sub_name, classes_till_rankup
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


# ---------- update ----------


def test_update_rank_200(client, db_pool_mock, auth_headers, fake_gym_id, fake_rank_id):
    """PUT /api/v1/ranks/{rank_id} updates mutable fields."""
    existing = make_rank_row(rank_id=fake_rank_id, gym_id=fake_gym_id)
    updated = make_rank_row(
        rank_id=fake_rank_id,
        gym_id=fake_gym_id,
        main_name="Blue",
    )

    get_result = MagicMock()
    get_result.mappings.return_value.fetchone.return_value = existing
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=get_result)

    db_pool_mock.execute_with_retry = AsyncMock(return_value=updated)

    response = client.put(
        f"/api/v1/ranks/{fake_rank_id}",
        json={"data": {"main_name": "Blue"}},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["main_name"] == "Blue"


def test_update_rank_400_when_empty_data(client, auth_headers, fake_rank_id):
    """PUT with empty data → 400 (no fields to update)."""
    fake_gym_id = str(uuid4())
    # Stub get_rank so the auth/exists check passes.
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

    get_result = MagicMock()
    get_result.mappings.return_value.fetchone.return_value = existing

    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "lower_rank_id": None,
        "higher_rank_id": None,
    }
    reassign_result = MagicMock()
    delete_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            get_result,  # get_rank in router
            neighbor_result,  # get_neighbor_ranks in service
            reassign_result,  # reassign_members_rank
            delete_result,  # delete_rank
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
    """POST /api/v1/ranks/from-preset clones the ladder and returns
    the gym's full rank list."""
    seeded_rows = [
        make_rank_row(
            rank_id=str(uuid4()),
            gym_id=fake_gym_id,
            main_rank_num_order=0,
            sub_rank_num_order=0,
            main_name="White",
            sub_name="0 stripes",
        ),
        make_rank_row(
            rank_id=str(uuid4()),
            gym_id=fake_gym_id,
            main_rank_num_order=0,
            sub_rank_num_order=1,
            main_name="White",
            sub_name="1 stripe",
        ),
    ]

    insert_result = MagicMock()
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "is_rank_enabled": True,
    }
    backfill_result = MagicMock()
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = seeded_rows

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[
            insert_result,
            enabled_result,
            backfill_result,
            list_result,
        ],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/from-preset",
        json={"gym_id": fake_gym_id, "gym_type": "bjj"},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 2


def test_list_presets_flat(client, db_pool_mock, auth_headers):
    """GET /api/v1/ranks/presets?gym_type=bjj returns a flat list."""
    preset_rows = [
        {
            "preset_id": str(uuid4()),
            "gym_type": "bjj",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "White",
            "sub_name": "0 stripes",
            "classes_till_rankup": 15,
            "image_url": None,
            "color": "#FFFFFF",
        }
    ]
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = preset_rows

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=list_result)

    response = client.get(
        "/api/v1/ranks/presets?gym_type=bjj",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["main_name"] == "White"


def test_get_presets_grouped_builds_nested_structure(client, db_pool_mock, auth_headers):
    """GET /api/v1/ranks/presets/grouped groups by gym_type, then by
    main rank with sub-ranks nested. Hand-crafted dataset to verify
    the single-pass grouper crosses gym_type and main_rank boundaries
    correctly."""
    rows = [
        # bjj — main 0 (White) with two sub-ranks
        {
            "preset_id": str(uuid4()),
            "gym_type": "bjj",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "White",
            "sub_name": "0 stripes",
            "classes_till_rankup": 15,
            "image_url": None,
            "color": "#FFFFFF",
        },
        {
            "preset_id": str(uuid4()),
            "gym_type": "bjj",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 1,
            "main_name": "White",
            "sub_name": "1 stripe",
            "classes_till_rankup": 15,
            "image_url": None,
            "color": "#FFFFFF",
        },
        # bjj — main 1 (Blue) with one sub-rank
        {
            "preset_id": str(uuid4()),
            "gym_type": "bjj",
            "main_rank_num_order": 1,
            "sub_rank_num_order": 0,
            "main_name": "Blue",
            "sub_name": "0 stripes",
            "classes_till_rankup": 20,
            "image_url": None,
            "color": "#1F6FEB",
        },
        # mma — main 0 (Beginner) with one
        {
            "preset_id": str(uuid4()),
            "gym_type": "mma",
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "Beginner",
            "sub_name": "",
            "classes_till_rankup": 20,
            "image_url": None,
            "color": "#9CA3AF",
        },
    ]
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = rows

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=list_result)

    response = client.get(
        "/api/v1/ranks/presets/grouped",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()["presets"]

    assert set(body.keys()) == {"bjj", "mma"}
    bjj = body["bjj"]
    assert len(bjj) == 2
    assert bjj[0]["main_name"] == "White"
    assert len(bjj[0]["sub_ranks"]) == 2
    assert bjj[1]["main_name"] == "Blue"
    assert len(bjj[1]["sub_ranks"]) == 1

    mma = body["mma"]
    assert len(mma) == 1
    assert mma[0]["main_name"] == "Beginner"
    assert len(mma[0]["sub_ranks"]) == 1


# ---------- enabled toggle ----------


def test_get_rank_enabled_returns_state(client, db_pool_mock, auth_headers, fake_gym_id):
    """GET /api/v1/ranks/enabled returns the gym's flag."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "is_rank_enabled": True,
    }
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

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
    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "is_rank_enabled": False,
    }
    update_result = MagicMock()
    update_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "is_rank_enabled": True,
    }
    backfill_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[current_result, update_result, backfill_result],
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


# ---------- pydantic validation ----------


@pytest.mark.parametrize(
    "color,expected",
    [
        ("red", 422),
        ("#FFF", 422),
        ("#GGGGGG", 422),
        ("#1F6FEB", 201),
    ],
)
def test_create_rank_color_validation(
    client, db_pool_mock, auth_headers, fake_gym_id, color, expected
):
    """Pydantic enforces hex color format on POST."""
    rank_id = str(uuid4())
    row = make_rank_row(rank_id=rank_id, gym_id=fake_gym_id, color=color)
    insert_result = MagicMock()
    insert_result.mappings.return_value.fetchone.return_value = row
    enabled_result = MagicMock()
    enabled_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "is_rank_enabled": False,
    }

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[insert_result, enabled_result])
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "White",
            "sub_name": "0 stripes",
            "classes_till_rankup": 15,
            "color": color,
        },
        headers=auth_headers,
    )
    assert response.status_code == expected


def test_create_rank_negative_order_rejected(client, auth_headers, fake_gym_id):
    """Order fields must be >= 0."""
    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": -1,
            "sub_rank_num_order": 0,
            "main_name": "X",
            "sub_name": "Y",
            "classes_till_rankup": 0,
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_create_rank_empty_name_rejected(client, auth_headers, fake_gym_id):
    """Empty main_name / sub_name rejected by min_length."""
    response = client.post(
        "/api/v1/ranks/",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            "sub_rank_num_order": 0,
            "main_name": "",
            "sub_name": "Y",
            "classes_till_rankup": 0,
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


# ---------- promote-member ----------


def test_promote_member_200_with_new_rank(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id
):
    """POST /api/v1/ranks/promote-member advances a rank-less member
    to the lowest rank and returns the new rank."""
    low_id = str(uuid4())
    ladder = [
        make_rank_row(rank_id=low_id, gym_id=fake_gym_id, main_name="White"),
        make_rank_row(
            rank_id=str(uuid4()),
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            main_name="Blue",
        ),
    ]

    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = {
        "current_rank_id": None,
        "gym_id": fake_gym_id,
    }
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = ladder
    set_result = MagicMock()
    set_result.mappings.return_value.fetchone.return_value = {
        "member_id": fake_member_id,
        "current_rank_id": low_id,
    }
    activity_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[current_result, list_result, set_result, activity_result],
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
    target_row = make_rank_row(rank_id=target_id, gym_id=fake_gym_id)

    current_result = MagicMock()
    current_result.mappings.return_value.fetchone.return_value = {
        "current_rank_id": None,
        "gym_id": fake_gym_id,
    }
    target_result = MagicMock()
    target_result.mappings.return_value.fetchone.return_value = target_row
    set_result = MagicMock()
    set_result.mappings.return_value.fetchone.return_value = {
        "member_id": fake_member_id,
        "current_rank_id": target_id,
    }
    activity_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[current_result, target_result, set_result, activity_result],
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
    """POST /api/v1/ranks/reorder applies the new ordering and returns
    the reordered ladder."""
    rank_a = str(uuid4())
    rank_b = str(uuid4())
    ladder = [
        make_rank_row(rank_id=rank_a, gym_id=fake_gym_id, main_name="Blue"),
        make_rank_row(
            rank_id=rank_b,
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            main_name="White",
        ),
    ]
    reordered = [
        make_rank_row(rank_id=rank_b, gym_id=fake_gym_id, main_name="White"),
        make_rank_row(
            rank_id=rank_a,
            gym_id=fake_gym_id,
            main_rank_num_order=1,
            main_name="Blue",
        ),
    ]

    ladder_result = MagicMock()
    ladder_result.mappings.return_value.all.return_value = ladder
    shift_result = MagicMock()
    finalize_result = MagicMock()
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = reordered

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[ladder_result, shift_result, finalize_result, list_result],
    )
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/reorder",
        json={
            "gym_id": fake_gym_id,
            "ranks": [
                {
                    "rank_id": rank_a,
                    "main_rank_num_order": 1,
                    "sub_rank_num_order": 0,
                },
                {
                    "rank_id": rank_b,
                    "main_rank_num_order": 0,
                    "sub_rank_num_order": 0,
                },
            ],
        },
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert len(response.json()["items"]) == 2


def test_reorder_ranks_400_on_partial_payload(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """A reorder payload that misses part of the ladder is a clean
    400, not a constraint 500."""
    rank_a = str(uuid4())
    rank_b = str(uuid4())
    ladder = [
        make_rank_row(rank_id=rank_a, gym_id=fake_gym_id),
        make_rank_row(
            rank_id=rank_b,
            gym_id=fake_gym_id,
            main_rank_num_order=1,
        ),
    ]
    ladder_result = MagicMock()
    ladder_result.mappings.return_value.all.return_value = ladder

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[ladder_result])
    session.commit = AsyncMock()

    response = client.post(
        "/api/v1/ranks/reorder",
        json={
            "gym_id": fake_gym_id,
            "ranks": [
                {
                    "rank_id": rank_a,
                    "main_rank_num_order": 0,
                    "sub_rank_num_order": 0,
                },
            ],
        },
        headers=auth_headers,
    )
    assert response.status_code == 400
    assert "entire ladder" in response.json()["detail"]


# ---------- whole-group operations ----------


def test_rename_group_200_returns_ladder(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """PUT /api/v1/ranks/rename-group renames atomically and returns
    the updated ladder."""
    renamed = [
        make_rank_row(rank_id=str(uuid4()), gym_id=fake_gym_id, main_name="Azul"),
    ]
    rename_result = MagicMock()
    rename_result.mappings.return_value.all.return_value = [
        {"rank_id": renamed[0]["rank_id"]},
    ]
    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = renamed

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[rename_result, list_result])
    session.commit = AsyncMock()

    response = client.put(
        "/api/v1/ranks/rename-group",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 0,
            "new_main_name": "Azul",
        },
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["items"][0]["main_name"] == "Azul"


def test_rename_group_404_when_missing(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """Renaming a group with no rows is a 404."""
    rename_result = MagicMock()
    rename_result.mappings.return_value.all.return_value = []

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[rename_result])
    session.commit = AsyncMock()

    response = client.put(
        "/api/v1/ranks/rename-group",
        json={
            "gym_id": fake_gym_id,
            "main_rank_num_order": 9,
            "new_main_name": "Azul",
        },
        headers=auth_headers,
    )
    assert response.status_code == 404


def test_delete_group_204(client, db_pool_mock, auth_headers, fake_gym_id):
    """DELETE /api/v1/ranks/group reassigns members then deletes the
    whole group."""
    neighbor_result = MagicMock()
    neighbor_result.mappings.return_value.fetchone.return_value = {
        "gym_id": fake_gym_id,
        "lower_rank_id": str(uuid4()),
        "higher_rank_id": None,
    }
    reassign_result = MagicMock()
    delete_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[neighbor_result, reassign_result, delete_result],
    )
    session.commit = AsyncMock()

    response = client.delete(
        "/api/v1/ranks/group",
        params={"gym_id": fake_gym_id, "main_rank_num_order": 2},
        headers=auth_headers,
    )
    assert response.status_code == 204
