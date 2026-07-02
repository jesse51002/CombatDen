from pydantic import BaseModel, ConfigDict


class SeedModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    def to_insert_dict(self) -> dict:
        # mode="json" recursively converts every field to a JSON-safe value
        # (UUID -> str, date/datetime/time -> ISO string, nested BaseModel ->
        # dict, Enum -> its value) at ANY nesting depth -- not just the
        # top-level keys a shallow per-key loop would catch. This matters for
        # JSONB columns holding nested models (e.g. gym_class_schedules.
        # weekday_slots: dict[str, list[ScheduleSlot]], each ScheduleSlot
        # carrying its own time + UUID fields) -- a shallow conversion left
        # those nested time/UUID objects un-stringified, which the Supabase
        # client's JSON encoder can't serialize (TypeError: Object of type
        # time is not JSON serializable).
        return self.model_dump(exclude_none=True, mode="json")
