from sqlalchemy.orm import Session

from app.models import FleetRecord
from app.schemas import IngestRecord


def save_records(db: Session, records: list[IngestRecord]) -> int:
    db.add_all(
        [
            FleetRecord(
                device_id=record.device_id,
                status=record.status,
                observed_at=record.observed_at,
                details=record.details,
            )
            for record in records
        ]
    )
    db.commit()
    return len(records)
