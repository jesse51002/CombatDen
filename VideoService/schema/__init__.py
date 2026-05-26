"""Public Pydantic v2 schema for the videos_config.yaml contract."""

from schema.big_group import BigGroup
from schema.class_output import ClassImage, ClassOutput
from schema.video_classification import VideoClassification
from schema.video_feed import VideoCard, VideosFeed
from schema.verdict_reason import VerdictReason
from schema.video_output import VideoOutput, VideosManifest, VideosOutput
from schema.video_type import VideoType
from schema.videos_config import VideoSearch, VideosConfig

__all__ = [
    "BigGroup",
    "ClassImage",
    "ClassOutput",
    "VerdictReason",
    "VideoCard",
    "VideoClassification",
    "VideoOutput",
    "VideoSearch",
    "VideoType",
    "VideosConfig",
    "VideosFeed",
    "VideosManifest",
    "VideosOutput",
]
