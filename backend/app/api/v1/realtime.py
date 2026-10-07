"""Authenticated polling transports for durable operational events."""

import asyncio
import json
from datetime import datetime, timedelta, timezone
from typing import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select
from app.core.database import SessionLocal
from app.core.security import decode_access_token, get_current_admin
from app.models import AdminUser, OperationalEvent, RevokedAdminToken

router = APIRouter(tags=["realtime"])
EVENT_RETENTION = timedelta(days=7)
POLL_INTERVAL_SECONDS = 1.5
MAX_BATCH_SIZE = 100


def _event_payload(row: OperationalEvent) -> dict[str, object]:
    created_at = row.created_at
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return {
        "id": str(row.id),
        "type": row.type,
        "title": row.title,
        "timestamp": created_at.isoformat(),
    }


def _read_events(after_id: int) -> list[OperationalEvent]:
    cutoff = datetime.now(timezone.utc) - EVENT_RETENTION
    with SessionLocal() as db:
        return list(
            db.scalars(
                select(OperationalEvent)
                .where(
                    OperationalEvent.id > after_id,
                    OperationalEvent.created_at >= cutoff,
                )
                .order_by(OperationalEvent.id)
                .limit(MAX_BATCH_SIZE)
            ).all()
        )


def _latest_event_id() -> int:
    cutoff = datetime.now(timezone.utc) - EVENT_RETENTION
    with SessionLocal() as db:
        return db.scalar(
            select(func.max(OperationalEvent.id)).where(OperationalEvent.created_at >= cutoff)
        ) or 0


def _authenticated_websocket(websocket: WebSocket) -> bool:
    authorization = websocket.headers.get("authorization", "")
    token = (
        authorization[7:]
        if authorization.lower().startswith("bearer ")
        else websocket.cookies.get("admin_session")
    )
    if not token:
        return False

    try:
        claims = decode_access_token(token)
    except HTTPException:
        return False

    with SessionLocal() as db:
        admin = db.get(AdminUser, int(claims["sub"]))
        return (
            admin is not None
            and admin.is_active
            and db.get(RevokedAdminToken, claims["jti"]) is None
        )


async def _sse_stream(request: Request, after_id: int) -> AsyncIterator[str]:
    cursor = after_id
    heartbeat_at = asyncio.get_running_loop().time()
    while not await request.is_disconnected():
        events = await asyncio.to_thread(_read_events, cursor)
        for row in events:
            cursor = row.id
            payload = json.dumps({"data": _event_payload(row)}, separators=(",", ":"))
            yield f"id: {row.id}\nevent: operational\ndata: {payload}\n\n"
        now = asyncio.get_running_loop().time()
        if now - heartbeat_at >= 15:
            yield ": keep-alive\n\n"
            heartbeat_at = now
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


@router.get("/admin/events/stream")
def stream_events(
    request: Request,
    after: int | None = Query(default=None, ge=0),
    _: AdminUser = Depends(get_current_admin),
) -> StreamingResponse:
    header_cursor = request.headers.get("last-event-id")
    try:
        cursor = after if after is not None else int(header_cursor) if header_cursor else None
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid Last-Event-ID") from exc
    if cursor is not None and cursor < 0:
        raise HTTPException(status_code=400, detail="Invalid Last-Event-ID")
    if cursor is None:
        cursor = _latest_event_id()
    return StreamingResponse(
        _sse_stream(request, cursor),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "X-Accel-Buffering": "no",
        },
    )


@router.websocket("/ws")
async def websocket_events(websocket: WebSocket) -> None:
    if not _authenticated_websocket(websocket):
        await websocket.close(code=4401)
        return

    try:
        cursor_value = websocket.query_params.get("after")
        cursor = int(cursor_value) if cursor_value else await asyncio.to_thread(_latest_event_id)
        if cursor < 0:
            raise ValueError
    except ValueError:
        await websocket.close(code=4400, reason="Invalid event cursor")
        return

    await websocket.accept()
    try:
        while True:
            events = await asyncio.to_thread(_read_events, cursor)
            for row in events:
                await websocket.send_json({"data": _event_payload(row)})
                cursor = row.id
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
    except WebSocketDisconnect:
        return
