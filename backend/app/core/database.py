"""Database engine, session factory and declarative base."""

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import settings

# check_same_thread is a SQLite-only concern; harmless for other drivers once
# guarded, so it is passed conditionally.
database_url = settings.database_url
connect_args = {"check_same_thread": False} if str(database_url).startswith("sqlite") else {}

engine = create_engine(database_url, connect_args=connect_args, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db():
    """FastAPI dependency yielding a session that always closes."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
