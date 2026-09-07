"""India pincode -> city / state lookup (fully dynamic / live).

No static dataset. Every lookup queries live services:
  1. PostPin API (primary) — https://api.postalpincode.in/pincode/{pincode}
  2. Google Maps Geocoding (fallback) — when PostPin has no match and
     GOOGLE_MAPS_API_KEY is configured.
"""
from __future__ import annotations

import os
from typing import Any

import httpx

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.services.pincode")


class PincodeInfo:
    __slots__ = ("pincode", "city", "state")

    def __init__(self, pincode: str, city: str, state: str):
        self.pincode = pincode
        self.city = city
        self.state = state


_POSTPIN_URL = "https://api.postalpincode.in/pincode/{pincode}"
_GOOGLE_GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"
_GOOGLE_API_KEY = getattr(settings, "GOOGLE_MAPS_API_KEY", None) or os.getenv("GOOGLE_MAPS_API_KEY")


def _lookup_postpin(pincode: str) -> PincodeInfo | None:
    try:
        resp = httpx.get(_POSTPIN_URL.format(pincode=pincode), timeout=5.0)
        if resp.status_code != 200:
            return None
        body = resp.json()
        office_list = (
            body[0].get("PostOffice") if isinstance(body, list) and body else None
        )
        if not office_list:
            return None
        office = office_list[0]
        state = (office.get("State") or "").strip()
        city = (office.get("Name") or office.get("Region") or office.get("District") or "").strip()
        if state and city:
            return PincodeInfo(pincode=pincode, city=city, state=state)
        return None
    except Exception as exc:
        logger.warning("PostPin lookup failed for %s: %s", pincode, exc)
        return None


def _lookup_google(pincode: str) -> PincodeInfo | None:
    if not _GOOGLE_API_KEY:
        return None
    try:
        resp = httpx.get(
            _GOOGLE_GEOCODE_URL,
            params={"address": f"{pincode}+India", "key": _GOOGLE_API_KEY},
            timeout=5.0,
        )
        if resp.status_code != 200:
            return None
        results = resp.json().get("results") or []
        if not results:
            return None
        address_components = results[0].get("address_components") or []
        city = state = ""
        for comp in address_components:
            types = comp.get("types") or []
            if "locality" in types and not city:
                city = comp.get("long_name", "")
            elif "administrative_area_level_2" in types and not city:
                city = comp.get("long_name", "")
            elif "administrative_area_level_1" in types and not state:
                state = comp.get("long_name", "")
        if state and city:
            return PincodeInfo(pincode=pincode, city=city, state=state)
        return None
    except Exception as exc:
        logger.warning("Google Maps lookup failed for %s: %s", pincode, exc)
        return None


def lookup(pincode: str) -> PincodeInfo | None:
    """Resolve a 6-digit Indian pincode to city + state (live)."""
    clean = (pincode or "").strip()
    if not clean.isdigit() or len(clean) != 6:
        return None
    # 1. PostPin (primary)
    result = _lookup_postpin(clean)
    if result:
        return result
    # 2. Google Maps (fallback)
    return _lookup_google(clean)
