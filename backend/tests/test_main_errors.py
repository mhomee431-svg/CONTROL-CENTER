import asyncio
import json
import logging

from fastapi import Request
from starlette.responses import Response

from app.main import request_id_middleware, unhandled_exception_handler


def _request(request_id: str) -> Request:
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/diagnostic",
            "headers": [(b"x-request-id", request_id.encode())],
            "query_string": b"",
            "server": ("testserver", 80),
            "client": ("testclient", 1234),
            "scheme": "http",
            "state": {},
        }
    )


def test_request_id_is_returned_and_invalid_client_value_is_replaced():
    request = _request("bad request id")

    async def call_next(_: Request) -> Response:
        return Response()

    response = asyncio.run(request_id_middleware(request, call_next))

    assert response.headers["X-Request-ID"] == request.state.request_id
    assert " " not in request.state.request_id


def test_unhandled_errors_are_logged_with_request_id_without_leaking_details(caplog):
    request = _request("req-test-123")
    request.state.request_id = "req-test-123"
    exception = RuntimeError("database connection secret")

    with caplog.at_level(logging.ERROR):
        response = asyncio.run(unhandled_exception_handler(request, exception))

    body = json.loads(response.body)
    assert response.status_code == 500
    assert response.headers["X-Request-ID"] == "req-test-123"
    assert body["error_code"] == "INTERNAL_ERROR"
    assert "database connection secret" not in response.body.decode()
    assert "req-test-123" in caplog.text
    assert any(record.exc_info for record in caplog.records)
