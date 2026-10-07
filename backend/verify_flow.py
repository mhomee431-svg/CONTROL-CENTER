"""Ad-hoc end-to-end check for the verification surfaces.

Not part of the app: exercises the real routes through TestClient so the queue
filters, the decision mapping, the reviewer assignment and the decision history
are proven against a running app rather than by reading the source.
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# --- Sign in ---------------------------------------------------------------
login = client.post("/api/v1/admin/auth/login", json={"username": "admin", "password": "admin123"})
assert login.status_code == 200, login.text
token = login.json()["data"]["access_token"]
H = {"Authorization": f"Bearer {token}"}


def ok(resp):
    assert resp.status_code == 200, f"{resp.status_code}: {resp.text}"
    body = resp.json()
    assert body["success"] is True, body
    return body["data"]


# --- Queue: each stage tab returns a list ----------------------------------
for stage in ["PENDING", "UNDER_REVIEW", "VERIFIED", "REJECTED", "NEEDS_CORRECTION"]:
    data = ok(client.get("/api/v1/admin/shops", params={"verification_status": stage}, headers=H))
    assert "items" in data and "total" in data, data
print("queue stages ok")

# --- Queue: every filter the UI sends is accepted --------------------------
filtered = ok(
    client.get(
        "/api/v1/admin/shops",
        params={
            "verification_status": "PENDING",
            "category": "Electronics",
            "city": "Mumbai",
            "status": "PENDING",
            "reviewer": "Platform Owner",
            "created_from": "2020-01-01",
            "created_to": "2999-12-31",
            "search": "gupta",
            "limit": 10,
            "offset": 0,
        },
        headers=H,
    )
)
print("filters ok, rows:", filtered["total"])

# --- Summary counts --------------------------------------------------------
summary = ok(client.get("/api/v1/admin/shops/verification/summary", headers=H))
assert "counts" in summary and "total" in summary["counts"], summary
print("summary ok:", summary["counts"])

# --- Decisions: unknown verb is rejected -----------------------------------
bad = client.post("/api/v1/admin/shops/3/verification", json={"decision": "NOPE"}, headers=H)
assert bad.status_code == 422, bad.text
print("unknown decision rejected ok")

# --- Decisions: reject without a reason is refused -------------------------
noreason = client.post("/api/v1/admin/shops/3/verification", json={"decision": "REJECT"}, headers=H)
assert noreason.status_code == 422, noreason.text
print("reason enforcement ok")

# --- Decisions: request correction maps to NEEDS_CORRECTION ---------------
corr = ok(
    client.post(
        "/api/v1/admin/shops/3/verification",
        json={"decision": "REQUEST_CORRECTION", "reason": "Blurred GST certificate"},
        headers=H,
    )
)
assert corr["verification_status"] == "NEEDS_CORRECTION", corr
print("request correction ok")

# --- Decisions: hold maps to UNDER_REVIEW ----------------------------------
hold = ok(
    client.post(
        "/api/v1/admin/shops/3/verification",
        json={"decision": "ON_HOLD", "reason": "Waiting on field visit"},
        headers=H,
    )
)
assert hold["verification_status"] == "UNDER_REVIEW", hold
print("hold ok")

# --- Decisions: hold is logged as its own action ---------------------------
hist_hold = ok(client.get("/api/v1/admin/shops/3/verification/history", headers=H))
assert any(i["action"] == "shop.verification.hold" for i in hist_hold["items"]), hist_hold
print("hold audit action ok")

# --- Decisions: approve activates and clears the rejection reason ----------
appr = ok(
    client.post(
        "/api/v1/admin/shops/3/verification",
        json={"decision": "VERIFY", "reason": "Documents and visit check out"},
        headers=H,
    )
)
assert appr["verification_status"] == "VERIFIED", appr
assert appr["status"] == "ACTIVE", appr
assert appr["rejection_reason"] is None, appr
print("approve ok")

# --- Assignment ------------------------------------------------------------
assigned = ok(
    client.post(
        "/api/v1/admin/shops/1/verification/assign",
        json={"reviewer": "Support Admin", "reason": "Routing to field team"},
        headers=H,
    )
)
assert assigned["verified_by"] == "Support Admin", assigned
released = ok(
    client.post(
        "/api/v1/admin/shops/1/verification/assign",
        json={"reviewer": None, "reason": "Back to the shared queue"},
        headers=H,
    )
)
assert released["verified_by"] is None, released
print("assignment ok")

# --- Decision history ------------------------------------------------------
hist = ok(client.get("/api/v1/admin/shops/3/verification/history", headers=H))
assert hist["total"] >= 3, hist
assert all(i["action"].startswith("shop.verification.") for i in hist["items"]), hist["items"][:1]
print("history ok, entries:", hist["total"])

print("ALL VERIFICATION CHECKS PASSED")
