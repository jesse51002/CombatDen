from typing import Literal, Optional
from uuid import UUID

from . import SeedModel


class GymCreate(SeedModel):
    gym_id: UUID
    gym_name: str
    rank_enabled: bool = True
    rank_preset: Optional[
        Literal["bjj", "muay_thai", "karate", "taekwondo", "judo", "mma"]
    ] = None
    rank_1_name: Optional[str] = None
    rank_2_name: Optional[str] = None
    rank_3_name: Optional[str] = None
    rank_4_name: Optional[str] = None
    rank_5_name: Optional[str] = None
    estimated_classes_rank_1: int = 20
    estimated_classes_rank_2: int = 100
    estimated_classes_rank_3: int = 200
    estimated_classes_rank_4: int = 200
    estimated_classes_rank_5: int = 200
