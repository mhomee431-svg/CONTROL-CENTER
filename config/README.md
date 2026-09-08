# GCP Service Account Configuration

## IMPORTANT SECURITY NOTICE

**The GCP service account key previously shared in this project's chat history is COMPROMISED.**
It MUST be rotated immediately and NEVER stored in any file.

## Setup Instructions

1. Go to [GCP IAM Admin - Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Select the `hyperlocal--discovery` project
3. Find the `cline-dev-agent` service account (or create a new one)
4. Click "Keys" → "Add Key" → "Create new key" → JSON
5. Download the key file
6. Save it as `config/gcp-key.json` in this directory
7. The file is automatically excluded from git via `.gitignore`

## File Structure

```
config/
  README.md       # This file
  gcp-key.json    # Gitignored - your service account key
```

## Required GCP APIs

Enable these in [GCP Console → APIs & Services](https://console.cloud.google.com/apis):
- Geocoding API
- Places API (New)
- Directions API
- Distance Matrix API

## API Key Restrictions

Restrict `GOOGLE_MAPS_API_KEY` to:
- The APIs listed above
- Your app's bundle ID (for mobile) or IP/Referer (for server)

## Rotating a Compromised Key

If a key has been exposed (e.g., in chat history, logs, or accidentally committed):

1. Go to GCP Console → IAM → Service Accounts
2. Select the compromised service account
3. Go to "Keys" tab
4. Delete the exposed key
5. Create a new key
6. Update `config/gcp-key.json` with the new key
7. If the key was ever committed to git, consider the entire history compromised and rewrite it
