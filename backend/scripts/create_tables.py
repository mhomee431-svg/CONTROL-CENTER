import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

import traceback  # noqa: E402

from sqlalchemy import create_engine  # noqa: E402

import app.models  # noqa: E402,F401
from app.core.config import settings  # noqa: E402
from app.database.session import Base  # noqa: E402

print("DB:", settings.DATABASE_URL, flush=True)
print("SYNC:", settings.sqlalchemy_sync_url, flush=True)

try:
    eng = create_engine(settings.sqlalchemy_sync_url)
    Base.metadata.create_all(eng)
    print("TABLES CREATED OK", flush=True)
except Exception:
    traceback.print_exc()
    raise