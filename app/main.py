from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import Base, engine
from app.routers import health, ingestion


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="WiFi Fleet Monitor", version="1.0.0", lifespan=lifespan)
app.include_router(health.router)
app.include_router(ingestion.router)
