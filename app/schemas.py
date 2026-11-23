from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class IngestRecord(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    status: str = Field(min_length=1, max_length=64)
    observed_at: datetime
    details: str | None = Field(default=None, max_length=4096)


class IngestRequest(BaseModel):
    records: list[IngestRecord] = Field(min_length=1, max_length=1000)


class IngestResponse(BaseModel):
    accepted: int


class HealthResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str
