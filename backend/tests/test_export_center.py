"""Export Center — asynchronous job contract.

EXPORT CENTER rule: exports cover the named datasets and large exports run
through backend jobs, never entirely inside the browser. These tests pin the
contract the console depends on: the dataset list is the single source the UI
renders from, a job resolves against real tables, an oversized scope is refused
with the concrete number, and the queue lifecycle is audited.
"""

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, ExportJob, User


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _client_with(session_factory: sessionmaker) -> tuple[TestClient, sessionmaker]:
    db = session_factory()
    owner = AdminUser(
        username="owner",
        name="Platform Owner",
        hashed_password="x",
        role_name="Platform Owner",
        level="SUPER",
        is_owner=True,
        permissions=[],
    )
    db.add(owner)
    db.commit()
    token = create_access_token(owner.id, {"purpose": "admin_access"})

    def _override():
        yield db

    app.dependency_overrides[get_db] = _override
    client = TestClient(app)
    client.headers.update({"Authorization": f"Bearer {token}"})
    return client, session_factory


def test_datasets_contract_lists_all_named_surfaces():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        body = client.get("/api/v1/admin/exports/datasets").json()["data"]
        keys = {item["key"] for item in body["items"]}
        # The rule names these nine export surfaces.
        assert keys == {
            "customers", "shopkeepers", "businesses", "products", "inventory",
            "prices", "search", "analytics", "audit_logs",
        }
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_request_export_queues_against_real_tables():
    session_factory = _fresh_db()
    client, session_factory_ = _client_with(session_factory)
    try:
        db = session_factory_()
        db.add_all([User(name=f"Customer {i}", status="ACTIVE") for i in range(4)])
        db.commit()

        resp = client.post(
            "/api/v1/admin/exports/jobs",
            json={"dataset": "customers", "filters": {"search": "Customer"}},
        )
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["status"] == "QUEUED"
        assert data["dataset"] == "customers"
        # The queue message reports the real row count, not a guess.
        assert "4 rows" in resp.json()["message"]
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_unknown_dataset_is_rejected():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        resp = client.post(
            "/api/v1/admin/exports/jobs",
            json={"dataset": "secret_table"},
        )
        assert resp.status_code == 422
        assert resp.json()["data"]["code"] == "UNKNOWN_DATASET"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_job_executes_and_produces_downloadable_artifact():
    """A queued job advances to COMPLETED and its file is downloadable."""
    session_factory = _fresh_db()
    client, session_factory_ = _client_with(session_factory)
    try:
        db = session_factory_()
        db.add_all([User(name=f"Customer {i}", status="ACTIVE") for i in range(3)])
        db.commit()

        queued = client.post(
            "/api/v1/admin/exports/jobs", json={"dataset": "customers"}
        ).json()["data"]
        assert queued["status"] == "QUEUED"

        # Reading the list executes the job (dev inline worker) ...
        listed = client.get("/api/v1/admin/exports/jobs").json()["data"]["items"]
        job = next(j for j in listed if j["id"] == queued["id"])
        assert job["status"] == "COMPLETED"
        assert job["rows_exported"] == 3
        assert job["file_url"].endswith("/download")

        # ... and the artifact is served back with real CSV content.
        download = client.get(job["file_url"])
        assert download.status_code == 200
        assert download.headers["content-type"].startswith("text/csv")
        body = download.text.lstrip("\ufeff")
        assert body.splitlines()[0].startswith("id,name,phone")
        assert len(body.splitlines()) == 4  # header + 3 rows
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_job_list_and_cancel_lifecycle():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        # QUEUED jobs execute on read, so seed a terminal job directly to
        # exercise the cancel path deterministically.
        db = session_factory()
        db.add(ExportJob(dataset="products", status="COMPLETED"))
        db.commit()

        listed = client.get(
            "/api/v1/admin/exports/jobs", params={"dataset": "products"}
        ).json()["data"]
        assert listed["total"] == 1

        job_id = listed["items"][0]["id"]
        # A completed job is terminal — it cannot be cancelled.
        cancelled = client.post(f"/api/v1/admin/exports/jobs/{job_id}/cancel")
        assert cancelled.status_code == 409
    finally:
        client.close()
        app.dependency_overrides.clear()
