from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class SeedModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    def to_insert_dict(self) -> dict:
        data = self.model_dump(exclude_none=True)
        for key, value in data.items():
            if isinstance(value, UUID):
                data[key] = str(value)
            elif isinstance(value, (date, datetime, time)):
                data[key] = value.isoformat()
            elif isinstance(value, list):
                data[key] = [str(v) if isinstance(v, UUID) else v for v in value]
        return data
