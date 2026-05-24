"""ClassOutput contract: exactly four class cards, each a name + image url,
extra="forbid"."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from schema import ClassOutput


def _doc(n: int = 4) -> dict:
    return {
        "company_name": "Killer Muay Thai",
        "app_id": "combatden",
        "classes": [
            {
                "name": f"Class {i}",
                "image_url": f"https://img/{i}.jpg",
                "description": f"What class {i} is about.",
                "instructor_name": f"Coach {i}",
                "instructor_bio": f"Bio for coach {i}.",
                "instructor_image_url": f"https://img/coach{i}.jpg",
            }
            for i in range(n)
        ],
    }


def test_round_trips_with_four() -> None:
    out = ClassOutput.model_validate(_doc())
    assert len(out.classes) == 4
    assert out.classes[0].name == "Class 0"
    assert out.classes[0].instructor_name == "Coach 0"
    assert out.classes[0].instructor_bio == "Bio for coach 0."
    assert out.classes[0].instructor_image_url == "https://img/coach0.jpg"


def test_missing_instructor_field_rejected() -> None:
    doc = _doc()
    del doc["classes"][0]["instructor_bio"]
    with pytest.raises(ValidationError):
        ClassOutput.model_validate(doc)


@pytest.mark.parametrize("n", [0, 3, 5])
def test_must_be_exactly_four(n: int) -> None:
    with pytest.raises(ValidationError):
        ClassOutput.model_validate(_doc(n))


def test_empty_name_or_url_rejected() -> None:
    doc = _doc()
    doc["classes"][0]["name"] = ""
    with pytest.raises(ValidationError):
        ClassOutput.model_validate(doc)
    doc = _doc()
    doc["classes"][0]["image_url"] = ""
    with pytest.raises(ValidationError):
        ClassOutput.model_validate(doc)


def test_extra_key_rejected() -> None:
    doc = _doc()
    doc["classes"][0]["schedule"] = "Mon 6pm"  # not in the contract
    with pytest.raises(ValidationError):
        ClassOutput.model_validate(doc)
