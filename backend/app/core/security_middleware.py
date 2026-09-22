"""API Security middleware.

Provides:
- Input sanitization
- Request size limits
- SQL injection detection
- XSS prevention headers
- Content-Type validation
"""
import json
import logging
import re
from typing import Callable, Optional, Set

from fastapi import Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

# Matches a JWT-shaped string (three base64url segments separated by dots).
# JWT payloads are opaque, server-generated tokens that are never interpreted
# by the SQL layer — a single base64url segment can legitimately contain a bare
# `--` (SQL comment terminator) or other rule substrings purely by chance, so
# scanning JWT values produces false positives without adding real signal.
# Fields like ``refresh_token`` and ``access_token`` carry JWTs, so they must
# be excluded from the body scan. Prose fields (descriptions, reports, etc.)
# are still scanned field-by-field.
_JWT_RE = re.compile(
    r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"
)


def _looks_like_jwt(value: str) -> bool:
    """Return True if *value* is a JWT (opaque token, safe to skip)."""
    if not isinstance(value, str):
        return False
    return bool(_JWT_RE.match(value))

logger = logging.getLogger("app.core.security_middleware")


class InputSanitizationMiddleware(BaseHTTPMiddleware):
    """Middleware to sanitize incoming request data."""
    
    # Patterns that might indicate SQL injection attempts.
    #
    # These match STATEMENT SHAPES, not bare keywords. A bare-keyword rule is
    # unusable on a platform whose users write free prose: "stock did not
    # update", "delete product does nothing", "failed to create the offer" are
    # ordinary sentences, and a `\b(UPDATE|DELETE|CREATE)\b` rule answers 400
    # INVALID_INPUT to every one of them — a shopkeeper could not even file a
    # support report containing the word "update". Each pattern below still
    # catches the injection it is named for (keyword + object + clause,
    # comment terminators, boolean and stacked payloads, dangerous procedures).
    SQL_INJECTION_PATTERNS = [
        # Keyword followed by its SQL object: `SELECT * FROM`, `UPDATE x SET`.
        r"(\bSELECT\b[\w\s,*.\"']{0,80}?\bFROM\b)",
        r"(\bINSERT\b[\w\s,*.\"']{0,80}?\bINTO\b)",
        r"(\bUPDATE\b\s+[\w.\"'\[\]]+\s+\bSET\b)",
        r"(\bDELETE\b\s+\bFROM\b)",
        r"(\b(DROP|TRUNCATE)\b\s+\b(TABLE|DATABASE|SCHEMA|INDEX|VIEW)\b)",
        r"(\b(CREATE|ALTER)\b\s+\b(TABLE|DATABASE|SCHEMA|INDEX|VIEW|USER|ROLE)\b)",
        r"(\bUNION\b\s+(\bALL\b\s+)?\bSELECT\b)",
        r"(\bEXEC\b)",
        r"(\bFETCH\b\s+\b(NEXT|FIRST|PRIOR)\b)",
        r"(\bDECLARE\b\s+@)",
        # Stacked statements: `;` immediately followed by a new statement.
        r"(;\s*\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|EXEC)\b)",
        # Comment terminators and extended-procedure prefixes.
        r"(--|\/\*|\*\/|xp_|sp_)",
        # Boolean-based injection: `OR 1=1`, `AND 1 = 1`, `' OR '`.
        r"(\b(OR|AND)\b\s+\d+\s*=\s*\d+)",
        r"('(\s)*(OR|AND)(\s)+')",
        # Time-based / destructive procedures (kept contextual: "delay",
        # "backup" and "restore" are ordinary words in a merchant's report).
        r"(\bWAITFOR\b\s+\bDELAY\b)",
        r"(\bBENCHMARK\s*\()",
        r"(\bSHUTDOWN\b)",
        r"(\b(RESTORE|BACKUP)\b\s+\b(DATABASE|TABLE|LOG|SCHEMA)\b)",
    ]

    # Patterns that might indicate XSS attempts.
    #
    # The event-handler rule names the handlers instead of matching any
    # `on...=`: `on\w+\s*=` also fires inside ordinary words once an `=` follows
    # (`connection=x`, `information=y`), which is another false positive of the
    # same kind the SQL rules above were fixed for.
    XSS_PATTERNS = [
        r"<script[^>]*>",
        r"javascript:",
        r"\bon(click|error|load|mouse\w+|error|focus|blur|submit|change|input|"
        r"key\w+|touch\w+|drag\w+|animation\w+|transition\w+)\s*=",
        r"<iframe",
        r"<object",
        r"<embed",
        r"<link",
        r"<meta",
        r"<img[^>]+onerror",
    ]
    
    def __init__(self, app):
        super().__init__(app)
        self.sql_patterns = [re.compile(p, re.IGNORECASE) for p in self.SQL_INJECTION_PATTERNS]
        self.xss_patterns = [re.compile(p, re.IGNORECASE) for p in self.XSS_PATTERNS]
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Skip safe methods
        if request.method in ("GET", "HEAD", "OPTIONS"):
            return await call_next(request)
        
        # Check query parameters
        for key, value in request.query_params.items():
            if self._contains_sql_injection(value) or self._contains_xss(value):
                logger.warning(
                    "Potential attack detected in query param '%s': %s (client=%s)",
                    key, value, request.client.host if request.client else "unknown",
                )
                return JSONResponse(
                    status_code=400,
                    content={
                        "success": False,
                        "message": "Invalid input detected",
                        "error_code": "INVALID_INPUT",
                    },
                )
        
                # Check request body for JSON content.
        #
        # Rather than regex-scanning the raw body blob (which matches substrings
        # inside base64url-encoded JWT tokens — e.g. ``refresh_token`` values —
        # producing false "SQL comment terminator" hits), parse the JSON and scan
        # each string field value individually, skipping JWT-shaped values that
        # are opaque server-generated tokens never interpreted by the SQL layer.
        content_type = request.headers.get("content-type", "")
        if "application/json" in content_type:
            try:
                body = await request.body()
                if body:
                    body_str = body.decode("utf-8")
                    try:
                        payload = json.loads(body_str)
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        # Not valid JSON — fall back to whole-body scan so we
                        # never weaken protection against malformed payloads.
                        if self._contains_sql_injection(body_str) or self._contains_xss(body_str):
                            logger.warning(
                                "Potential attack detected in request body (client=%s)",
                                request.client.host if request.client else "unknown",
                            )
                            return JSONResponse(
                                status_code=400,
                                content={
                                    "success": False,
                                    "message": "Invalid input detected",
                                    "error_code": "INVALID_INPUT",
                                },
                            )
                    else:
                        # Scan each string value, skipping JWTs.
                        for value in self._iter_string_values(payload):
                            if _looks_like_jwt(value):
                                continue
                            if self._contains_sql_injection(value) or self._contains_xss(value):
                                logger.warning(
                                    "Potential attack detected in request body (client=%s)",
                                    request.client.host if request.client else "unknown",
                                )
                                return JSONResponse(
                                    status_code=400,
                                    content={
                                        "success": False,
                                        "message": "Invalid input detected",
                                        "error_code": "INVALID_INPUT",
                                    },
                                )
            except Exception:
                pass
        
        return await call_next(request)
    
    def _contains_sql_injection(self, value: str) -> bool:
        """Check if value contains SQL injection patterns."""
        if not value:
            return False
        return any(pattern.search(value) for pattern in self.sql_patterns)

    def _contains_xss(self, value: str) -> bool:
        """Check if value contains XSS patterns."""
        if not value:
            return False
        return any(pattern.search(value) for pattern in self.xss_patterns)

    @staticmethod
    def _iter_string_values(payload: object):
        """Yield every nested string value in a parsed-JSON payload.

        Handles dicts, lists, tuples and scalars so that arbitrary nesting
        (objects inside arrays, etc.) is covered. Non-string scalars (ints,
        bools, nulls) are skipped because the rule engines only target text.
        """
        if isinstance(payload, str):
            yield payload
        elif isinstance(payload, dict):
            for v in payload.values():
                yield from InputSanitizationMiddleware._iter_string_values(v)
        elif isinstance(payload, (list, tuple)):
            for v in payload:
                yield from InputSanitizationMiddleware._iter_string_values(v)
        # ints / bools / None / floats — nothing to scan


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """Middleware to enforce request size limits."""
    
    def __init__(
        self,
        app,
        max_body_size: int = 10 * 1024 * 1024,  # 10 MB default
        max_query_params: int = 100,
        max_headers: int = 50,
    ):
        super().__init__(app)
        self.max_body_size = max_body_size
        self.max_query_params = max_query_params
        self.max_headers = max_headers
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Check query parameter count
        if len(request.query_params) > self.max_query_params:
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": f"Too many query parameters (max {self.max_query_params})",
                    "error_code": "TOO_MANY_PARAMS",
                },
            )
        
        # Check header count
        if len(request.headers) > self.max_headers:
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": f"Too many headers (max {self.max_headers})",
                    "error_code": "TOO_MANY_HEADERS",
                },
            )
        
        # Check content length
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                if int(content_length) > self.max_body_size:
                    return JSONResponse(
                        status_code=413,
                        content={
                            "success": False,
                            "message": f"Request body too large (max {self.max_body_size} bytes)",
                            "error_code": "PAYLOAD_TOO_LARGE",
                        },
                    )
            except ValueError:
                pass
        
        return await call_next(request)


class ContentTypeValidationMiddleware(BaseHTTPMiddleware):
    """Middleware to validate content types for mutating requests."""
    
    ALLOWED_CONTENT_TYPES: Set[str] = {
        "application/json",
        "application/x-www-form-urlencoded",
        "multipart/form-data",
    }
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Only check mutating methods
        if request.method in ("POST", "PUT", "PATCH"):
            content_type = request.headers.get("content-type", "").split(";")[0].strip()
            
            # Allow empty content-type for requests without body
            content_length = request.headers.get("content-length", "0")
            if content_length == "0" or not content_type:
                return await call_next(request)
            
            if content_type and content_type not in self.ALLOWED_CONTENT_TYPES:
                return JSONResponse(
                    status_code=415,
                    content={
                        "success": False,
                        "message": f"Unsupported content type: {content_type}",
                        "error_code": "UNSUPPORTED_MEDIA_TYPE",
                    },
                )
        
        return await call_next(request)


def sanitize_input(value: str) -> str:
    """Sanitize a string input by removing potentially dangerous characters.
    
    Use this for user-provided strings that will be displayed back.
    """
    if not value:
        return value
    
    # Remove null bytes
    value = value.replace("\x00", "")
    
    # Remove control characters except newlines and tabs
    value = "".join(
        char for char in value
        if char == "\n" or char == "\r" or char == "\t" or (ord(char) >= 32)
    )
    
    # Strip leading/trailing whitespace
    value = value.strip()
    
    return value


def escape_html(value: str) -> str:
    """Escape HTML special characters to prevent XSS."""
    if not value:
        return value
    
    html_escape_table = {
        "&": "&amp;",
        '"': "&quot;",
        "'": "&#x27;",
        ">": "&gt;",
        "<": "&lt;",
        "/": "&#x2F;",
    }
    
    return "".join(html_escape_table.get(c, c) for c in value)


def validate_order_by(value: str, allowed_fields: Set[str]) -> Optional[str]:
    """Validate and sanitize an ORDER BY clause.
    
    Args:
        value: The order_by value (e.g., "name", "-created_at")
        allowed_fields: Set of allowed field names
    
    Returns:
        Sanitized order_by value or None if invalid
    """
    if not value:
        return None
    
    # Remove leading minus for descending order
    field = value.lstrip("-")
    
    if field not in allowed_fields:
        return None
    
    return value