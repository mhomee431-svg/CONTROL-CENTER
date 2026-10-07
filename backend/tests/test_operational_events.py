from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app.core.database import Base
from app.core.operational_events import register_operational_events
from app.models import OperationalEvent, SearchQuery


def test_search_creates_one_non_sensitive_event_in_the_same_transaction():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    register_operational_events()
    register_operational_events()

    with Session(engine) as db:
        db.add(SearchQuery(query="private search contents"))
        db.commit()

        events = list(db.scalars(select(OperationalEvent)).all())

    assert len(events) == 1
    assert events[0].type == "CUSTOMER_SEARCH"
    assert events[0].title == "A customer searched nearby products"
    assert "private search contents" not in events[0].title
    engine.dispose()
