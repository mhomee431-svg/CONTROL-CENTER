# Location API Documentation

## Overview

The Location API provides geocoding, address autocomplete, route optimization, and shop discovery services using Google Maps APIs and PostGIS spatial queries.

## Google Maps APIs Used

| API | Purpose | Endpoint |
|-----|---------|----------|
| Geocoding API | Reverse geocoding (lat/lng → address) | `GET /api/v1/locations/reverse-geocode` |
| Places API | Address autocomplete suggestions | `GET /api/v1/locations/autocomplete` |
| Places API Details | Resolve place_id to coordinates | `GET /api/v1/locations/place-coordinates` |
| Directions API | Route polyline + ETA | `GET /api/v1/locations/directions` |
| Distance Matrix API | Multi-point distance/ETA | `GET /api/v1/locations/distance-matrix` |

## API Endpoints

### 1. Reverse Geocode
`GET /api/v1/locations/reverse-geocode?latitude=25.5941&longitude=85.1376`

Converts lat/lng coordinates into a structured address payload.

**Response:**
```json
{
  "success": true,
  "data": {
    "formatted_address": "Patna, Bihar, India",
    "street_number": null,
    "route": "Main Road",
    "locality": "Patna",
    "district": "Patna",
    "state": "Bihar",
    "pincode": "800001",
    "country": "India",
    "latitude": 25.5941,
    "longitude": 85.1376,
    "place_id": "ChIJ..."
  }
}
```

### 2. Address Autocomplete
`GET /api/v1/locations/autocomplete?q=patna&latitude=25.59&longitude=85.13&radius=50000`

Returns Places API address suggestions. Optionally biased toward a location.

**Response:**
```json
{
  "success": true,
  "data": {
    "query": "patna",
    "suggestions": [
      {
        "place_id": "ChIJ...",
        "main_text": "Patna",
        "secondary_text": "Bihar, India",
        "types": ["locality", "political"]
      }
    ]
  }
}
```

### 3. Directions (Route + ETA)
`GET /api/v1/locations/directions?origin_lat=25.59&origin_lng=85.13&dest_lat=25.60&dest_lng=85.15&mode=driving`

Computes route polyline, distance, and ETA with live traffic.

**Response:**
```json
{
  "success": true,
  "data": {
    "distance_meters": 2400,
    "distance_text": "2.4 km",
    "duration_seconds": 480,
    "duration_text": "8 mins",
    "polyline": "encoded_polyline_string",
    "start_address": "Patna, Bihar",
    "end_address": "Patna City, Bihar",
    "steps": [...]
  }
}
```

### 4. Distance Matrix
`GET /api/v1/locations/distance-matrix?origins=25.59,85.13;25.60,85.15&destinations=25.61,85.16&mode=driving`

Computes distance/duration for multiple origin-destination pairs.

**Response:**
```json
{
  "success": true,
  "data": {
    "origins": ["Patna, Bihar"],
    "destinations": ["Patna City, Bihar"],
    "rows": [[{
      "origin_address": "Patna, Bihar",
      "destination_address": "Patna City, Bihar",
      "distance_meters": 2400,
      "distance_text": "2.4 km",
      "duration_seconds": 480,
      "duration_text": "8 mins"
    }]]
  }
}
```

### 5. Nearby Shops
`GET /api/v1/locations/nearby?latitude=25.59&longitude=85.13&radius_km=5&include_eta=true`

Returns active shops within radius. Optionally includes live ETA.

### 6. Place Coordinates
`GET /api/v1/locations/place-coordinates?place_id=ChIJ...`

Resolves a Places API place_id to lat/lng.

### 7. Pincode Lookup
`GET /api/v1/locations/pincode/800001`

Resolves Indian pincode to city + state (PostPin API primary, Google Geocoding fallback).

## Environment Configuration

### Required
```bash
# backend/.env
GCP_PROJECT_ID=hyperlocal--discovery
GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/config/gcp-key.json
GOOGLE_MAPS_API_KEY=your_google_maps_api_key
```

### Security Notes
- `config/gcp-key.json` is gitignored — NEVER commit service account keys
- `GOOGLE_MAPS_API_KEY` should be restricted to specific APIs in GCP Console
- The service account key provided in previous chat history is COMPROMISED and must be rotated
- Generate a new key at: https://console.cloud.google.com/iam-admin/serviceaccounts

## Enabling Google Maps APIs

In GCP Console, enable these APIs for your project:
1. Geocoding API
2. Places API (New)
3. Directions API
4. Distance Matrix API

## GCP Service Account Setup

1. Go to https://console.cloud.google.com/iam-admin/serviceaccounts
2. Create a service account with "Maps API User" role
3. Generate a JSON key
4. Save to `config/gcp-key.json` (gitignored)
5. Set `GOOGLE_APPLICATION_CREDENTIALS` in `.env` to the absolute path

## Architecture

```
Flutter Apps → FastAPI Backend → Google Maps APIs
                    ↓
              PostGIS (shop coordinates)
                    ↓
              Redis (caching layer)
```

The backend location service (`app/services/location_service.py`) handles all Google Maps API calls, while shop discovery uses PostGIS for spatial queries and haversine distance for filtering.
