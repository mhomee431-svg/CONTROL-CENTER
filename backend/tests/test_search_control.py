"""Search Control Center endpoints.

The console's highest-priority discovery surfaces. These tests pin three
contracts that keep operator decisions honest:

* The summary counts real recorded searches and reports uncollected metrics
  (latency, clicks, matching) as null — never as zero or an estimate.
* The zero-results endpoint groups real zero-result queries with their true
  first/last seen dates, and its gap evidence (potential category, catalog
  candidates) is computed from real tables, with matched_products always empty.
* The quality endpoint's per-term rates are computed from real rows.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, Category, Product, SearchQuery


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _client_with(session_factory: sessionmaker) -> tuple[TestClient, Session]:
    """A TestClient wired to an in-memory database with an owner token."""
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
    return client, db


def test_summary_counts_real_searches_and_nulls_uncollected_metrics():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add_all([
            SearchQuery(query="rice", result_count=3, location="Mumbai",
                        searched_at=_now() - timedelta(days=1)),
            SearchQuery(query="rice", result_count=2, location="Mumbai",
                        searched_at=_now() - timedelta(days=2)),
            SearchQuery(query="unicorn widget", result_count=0, location="Delhi",
                        searched_at=_now() - timedelta(days=1)),
        ])
        db.commit()

        body = client.get("/api/v1/admin/search/summary", params={"days": 7}).json()["data"]

        vol = body["volume"]
        assert vol["total_searches"] == 3
        assert vol["unique_searchers"] == 0  # no user_id recorded
        quality = body["quality"]
        assert quality["success_rate"] == round((2 / 3) * 100, 2)
        assert quality["zero_result_rate"] == round((1 / 3) * 100, 2)
        # Real average: (3 + 2 + 0) / 3.
        assert quality["avg_result_count"] == round(5 / 3, 2)
        # Uncollected metrics are honest nulls, never fabricated zeros.
        assert quality["latency_ms"] is None
        assert quality["click_rate"] is None
        assert quality["search_failures"] is None
        assert quality["product_matching_rate"] is None
        assert quality["shop_matching_rate"] is None
        assert body["diagnostics"]["exact_matching"] is None

        # Top searches carry per-term zero counts; the zero list carries a range.
        top = {t["term"]: t for t in body["top_searches"]}
        assert top["rice"]["count"] == 2
        assert top["rice"]["zero_count"] == 0
        assert top["unicorn widget"]["zero_count"] == 1
        zq = {z["query"]: z for z in body["zero_result_queries"]}
        assert zq["unicorn widget"]["count"] == 1
        assert zq["unicorn widget"]["first_seen"] is not None
        assert zq["unicorn widget"]["last_seen"] is not None
    finally:
        client.close()
        app.dependency_overrides.clear()



def test_zero_results_groups_demand_and_computes_gap_evidence_from_real_tables():
    """Gap evidence comes from real catalog rows; matched_products stays empty."""
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add(Category(name="Drill Bits", is_active=True))
        db.add(Product(name="Cordless Drill Machine", category_name="Power Tools"))
        db.commit()

        older = _now() - timedelta(days=5)
        newer = _now() - timedelta(days=1)
        db.add_all([
            SearchQuery(query="bosch drill 10mm", result_count=0, location="Delhi",
                        searched_at=older),
            SearchQuery(query="bosch drill 10mm", result_count=0, location="Delhi",
                        searched_at=newer),
            # A successful search must NOT appear in the gap list.
            SearchQuery(query="rice", result_count=4, location="Mumbai",
                        searched_at=newer),
        ])
        db.commit()

        body = client.get(
            "/api/v1/admin/search/zero-results", params={"days": 30}
        ).json()["data"]
        assert body["total"] == 1
        row = body["items"][0]
        assert row["query"] == "bosch drill 10mm"
        assert row["count"] == 2
        # The real date range the operator is asked to show.
        assert row["first_seen"] is not None and row["last_seen"] is not None
        assert row["first_seen"] <= row["last_seen"]
        assert row["location"] == "Delhi"
        # Token overlap against a REAL category name — not invented.
        assert row["potential_category"] == "Drill Bits"
        # A real product shares the token "drill" — a candidate, not a match.
        assert row["candidate_products"] >= 1
        assert any("Drill" in name for name in row["candidate_examples"])
        # Zero-result means zero matches, always.
        assert row["matched_products"] == []
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_quality_endpoint_reports_per_term_rates_from_real_rows():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add_all([
            SearchQuery(query="rice", result_count=5, searched_at=_now() - timedelta(days=1)),
            SearchQuery(query="rice", result_count=0, searched_at=_now() - timedelta(days=2)),
            SearchQuery(query="rice", result_count=2, searched_at=_now() - timedelta(days=3)),
            SearchQuery(query="milk", result_count=0, searched_at=_now() - timedelta(days=1)),
        ])
        db.commit()

        body = client.get(
            "/api/v1/admin/search/quality", params={"days": 7}
        ).json()["data"]
        by_term = {r["term"]: r for r in body["items"]}
        assert by_term["rice"]["searches"] == 3
        assert by_term["rice"]["zero_count"] == 1
        assert by_term["rice"]["zero_rate"] == round((1 / 3) * 100, 2)
        assert by_term["rice"]["success_rate"] == round((2 / 3) * 100, 2)
        assert by_term["milk"]["zero_rate"] == 100.0

        # Free-text review of a single term.
        one = client.get(
            "/api/v1/admin/search/quality", params={"days": 7, "search": "milk"}
        ).json()["data"]
        assert one["total"] == 1
        assert one["items"][0]["term"] == "milk"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_search_control_endpoints_require_authentication():
    session_factory = _fresh_db()
    client, _db = _client_with(session_factory)
    try:
        anonymous = TestClient(app)
        for path in (
            "/api/v1/admin/search/summary",
            "/api/v1/admin/search/zero-results",
            "/api/v1/admin/search/quality",
        ):
            assert anonymous.get(path).status_code == 401, path
        anonymous.close()
    finally:
        client.close()
        app.dependency_overrides.clear()
