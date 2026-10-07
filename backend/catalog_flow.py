"""Ad-hoc end-to-end check for the product catalog surfaces.

Not part of the app: exercises the real routes through TestClient so the
product table filters, bulk moderation, listing reviews, quality findings and
the high-risk merge workflow are proven against a running app.
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


# --- Product table: list + filters -----------------------------------------
listed = ok(client.get("/api/v1/admin/products", headers=H))
assert "items" in listed and "total" in listed, listed
assert listed["total"] >= 1, listed
print("product list ok, total:", listed["total"])

pending = ok(client.get("/api/v1/admin/products", params={"status": "PENDING"}, headers=H))
assert all(r["status"] == "PENDING" for r in pending["items"]), pending
print("status filter ok")

# --- Detail + variants + identifiers ---------------------------------------
first_id = listed["items"][0]["id"]
detail = ok(client.get(f"/api/v1/admin/products/{first_id}", headers=H))
assert detail["id"] == first_id, detail
variants = ok(client.get(f"/api/v1/admin/products/{first_id}/variants", headers=H))
assert "items" in variants, variants
identifiers = ok(client.get("/api/v1/admin/identifiers", headers=H))
assert "items" in identifiers, identifiers
print("detail/variants/identifiers ok")

# --- Bulk moderation requires a reason -------------------------------------
noreason = client.post(
    "/api/v1/admin/products/bulk",
    json={"action": "APPROVE", "product_ids": [first_id]},
    headers=H,
)
assert noreason.status_code == 422, noreason.text
bulk = ok(
    client.post(
        "/api/v1/admin/products/bulk",
        json={"action": "APPROVE", "product_ids": [first_id], "reason": "Catalog audit pass"},
        headers=H,
    )
)
assert bulk["updated"] == 1 and bulk["status"] == "APPROVED", bulk
print("bulk moderation ok")

# --- Approvals queue + listing review --------------------------------------
approvals = ok(client.get("/api/v1/admin/products/approvals", headers=H))
assert "items" in approvals, approvals
if approvals["items"]:
    lid = approvals["items"][0]["id"]
    reviewed = ok(
        client.post(
            f"/api/v1/admin/products/listings/{lid}/review",
            json={"decision": "APPROVE", "reason": "Barcode and images check out"},
            headers=H,
        )
    )
    assert reviewed["status"] == "APPROVED", reviewed
    print("listing review ok, id:", lid)
else:
    print("approvals queue empty — review step skipped")

# --- Quality findings ------------------------------------------------------
quality = ok(client.get("/api/v1/admin/products/quality", headers=H))
assert "items" in quality and "total" in quality, quality
filtered = ok(client.get("/api/v1/admin/products/quality", params={"check": "missing-images"}, headers=H))
assert all(f["check"] == "missing-images" for f in filtered["items"]), filtered
print("quality findings ok, total:", quality["total"])

# --- Merge: compare then confirm -------------------------------------------
second_id = listed["items"][1]["id"] if listed["total"] > 1 else first_id
if second_id == first_id:
    print("single-product catalog — merge compare skipped")
else:
    cmp = ok(
        client.post(
            "/api/v1/admin/products/merge/compare",
            json={"product_a_id": first_id, "product_b_id": second_id},
            headers=H,
        )
    )
    assert "candidate_a" in cmp and "candidate_b" in cmp, cmp
    noreason_merge = client.post(
        "/api/v1/admin/products/merge/confirm",
        json={"winner_id": first_id, "loser_id": second_id},
        headers=H,
    )
    assert noreason_merge.status_code == 422, noreason_merge.text
    merged = ok(
        client.post(
            "/api/v1/admin/products/merge/confirm",
            json={"winner_id": first_id, "loser_id": second_id, "reason": "Same pack, duplicate master rows"},
            headers=H,
        )
    )
    assert merged["winner"]["id"] == first_id and merged["loser_id"] == second_id, merged
    print("merge compare + confirm ok")

print("ALL CATALOG CHECKS PASSED")
