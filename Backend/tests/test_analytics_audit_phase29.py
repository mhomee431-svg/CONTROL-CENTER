"""Phase 29 - Analytics & Audit System tests.

Covers against a real in-memory SQLite database:
  * Event generation (customer / shopkeeper / platform catalogs, validation,
    PII scrubbing, paired search-outcome events)
  * Event integrity (hash-chained audit trail, tamper detection,
    immutability guards)
  * Aggregation (daily rollups, idempotent rebuilds)
  * Dashboard correctness (search trends, popular entities, conversion,
    freshness, subscriptions, platform health)
  * Report correctness (generation, persistence, payload accuracy)
  * VERIFY - every business metric traces back to raw platform events

Privacy note: analytics events never store personal information — verified
by scrubbing assertions below.
"""

import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import ForbiddenError, NotFoundError, ValidationError  # noqa: E402
from app.models.admin import AuditLog, Report  # noqa: E402
from app.models.analytics_event import (  # noqa: E402
    AnalyticsDailyAggregate,
    AnalyticsEvent,
)
from app.models.base import Base  # noqa: E402
from app.services import analytics_system as an  # noqa: E402
from app.services import audit_service  # noqa: E402


# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if isinstance(sd_arg, str) and sd_arg.lower() == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None)
            if ou is not None and str(ou_arg).strip().lower().startswith("now"):
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()


# Tables required by the phase-29 test matrix (FK parents included).
from app.models.product import Brand, Category, ProductMaster  # noqa: E402
from app.models.shop import Shop  # noqa: E402

TABLES = [
    Shop.__table__,
    Category.__table__,
    Brand.__table__,
    ProductMaster.__table__,
    AnalyticsEvent.__table__,
    AnalyticsDailyAggregate.__table__,
    AuditLog.__table__,
    Report.__table__,
]


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


NOW = datetime.now(timezone.utc)


# ── Event generation ─────────────────────────────────────────────────────────
class TestEventGeneration:
    def test_customer_event_catalog(self, db):
        for name in [
            "SEARCH", "SEARCH_RESULT_CLICK", "PRODUCT_VIEW", "SHOP_VIEW",
            "DIRECTIONS", "SAVE", "SHARE",
        ]:
            an.track_event(db, event_name=name, actor_type="CUSTOMER", actor_id=7)
        names = {e.event_name for e in db.query(AnalyticsEvent).all()}
        assert names == an.CUSTOMER_EVENTS
        assert db.query(AnalyticsEvent).count() == 7

    def test_shopkeeper_event_catalog(self, db):
        for name in [
            "PRODUCT_ADDED", "INVENTORY_UPDATED", "PRICE_CHANGED",
            "OFFER_CREATED", "BARCODE_SCAN", "EXCEL_IMPORT", "POS_SYNC",
        ]:
            an.track_event(
                db, event_name=name, actor_type="SHOPKEEPER", actor_id=9, shop_id=3
            )
        assert (
            db.query(AnalyticsEvent)
            .filter(AnalyticsEvent.actor_type == "SHOPKEEPER")
            .count()
            == 7
        )

    def test_platform_events(self, db):
        an.track_event(db, event_name="INVENTORY_FRESHNESS", actor_type="PLATFORM",
                       shop_id=5, metric_value=0.87)
        an.track_event(db, event_name="API_PERFORMANCE", actor_type="PLATFORM",
                       metric_value=142.5)
        an.track_event(db, event_name="ERROR", actor_type="PLATFORM",
                       props={"path": "/search"})
        kinds = {e.event_name for e in db.query(AnalyticsEvent).all()}
        assert kinds == {"INVENTORY_FRESHNESS", "API_PERFORMANCE", "ERROR"}

    def test_unknown_event_rejected(self, db):
        with pytest.raises(ValidationError):
            an.track_event(db, event_name="NOT_A_REAL_EVENT", actor_type="CUSTOMER")

    def test_actor_mismatch_rejected(self, db):
        with pytest.raises(ValidationError):
            an.track_event(db, event_name="SEARCH", actor_type="SHOPKEEPER")
        with pytest.raises(ValidationError):
            an.track_event(db, event_name="ERROR", actor_type="CUSTOMER")

    def test_unknown_actor_rejected(self, db):
        with pytest.raises(ValidationError):
            an.track_event(db, event_name="SEARCH", actor_type="ADMIN_BOT")

    def test_pii_props_are_scrubbed(self, db):
        event = an.track_event(
            db,
            event_name="PRODUCT_VIEW",
            actor_type="CUSTOMER",
            actor_id=1,
            props={
                "email": "user@example.com",
                "phone_number": "+91 98765 43210",
                "latitude": 25.59,
                "source_screen": "HOME_FEED",
                "position": 4,
            },
        )
        assert event.props is not None
        assert "email" not in event.props
        assert "phone_number" not in event.props
        assert "latitude" not in event.props
        assert event.props["source_screen"] == "HOME_FEED"
        assert event.props["position"] == 4

    def test_track_search_emits_outcome_pair(self, db):
        ok = an.track_search(db, user_id=None, session_id="sess-ok",
                             query="milk", result_count=12)
        bad = an.track_search(db, user_id=None, session_id="sess-bad",
                              query="zzz", result_count=0)
        names = {
            e.session_id: e.event_name
            for e in db.query(AnalyticsEvent)
            .filter(AnalyticsEvent.actor_type == "PLATFORM")
            .all()
        }
        assert names["sess-ok"] == "SEARCH_SUCCESS"
        assert names["sess-bad"] == "SEARCH_FAILURE"
        assert ok.metric_value == 12.0

    def test_query_normalized_and_capped(self, db):
        long_q = "x" * 500
        event = an.track_search(db, user_id=None, query=f"  {long_q}  ",
                                result_count=1)
        assert event.query == "x" * 255


# ── Event / audit integrity ──────────────────────────────────────────────────
class TestEventIntegrity:
    def test_chain_valid_after_critical_actions(self, db):
        for i in range(3):
            audit_service.record_critical_action(
                db,
                action="VERIFY_SHOP" if i == 0 else "UPDATE",
                entity_type="SHOP",
                entity_id=10 + i,
                user_id=1,
                description=f"action {i}",
                new_values={"status": "ACTIVE"},
            )
        result = audit_service.verify_audit_chain(db)
        assert result == {"valid": True, "checked": 3, "total": 3, "broken_at": None}

    def test_records_are_chained(self, db):
        first = audit_service.record_critical_action(
            db, action="CREATE", entity_type="OFFER", entity_id=1
        )
        second = audit_service.record_critical_action(
            db, action="CREATE", entity_type="OFFER", entity_id=2
        )
        assert first.record_hash != second.record_hash
        assert second.prev_record_hash == first.record_hash

    def test_tampering_detected(self, db):
        e1 = audit_service.record_critical_action(
            db, action="CREATE", entity_type="SHOP", entity_id=1
        )
        e2 = audit_service.record_critical_action(
            db, action="UPDATE", entity_type="SHOP", entity_id=1,
            old_values={"a": 1}, new_values={"a": 2},
        )
        # Casual modification: rewrite history directly in the table.
        db.query(AuditLog).filter(AuditLog.id == e2.id).update(
            {"new_values": {"a": 999}}
        )
        db.expire_all()
        result = audit_service.verify_audit_chain(db)
        assert result["valid"] is False
        assert result["broken_at"] == e2.id

    def test_deletion_breaks_chain(self, db):
        for i in range(3):
            audit_service.record_critical_action(
                db, action="CREATE", entity_type="USER", entity_id=i + 1
            )
        middle = db.query(AuditLog).order_by(AuditLog.id.asc()).offset(1).first()
        db.delete(middle)
        db.flush()
        result = audit_service.verify_audit_chain(db)
        assert result["valid"] is False

    def test_audit_entries_cannot_be_mutated(self, db):
        with pytest.raises(ForbiddenError):
            audit_service.update_audit_entry()
        with pytest.raises(ForbiddenError):
            audit_service.delete_audit_entry()
        with pytest.raises(ForbiddenError):
            audit_service.assert_no_direct_mutation("admin")
        with pytest.raises(ForbiddenError):
            audit_service.assert_no_direct_mutation(None)

    def test_self_modifying_trails_refused(self, db):
        with pytest.raises(ForbiddenError):
            audit_service.record_critical_action(
                db, action="DELETE", entity_type="AUDIT_LOG", entity_id=5
            )


# ── Aggregation ──────────────────────────────────────────────────────────────
class TestAggregation:
    def test_daily_aggregation_counts(self, db):
        today = datetime.now(timezone.utc)
        yesterday = today - timedelta(days=1)
        an.track_event(db, event_name="PRODUCT_VIEW", actor_type="CUSTOMER",
                       actor_id=1, product_master_id=11, category_id=31,
                       occurred_at=today)
        an.track_event(db, event_name="PRODUCT_VIEW", actor_type="CUSTOMER",
                       actor_id=2, product_master_id=11, category_id=31,
                       session_id="sess-a", occurred_at=today)
        an.track_event(db, event_name="PRODUCT_VIEW", actor_type="CUSTOMER",
                       actor_id=3, product_master_id=11, category_id=31,
                       session_id="sess-b", occurred_at=today)

        result = an.aggregate_daily(db, today.date())
        assert result["groups"] >= 1
        rows = {
            (r["event_name"], r["product_master_id"]): r
            for r in an.read_aggregates(db)
            if r["aggregate_date"] == today.date().isoformat()
        }
        pv = rows[("PRODUCT_VIEW", 11)]
        assert pv["event_count"] == 3
        assert pv["distinct_sessions"] == 2
        assert pv["distinct_actors"] == 3

    def test_aggregation_is_idempotent_per_day(self, db):
        today = datetime.now(timezone.utc)
        for _ in range(4):
            an.track_event(db, event_name="SHARE", actor_type="CUSTOMER",
                           actor_id=1, occurred_at=today)
        an.aggregate_daily(db, today.date())
        an.aggregate_daily(db, today.date())
        # 1 grouped row (same day/name/dims), rebuilt not duplicated.
        assert db.query(AnalyticsDailyAggregate.id).count() == 1
        agg = db.query(AnalyticsDailyAggregate).first()
        assert agg.event_count == 4

    def test_metric_sum_aggregated(self, db):
        now = datetime.now(timezone.utc)
        for ms in (100, 200, 300):
            an.track_event(db, event_name="API_PERFORMANCE", actor_type="PLATFORM",
                           metric_value=ms, occurred_at=now)
        an.aggregate_daily(db, now.date())
        agg = (
            db.query(AnalyticsDailyAggregate)
            .filter(AnalyticsDailyAggregate.event_name == "API_PERFORMANCE")
            .first()
        )
        assert agg.metric_sum == 600.0


# ── Dashboard correctness ────────────────────────────────────────────────────
class TestDashboards:
    def test_search_trends(self, db):
        now = datetime.now(timezone.utc)
        for _ in range(3):
            an.track_search(db, user_id=1, session_id="s1", query="milk",
                            result_count=5, occurred_at=now)
        an.track_search(db, user_id=2, session_id="s2", query="bread",
                        result_count=0, occurred_at=now)
        trends = an.search_trends(db, days=7)
        assert trends["total_searches"] == 4
        assert trends["failures"] == 1
        assert trends["success_rate"] == round(3 / 4, 4)
        top = {t["query"]: t["count"] for t in trends["top_queries"]}
        assert top == {"milk": 3, "bread": 1}
        assert trends["daily"][0]["searches"] == 4

    def test_popular_products_and_categories(self, db):
        now = datetime.now(timezone.utc)
        for _ in range(3):
            an.track_event(db, event_name="PRODUCT_VIEW", actor_type="CUSTOMER",
                           product_master_id=101, category_id=31, occurred_at=now)
        an.track_event(db, event_name="SEARCH_RESULT_CLICK", actor_type="CUSTOMER",
                       product_master_id=102, category_id=32, occurred_at=now)
        products = an.popular_products(db, days=7)
        assert products[0]["product_master_id"] == 101
        assert products[0]["activity_count"] == 3
        categories = {c["category_id"]: c["event_count"]
                      for c in an.popular_categories(db, days=7)}
        assert categories == {31: 3, 32: 1}

    def test_popular_shops(self, db):
        now = datetime.now(timezone.utc)
        an.track_event(db, event_name="SHOP_VIEW", actor_type="CUSTOMER",
                       shop_id=21, session_id="x", occurred_at=now)
        an.track_event(db, event_name="DIRECTIONS", actor_type="CUSTOMER",
                       shop_id=21, session_id="y", occurred_at=now)
        shops = an.popular_shops(db, days=7)
        assert shops[0] == {"shop_id": 21, "activity_count": 2,
                            "distinct_sessions": 2}

    def test_conversion_rate(self, db):
        now = datetime.now(timezone.utc)
        # s1 searches then visits a shop; s2 only searches; s3 only views.
        an.track_event(db, event_name="SEARCH", actor_type="CUSTOMER",
                       session_id="s1", query="tea", metric_value=3, occurred_at=now)
        an.track_event(db, event_name="SHOP_VIEW", actor_type="CUSTOMER",
                       shop_id=21, session_id="s1", occurred_at=now)
        an.track_event(db, event_name="SEARCH", actor_type="CUSTOMER",
                       session_id="s2", query="jalebi", metric_value=0, occurred_at=now)
        an.track_event(db, event_name="SHOP_VIEW", actor_type="CUSTOMER",
                       shop_id=22, session_id="s3", occurred_at=now)
        conv = an.search_to_shop_conversion(db, days=7)
        assert conv["search_sessions"] == 2
        assert conv["converted_to_shop"] == 1
        assert conv["conversion_rate"] == 0.5

    def test_inventory_freshness(self, db):
        now = datetime.now(timezone.utc)
        an.track_event(db, event_name="INVENTORY_FRESHNESS", actor_type="PLATFORM",
                       shop_id=21, metric_value=0.8, occurred_at=now)
        an.track_event(db, event_name="INVENTORY_FRESHNESS", actor_type="PLATFORM",
                       shop_id=22, metric_value=1.0, occurred_at=now)
        fresh = an.inventory_freshness(db, days=7)
        assert fresh["overall_avg_freshness"] == 0.9
        by_shop = {b["shop_id"]: b["avg_freshness"] for b in fresh["by_shop"]}
        assert by_shop == {21: 0.8, 22: 1.0}

    def test_subscription_metrics(self, db):
        now = datetime.now(timezone.utc)
        plan_events = [
            ("SUBSCRIPTION_CREATED", None),
            ("SUBSCRIPTION_CREATED", None),
            ("SUBSCRIPTION_CANCELLED", None),
            ("PAYMENT_SUCCEEDED", 199.0),
            ("PAYMENT_SUCCEEDED", 499.0),
        ]
        for name, value in plan_events:
            an.track_event(db, event_name=name, actor_type="SHOPKEEPER",
                           shop_id=3, metric_value=value, occurred_at=now)
        metrics = an.subscription_metrics(db, days=30)
        assert metrics["subscriptions_created"] == 2
        assert metrics["subscriptions_cancelled"] == 1
        assert metrics["churn_rate"] == 0.5
        assert metrics["revenue"] == 698.0

    def test_platform_health(self, db):
        now = datetime.now(timezone.utc)
        for ms in (100, 200, 300):
            an.track_event(db, event_name="API_PERFORMANCE", actor_type="PLATFORM",
                           metric_value=ms, occurred_at=now)
        an.track_event(db, event_name="ERROR", actor_type="PLATFORM",
                       props={"where": "search"}, occurred_at=now)
        an.track_search(db, user_id=1, session_id="h1", query="a",
                        result_count=1, occurred_at=now)
        an.track_search(db, user_id=1, session_id="h2", query="b",
                        result_count=0, occurred_at=now)
        health = an.platform_health(db, hours=24)
        assert health["api_calls"] == 3
        assert health["latency_ms_avg"] == 200.0
        assert health["latency_ms_p95"] == 300.0
        assert health["errors"] == 1
        assert health["search_failure_rate"] == 0.5


# ── Report correctness ───────────────────────────────────────────────────────
class TestReports:
    def test_all_report_types_generate_ready(self, db):
        for report_type in an.REPORT_BUILDERS:
            report = an.generate_report(
                db, report_type=report_type, generated_by=1, params={"days": 7}
            )
            assert report.status == "READY"
            assert report.report_type == f"ANALYTICS_{report_type}"
            assert report.result_json is not None
            assert "data" in report.result_json

    def test_unknown_report_type_rejected(self, db):
        with pytest.raises(NotFoundError):
            an.generate_report(db, report_type="HOROSCOPES")

    def test_report_payload_matches_dashboard(self, db):
        now = datetime.now(timezone.utc)
        an.track_search(db, user_id=1, session_id="r1", query="milk",
                        result_count=9, occurred_at=now)
        report = an.generate_report(db, report_type="SEARCH_TRENDS",
                                    generated_by=42, params={"days": 7})
        live = an.search_trends(db, days=7)
        assert report.status == "READY"
        assert report.generated_by == 42
        assert report.result_json["data"]["total_searches"] == live["total_searches"]

    def test_get_report_missing(self, db):
        with pytest.raises(NotFoundError):
            an.get_report(db, 99999)


# ── VERIFY: metrics trace back to platform events ────────────────────────────
class TestVerifyTraceability:
    def test_funnel_traces_to_raw_events(self, db):
        """End-to-end funnel: every dashboard number recomputes from raw rows."""
        now = datetime.now(timezone.utc)
        # Session 1: search -> click -> shop view -> directions (full funnel)
        an.track_search(db, user_id=1, session_id="f1", query="sweets",
                        result_count=8, occurred_at=now)
        an.track_event(db, event_name="SEARCH_RESULT_CLICK", actor_type="CUSTOMER",
                       session_id="f1", product_master_id=501, shop_id=61,
                       occurred_at=now)
        an.track_event(db, event_name="SHOP_VIEW", actor_type="CUSTOMER",
                       shop_id=61, session_id="f1", occurred_at=now)
        an.track_event(db, event_name="DIRECTIONS", actor_type="CUSTOMER",
                       shop_id=61, session_id="f1", occurred_at=now)
        # Session 2: failed search only.
        an.track_search(db, user_id=2, session_id="f2", query="unobtainium",
                        result_count=0, occurred_at=now)
        # Session 3: search -> shop view.
        an.track_search(db, user_id=3, session_id="f3", query="sweets",
                        result_count=4, occurred_at=now)
        an.track_event(db, event_name="SHOP_VIEW", actor_type="CUSTOMER",
                       shop_id=61, session_id="f3", occurred_at=now)

        # Raw event counts...
        raw = {
            name: db.query(AnalyticsEvent.id)
            .filter(AnalyticsEvent.event_name == name)
            .count()
            for name in ["SEARCH", "SHOP_VIEW", "DIRECTIONS"]
        }
        assert raw == {"SEARCH": 3, "SHOP_VIEW": 2, "DIRECTIONS": 1}

        # ...equal dashboard numbers derived from those same events.
        trends = an.search_trends(db, days=7)
        assert trends["total_searches"] == raw["SEARCH"]
        assert trends["failures"] == 1

        conversion = an.search_to_shop_conversion(db, days=7)
        assert conversion["search_sessions"] == 3
        assert conversion["converted_to_shop"] == 2
        assert conversion["conversion_rate"] == round(2 / 3, 4)

        shops = {s["shop_id"]: s for s in an.popular_shops(db, days=7)}
        # SHOP_VIEW(2) + DIRECTIONS(1) + SEARCH_RESULT_CLICK(1) for shop 61
        assert shops[61]["activity_count"] == 4

        # Aggregates reconcile with the same raw stream.
        an.aggregate_daily(db, now.date())
        search_agg = (
            db.query(AnalyticsDailyAggregate)
            .filter(AnalyticsDailyAggregate.event_name == "SEARCH")
            .first()
        )
        assert search_agg.event_count == 3
        assert search_agg.distinct_sessions == 3

    def test_report_generation_from_funnel(self, db):
        now = datetime.now(timezone.utc)
        an.track_search(db, user_id=1, session_id="z1", query="chai",
                        result_count=6, occurred_at=now)
        report = an.generate_report(db, report_type="CONVERSION")
        data = report.result_json["data"]
        assert data["search_sessions"] == 1
        assert data["converted_to_shop"] == 0
        assert data["conversion_rate"] == 0.0