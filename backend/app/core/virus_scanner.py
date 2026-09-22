"""Virus scanning hooks for file uploads.

Provides:
- ClamAV integration hook
- External scanner API hooks
- Scan result caching
- Quarantine support

Note: Actual virus scanning requires ClamAV or an external service.
This module provides the hooks and can be enabled when a scanner is available.
"""
import logging
import hashlib
from datetime import datetime, timezone

from app.core.config import settings

logger = logging.getLogger("app.core.virus_scanner")


class ScanResult:
    """Result of a virus scan."""
    
    def __init__(
        self,
        is_clean: bool,
        scanner: str = "none",
        threats: list[str] | None = None,
        scan_time: datetime | None = None,
        error: str | None = None,
    ):
        self.is_clean = is_clean
        self.scanner = scanner
        self.threats = threats or []
        self.scan_time = scan_time or datetime.now(timezone.utc)
        self.error = error
    
    @property
    def is_infected(self) -> bool:
        """Check if file is infected."""
        return not self.is_clean and len(self.threats) > 0
    
    @property
    def status(self) -> str:
        """Get scan status string."""
        if self.error:
            return "error"
        if self.is_clean:
            return "clean"
        return "infected"
    
    def to_dict(self) -> dict:
        """Convert to dictionary."""
        return {
            "is_clean": self.is_clean,
            "scanner": self.scanner,
            "threats": self.threats,
            "scan_time": self.scan_time.isoformat(),
            "status": self.status,
            "error": self.error,
        }


def compute_file_hash(content: bytes) -> str:
    """Compute SHA-256 hash of file content for caching/dedup."""
    return hashlib.sha256(content).hexdigest()


def scan_file(content: bytes, filename: str | None = None) -> ScanResult:
    """Scan a file for viruses.
    
    If no scanner is configured, returns a "clean" result (assumes safe).
    When ClamAV or external scanner is configured, performs actual scanning.
    """
    if not getattr(settings, "VIRUS_SCAN_ENABLED", False):
        logger.debug("Virus scanning disabled, skipping scan for %s", filename)
        return ScanResult(is_clean=True, scanner="none")
    
    # Try ClamAV
    result = _scan_with_clamav(content, filename)
    if result is not None:
        return result
    
    # Try external scanner API
    result = _scan_with_external(content, filename)
    if result is not None:
        return result
    
    logger.warning("No virus scanner available, file assumed clean: %s", filename)
    return ScanResult(is_clean=True, scanner="none")


def _scan_with_clamav(content: bytes, filename: str | None) -> ScanResult | None:
    """Scan file using ClamAV daemon."""
    try:
        import clamd
        
        cd = clamd.ClamdUnixSocket()
        result = cd.scan_stream(content)
        
        if result is None:
            return ScanResult(is_clean=True, scanner="clamav")
        
        for stream, (status, threat) in result.items():
            if status == "FOUND":
                logger.warning("Virus detected by ClamAV: %s in file %s", threat, filename)
                return ScanResult(is_clean=False, scanner="clamav", threats=[threat])
        
        return ScanResult(is_clean=True, scanner="clamav")
        
    except ImportError:
        logger.debug("clamd not installed, skipping ClamAV scan")
        return None
    except Exception as exc:
        logger.error("ClamAV scan failed: %s", exc)
        return ScanResult(is_clean=True, scanner="clamav", error=str(exc))


def _scan_with_external(content: bytes, filename: str | None) -> ScanResult | None:
    """Scan a file through a configured external scanner API.

    Disabled unless ``VIRUS_SCAN_API_URL`` is configured: with no endpoint this
    returns ``None`` so the caller logs "no scanner available" and the file is
    treated as clean — the same fail-open behaviour a missing ClamAV daemon
    gets.

    Endpoint contract: POST the raw bytes (``application/octet-stream``) with
    the original name in ``X-Filename`` (and ``Authorization: Bearer ...`` when
    ``VIRUS_SCAN_API_KEY`` is set), answering ``{"clean": bool,
    "threats": ["name", ...]}``. A non-200 answer or an unreadable body is
    reported as an error result that still fails OPEN, so an unreachable
    scanner can never block uploads.
    """
    api_url = getattr(settings, "VIRUS_SCAN_API_URL", None)
    if not api_url:
        logger.debug("No external scanner configured, skipping external scan")
        return None

    try:
        import httpx

        headers = {"Content-Type": "application/octet-stream"}
        if filename:
            headers["X-Filename"] = filename
        api_key = getattr(settings, "VIRUS_SCAN_API_KEY", None)
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        resp = httpx.post(
            api_url,
            content=content,
            headers=headers,
            timeout=float(getattr(settings, "VIRUS_SCAN_TIMEOUT_SECONDS", 30.0)),
        )
        if resp.status_code != 200:
            logger.error("External scanner returned HTTP %s", resp.status_code)
            return ScanResult(
                is_clean=True,
                scanner="external",
                error=f"scanner HTTP {resp.status_code}",
            )

        payload = resp.json()
        raw_threats = payload.get("threats") or []
        threats = [str(item) for item in raw_threats]
        is_clean = bool(payload.get("clean", not threats))
        if not is_clean:
            logger.warning(
                "Virus detected by external scanner: %s in file %s", threats, filename
            )
        return ScanResult(is_clean=is_clean, scanner="external", threats=threats)

    except ImportError:
        logger.debug("httpx not installed, skipping external scan")
        return None
    except Exception as exc:
        logger.error("External scan failed: %s", exc)
        return ScanResult(is_clean=True, scanner="external", error=str(exc))


def should_scan_file(content_type: str) -> bool:
    """Determine if a file type should be scanned."""
    scan_types = {
        "application/x-executable",
        "application/x-dosexec",
        "application/x-msdownload",
        "application/x-sh",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/zip",
        "application/x-rar-compressed",
        "application/gzip",
        "text/javascript",
        "application/javascript",
    }
    return content_type in scan_types