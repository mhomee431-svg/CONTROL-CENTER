# Removed in the Firebase-auth refactor: shopkeeper_google_auth.py (OAuth code
# flow) was deleted — authentication is Firebase Google Sign-In, verified via
# the Firebase Admin SDK in:
#   backend/app/api/routes/shopkeeper_auth.py  (POST /firebase-login)
#   backend/app/services/firebase_verification.py
# API routes package