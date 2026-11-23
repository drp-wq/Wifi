import hmac
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.repository import save_records
from app.schemas import IngestRequest, IngestResponse

router = APIRouter(prefix="/api/v1", tags=["ingestion"])
bearer = HTTPBearer(auto_error=False)


def require_ingest_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    expected = settings.ingest_token.get_secret_value()
    supplied = credentials.credentials if credentials else ""
    if not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing bearer token")


@router.post("/ingest", response_model=IngestResponse, dependencies=[Depends(require_ingest_token)])
def ingest(payload: IngestRequest, db: Annotated[Session, Depends(get_db)]) -> IngestResponse:
    return IngestResponse(accepted=save_records(db, payload.records))
