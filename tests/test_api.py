import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker

os.environ["INGEST_TOKEN"] = "test-secret-token"
os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from app.config import get_settings  # noqa: E402
from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402
from app.models import FleetRecord  # noqa: E402


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        get_settings.cache_clear()
        cls.tempdir = tempfile.TemporaryDirectory()
        cls.engine = create_engine(f"sqlite:///{Path(cls.tempdir.name) / 'test.db'}")
        cls.Session = sessionmaker(bind=cls.engine, autoflush=False, expire_on_commit=False)
        Base.metadata.create_all(bind=cls.engine)

        def override_get_db():
            db = cls.Session()
            try:
                yield db
            finally:
                db.close()

        app.dependency_overrides[get_db] = override_get_db
        cls.client = TestClient(app)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.client.close()
        app.dependency_overrides.clear()
        cls.engine.dispose()
        cls.tempdir.cleanup()

    def setUp(self) -> None:
        with self.Session() as db:
            db.query(FleetRecord).delete()
            db.commit()

    def test_health(self) -> None:
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_ingest_requires_token(self) -> None:
        response = self.client.post("/api/v1/ingest", json={"records": []})
        self.assertEqual(response.status_code, 401)

    def test_ingest_accepts_valid_records(self) -> None:
        response = self.client.post(
            "/api/v1/ingest",
            headers={"Authorization": "Bearer test-secret-token"},
            json={"records": [{"device_id": "ap-01", "status": "online", "observed_at": datetime.now(timezone.utc).isoformat()}]},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"accepted": 1})
        with self.Session() as db:
            count = db.scalar(select(func.count()).select_from(FleetRecord))
        self.assertEqual(count, 1)

    def test_ingest_rejects_invalid_payload(self) -> None:
        response = self.client.post(
            "/api/v1/ingest",
            headers={"Authorization": "Bearer test-secret-token"},
            json={"records": [{"device_id": "", "status": "online", "observed_at": "not-a-date"}]},
        )
        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
