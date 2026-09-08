# High-Precision Geospatial Location Engine

Zomato-grade location services across FastAPI (PostGIS + Redis + Google Maps
APIs) and both Flutter apps (`customer_app`, `shopkeeper_app`).

## 1. Architecture

```
Flutter Customer/Shopkeeper App
        │  GPS fix (LocationAccuracy.high / bestForNavigation)
        │  Map pin drop (300ms debounce) + Places autocomplete (session token)
        ▼
FastAPI /api/v1/location/*
        │  ┌ reverse-geocode   → Google Geocoding API  (Redis 30d TTL)
        │  ├ nearby-shops      → PostGIS ST_DWithin    (Redis 5min TTL)
        │  ├ route-eta         → Directions API        (Redis 2min TTL)
        │  ├ route-eta-batch   → Distance Matrix API   (Redis 2min TTL)
        │  └ autocomplete      → Places API (session tokens)
        ▼
PostgreSQL (PostGIS, GEOGRAPHY(POINT,4326) + GIST index)  ·  Redis cache
```

## 2. Backend Endpoints (`POST /api/v1/location/*`)

### 2.1 `POST /location/reverse-geocode`
Convert lat/lng into a structured address payload (House No, Street, Area,
City, State, Pincode).

```json
{ "latitude": 25.5941, "longitude": 85.1376 }
```
```json
{
  "success": true,
  "data": {
    "latitude": 25.5941,
    "longitude": 85.1376,
    "formatted_address": "Patna, Bihar, India",
    "address": {
      "house_number": null,
      "street": "Main Road",
      "landmark": null,
      "area": "Patna",
      "city": "Patna",
      "state": "Bihar",
      "pincode": "800001",
      "country": "India"
    },
    "place_id": "ChIJ..."
  }
}
```
- Coordinates rounded to 7 decimals (~1.1 cm) for cache keys.
- Cached in Redis (`geospatial:geocode:lat:lng`) for 30 days.
- Returns `404 REVERSE_GEOCODE_FAILED` when `GOOGLE_MAPS_API_KEY` is
  missing or the API returns no result.

### 2.2 `POST /location/nearby-shops`
Radius-based shop discovery using PostGIS `ST_DWithin` on the
`GEOGRAPHY(POINT, 4326)` column; distance returned in meters.

```json
{
  "latitude": 25.5941,
  "longitude": 85.1376,
  "radius_meters": 5000,
  "limit": 50
}
```
```json
{
  "success": true,
  "data": {
    "user_latitude": 25.5941,
    "user_longitude": 85.1376,
    "radius_meters": 5000,
    "total": 3,
    "shops": [
      {
        "shop_id": 1,
        "shop_name": "Bihar General Store",
        "slug": "bihar-general-store",
### 2.3 `POST /location/route-eta`
Real-time route distance + ETA via Google Directions API (live traffic).

```json
{
  "origin_latitude": 25.5941,
  "origin_longitude": 85.1376,
  "dest_latitude": 25.6041,
  "dest_longitude": 85.1476,
  "mode": "driving"
}
```
```json
{
  "success": true,
  "data": {
    "distance_meters": 2400,
    "distance_text": "2.4 km",
    "duration_seconds": 480,
    "duration_text": "8 mins",
    "polyline": "encoded_polyline",
    "start_address": "Patna, Bihar",
    "end_address": "Patna City, Bihar",
    "steps": [ { "distance": "0.5 km", "duration": "2 mins", "instruction": "Head northeast", "mode": "driving" } ],
    "source": "google_directions"
  }
}
```
- Falls back to a haversine straight-line estimate (`source: haversine_estimate`,
  ~50 km/h average) when the Maps API is unavailable - NEVER fails the request.
- Cached 2 minutes (traffic-sensitive).

### 2.4 `POST /location/route-eta-batch`
One origin -> many destinations (delivery-boy route optimization) via the
Distance Matrix API.

```json
{
  "origin": { "latitude": 25.5941, "longitude": 85.1376 },
  "destinations": [
    { "latitude": 25.60, "longitude": 85.15 },
    { "latitude": 25.62, "longitude": 85.18 }
  ],
  "mode": "driving"
}
```

### 2.5 `POST /location/autocomplete`
Google Places Autocomplete with **session tokens** (billing optimization:
autocomplete + details share one token = one session).

```json
{ "query": "patna", "session_token": "tok-abc", "latitude": 25.59, "longitude": 85.13 }
```
Server generates a token when omitted and echoes it so the client can reuse
it in the subsequent `/location/place/resolve` call.

### 2.6 `POST /location/place/resolve`
Resolve a `place_id` (from autocomplete) to lat/lng, closing the session.

### 2.7 `GET /location/health`
Lightweight service probe (no external calls).

## 3. Database / Migration (0020)

- `CREATE EXTENSION IF NOT EXISTS postgis`
- `idx_shops_location_gist` - GIST spatial index on `shops.location`
  (`GEOGRAPHY(POINT,4326)`), powers fast `ST_DWithin` radius queries.
- `idx_shops_geo_filter` - composite btree on
  `(status, is_verified, is_accepting_orders, is_deleted)` for the
  discovery WHERE clause.

## 4. Redis Caching

| Domain `geospatial:` | Key pattern | TTL |
|---|---|---|
| `geocode:{lat7}:{lng7}` | reverse geocode results | 30 days |
| `nearby:{lat5}:{lng5}:{radius}:{limit}` | nearby shop lists | 5 min |
| `route:{o_lat5}:{o_lng5}:{d_lat5}:{d_lng5}:{mode}` | route/ETA | 2 min |

All cache reads degrade gracefully to the underlying source when Redis is
down (the shared `app.core.cache` circuit-breaker handles this).
        "rating": 4.2,
        "review_count": 128,
        "is_accepting_orders": true,
        "is_verified": true,
        "latitude": 25.595,
## 5. Flutter Integration

### Customer app (`apps/customer_app`)
- `device_location_repository.dart` - GPS via `Geolocator.getCurrentPosition`
  with `LocationAccuracy.high`, 15s time limit.
- `map_picker_controller.dart` - pin-drop flow with a **300ms debounce**
  (`_geocodeDebounceDuration`) before reverse geocoding; request sequencing
  prevents out-of-order responses.
- `map_picker_screen.dart` - full-screen `GoogleMap`, draggable center pin,
  route polyline, ETA chips.
- `location_api_service.dart` - typed DTO client (`NearbyShopDto`,
  `ReverseGeocodeDto`, `AutocompleteSuggestionDto`, `DirectionsDto` +
  `LocationApiService`) for `/api/v1/locations/*`.

### Shopkeeper app (`apps/shopkeeper_app`)
- `location_accuracy_config.dart` - single source of truth:
  `LocationAccuracy.bestForNavigation`, target <=10 m, discard >50 m.
- `location_service.dart` - two-phase acquisition (single fix then stream),
  best-reading selection, permission pre-flight.
- `place_autocomplete_service.dart` - Places Autocomplete + Details with
  **session-token** support (`search(query, sessionToken:)`,
  `getPlaceDetails(placeId, sessionToken:)`).

## 6. Environment

```bash
# backend/.env
GOOGLE_MAPS_API_KEY=<server-restricted key>
GOOGLE_APPLICATION_CREDENTIALS=<abs path to config/gcp-key.json>
GCP_PROJECT_ID=hyperlocal--discovery
REDIS_URL=redis://localhost:6379/0
DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/dbname
```

## 7. Tests

`backend/tests/test_geospatial_location_engine.py`:
- validation (invalid coords -> 400/422)
- graceful degradation when API key unset (404 / haversine estimate)
- reverse-geocode result mapping (mocked Google response)
- session-token preservation, place-resolution failure
- 7-decimal precision formatting, haversine reference distance

Run: `cd backend && python -m pytest tests/test_geospatial_location_engine.py -v`
        "longitude": 85.138,
        "distance_meters": 142.7,
        "distance_km": 0.14
      }
    ]
  }
}
```
- Only `status IN (ACTIVE, VERIFIED)`, verified, order-accepting, non-deleted
  shops with coordinates are returned.
- Uses the GIST spatial index (`idx_shops_location_gist`, migration 0020).
- Cached 5 minutes; falls back to an in-app haversine scan when PostGIS is
  unavailable (still correct, slower).