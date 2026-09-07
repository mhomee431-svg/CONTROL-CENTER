"""Geo helpers: haversine distance and shop coordinate resolution from PostGIS."""

from __future__ import annotations

import math
import struct
from typing import Any, Optional, Tuple


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate the great-circle distance between two points in kilometers."""
    R = 6371.0  # Earth radius in km
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)

    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def _parse_wkb_point(data: bytes) -> Optional[Tuple[float, float]]:
    """Parse a WKB/EWKB POINT payload into (longitude, latitude), honoring endianness.

    Handles both plain WKB and the EWKB form GeoAlchemy2 emits (SRID
    prepended right after the geometry type when the 0x20000000 flag bit
    is set) — e.g. ``0101000020E6100000...``.
    """
    if not data or len(data) < 5:
        return None
    try:
        byte_order = data[0]
        if byte_order not in (0, 1):
            return None
        endian = "<" if byte_order == 1 else ">"
        (geom_type,) = struct.unpack(endian + "I", data[1:5])
        offset = 5
        # EWKB carries an SRID (4 bytes) right after the type when the high
        # bit (0x20000000) is set.
        if geom_type & 0x20000000:
            offset += 4
        geom_type &= 0x0FFFFFFF
        if geom_type != 1:  # POINT
            return None
        if len(data) < offset + 16:
            return None
        (x,) = struct.unpack(endian + "d", data[offset:offset + 8])
        (y,) = struct.unpack(endian + "d", data[offset + 8:offset + 16])
        return x, y
    except (struct.error, ValueError, TypeError, IndexError):
        return None


def resolve_shop_coordinates(shop: Any) -> Tuple[Optional[float], Optional[float]]:
    """Return ``(longitude, latitude)`` for a shop, resolving from:

    1. The PostGIS ``location`` Geography POINT column — either WKT
       (``'POINT(lon lat)'``) or the WKB/EWKB hex blob GeoAlchemy2
       returns (``str(WKBElement)`` -> ``0101000020E6100000...``).
    2. The scalar ``latitude`` / ``longitude`` template columns (fallback).

    Returns ``(None, None)`` when no usable coordinate source exists. This
    centralizes coordinate access so every nearby/feed/map endpoint behaves
    identically regardless of how shop coordinates were stored.
    """
    location = getattr(shop, "location", None)
    if location is not None:
        parsed = None
        raw = None
        # GeoAlchemy2 WKBElement / blobs — duck-typed to avoid an import.
        # A freshly-constructed (not yet persisted) WKTElement exposes its WKT
        # through ``data`` as a str, which must NOT be fed to bytes().
        data_attr = getattr(location, "data", None)
        if isinstance(data_attr, (bytes, bytearray, memoryview)):
            raw = bytes(data_attr)
        elif isinstance(location, (bytes, bytearray)):
            raw = bytes(location)
        else:
            try:
                s = str(location).strip()
            except Exception:  # noqa: BLE001 — never crash on a bad geom
                s = None
            if s:
                if s.upper().startswith("POINT"):
                    try:
                        inner = (
                            s[6:-1].strip()
                            if s.endswith(")")
                            else s[5:].strip().rstrip(")")
                        )
                        parts = inner.split()
                        if len(parts) == 2:
                            parsed = float(parts[0]), float(parts[1])
                    except (ValueError, TypeError, IndexError):
                        parsed = None
                elif len(s) > 8:
                    # Hex EWKB/WKB such as '0101000020E6100000...'
                    try:
                        raw = bytes.fromhex(s.replace(" ", ""))
                    except (ValueError, TypeError):
                        raw = None
        if parsed is not None:
            return parsed
        if raw:
            parsed = _parse_wkb_point(raw)
            if parsed is not None:
                return parsed

    # Fallback: scalar latitude/longitude template columns. Mocks and partial
    # ORM objects may lack the attributes, hence getattr(...) defaults.
    latitude = getattr(shop, "latitude", None)
    longitude = getattr(shop, "longitude", None)
    if latitude is not None and longitude is not None:
        try:
            return float(longitude), float(latitude)
        except (ValueError, TypeError):
            return None, None
    return None, None