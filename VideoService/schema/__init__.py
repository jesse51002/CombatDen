"""Public Pydantic v2 schema for the videos_config.yaml contract."""

from schema.big_group import BigGroup
from schema.class_output import ClassImage
from schema.cost_log import CostEntry, ExecutionType
from schema.gym import Gym, GymSpecifications, GymVideos, RewardCard, ScanCost
from schema.gym_feed import GymCard, GymsPage
from schema.gym_type import GymType
from schema.parent_gym_type import ParentGymType
from schema.scan_verdict import ScanVerdict
from schema.video_classification import VideoClassification
from schema.video_feed import ThemeClasses, ThemeRewards, VideoCard, VideosFeed
from schema.verdict_reason import VerdictReason
from schema.video_output import VideoOutput
from schema.video_type import VideoType

__all__ = [
    "BigGroup",
    "ClassImage",
    "CostEntry",
    "ExecutionType",
    "Gym",
    "GymCard",
    "GymSpecifications",
    "GymType",
    "GymVideos",
    "GymsPage",
    "ParentGymType",
    "RewardCard",
    "ScanCost",
    "ScanVerdict",
    "ThemeClasses",
    "ThemeRewards",
    "VerdictReason",
    "VideoCard",
    "VideoClassification",
    "VideoOutput",
    "VideoType",
    "VideosFeed",
]
