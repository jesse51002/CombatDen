"""Public Pydantic v2 schema for the videos_config.yaml contract."""

from schema.big_group import BigGroup
from schema.class_output import ClassImage
from schema.cost import CostSource, CostStage
from schema.cost_log import CostEntry
from schema.gym import Gym, GymSpecifications, GymVideos, RewardCard, ScanCost
from schema.gym_feed import GymCard, GymDetail, GymSpecificationView, GymsPage
from schema.gym_type import GymType
from schema.parent_gym_type import ParentGymType
from schema.scan_verdict import ScanVerdict
from schema.video_classification import VideoClassification
from schema.video_feed import FeedPreview, FeedSection, VideoCard, VideosFeed
from schema.verdict_reason import VerdictReason
from schema.video_output import VideoOutput
from schema.video_type import VideoType

__all__ = [
    "BigGroup",
    "ClassImage",
    "CostEntry",
    "CostSource",
    "CostStage",
    "FeedPreview",
    "FeedSection",
    "Gym",
    "GymCard",
    "GymDetail",
    "GymSpecifications",
    "GymSpecificationView",
    "GymType",
    "GymVideos",
    "GymsPage",
    "ParentGymType",
    "RewardCard",
    "ScanCost",
    "ScanVerdict",
    "VerdictReason",
    "VideoCard",
    "VideoClassification",
    "VideoOutput",
    "VideoType",
    "VideosFeed",
]
