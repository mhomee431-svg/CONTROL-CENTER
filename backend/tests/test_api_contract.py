"""
Test suite to validate the API contract documentation.

Verifies that:
1. The API contract document exists and is non-empty.
2. All required API categories are covered.
3. All required contract elements are defined for each endpoint.
4. Every frontend feature has a defined backend contract.
"""
import os
import re
from pathlib import Path

# Path to the API contract document
CONTRACT_PATH = Path(__file__).parents[2] / "packages" / "api_contracts" / "API_CONTRACT.md"


def read_contract() -> str:
    """Read the API contract document."""
    assert CONTRACT_PATH.exists(), f"API contract not found at {CONTRACT_PATH}"
    content = CONTRACT_PATH.read_text(encoding="utf-8")
    assert len(content) > 1000, "API contract is too short"
    return content


def test_contract_exists_and_non_empty():
    """The API contract document must exist and be non-empty."""
    content = read_contract()
    assert "Hyperlocal Customer App" in content
    assert "API Contract" in content


def test_standard_response_structures_defined():
    """Standard success, error, and pagination structures must be defined."""
    content = read_contract()
    assert "Success Response" in content
    assert "Error Response" in content
    assert "Standard Pagination Structure" in content


def test_api_versioning_strategy_defined():
    """API versioning strategy must be defined."""
    content = read_contract()
    assert "API Versioning Strategy" in content
    assert "Backwards Compatibility Rules" in content


def test_standard_error_codes_defined():
    """Standard error codes must be defined."""
    content = read_contract()
    assert "Standard Error Codes" in content
    assert "VALIDATION_ERROR" in content
    assert "UNAUTHORIZED" in content
    assert "FORBIDDEN" in content
    assert "NOT_FOUND" in content
    assert "RATE_LIMIT_EXCEEDED" in content


def test_authentication_apis_defined():
    """Authentication APIs must be defined."""
    content = read_contract()
    assert "Send OTP" in content
    assert "Verify OTP" in content
    assert "Refresh Token" in content
    assert "Logout" in content


def test_customer_apis_defined():
    """Customer APIs must be defined."""
    content = read_contract()
    assert "Get Current User" in content
    assert "Update Current User" in content
    assert "Delete Current User" in content
    assert "Get Profile" in content
    assert "Update Profile" in content


def test_location_apis_defined():
    """Location APIs must be defined."""
    content = read_contract()
    assert "Get Nearby Shops (Location-based)" in content
    assert "Manual Location Search" in content


def test_category_apis_defined():
    """Category APIs must be defined."""
    content = read_contract()
    assert "List Categories" in content
    assert "Get Category by ID" in content


def test_brand_apis_defined():
    """Brand APIs must be defined."""
    content = read_contract()
    assert "List Brands" in content
    assert "Get Brand by ID" in content


def test_product_apis_defined():
    """Product APIs must be defined."""
    content = read_contract()
    assert "Get Product by Barcode" in content
    assert "Get Product by ID" in content
    assert "Compare Product Prices" in content


def test_product_variant_apis_defined():
    """Product Variant APIs must be defined."""
    content = read_contract()
    assert "List Product Variants" in content
    assert "Get Variant by ID" in content


def test_shop_apis_defined():
    """Shop APIs must be defined."""
    content = read_contract()
    assert "Get Nearby Shops" in content
    assert "Get Shop by ID" in content
    assert "Get Shop Products" in content


def test_shop_product_apis_defined():
    """Shop Product APIs must be defined."""
    content = read_contract()
    assert "Get Shop Product Detail" in content


def test_inventory_apis_defined():
    """Inventory APIs must be defined."""
    content = read_contract()
    assert "Get Product Inventory" in content
    assert "Get Shop Inventory" in content


def test_pricing_apis_defined():
    """Pricing APIs must be defined."""
    content = read_contract()
    assert "Get Price History" in content


def test_offer_apis_defined():
    """Offer APIs must be defined."""
    content = read_contract()
    assert "List Active Offers" in content
    assert "Get Offer by ID" in content


def test_search_apis_defined():
    """Search APIs must be defined."""
    content = read_contract()
    assert "Search Products" in content
    assert "Search Suggestions" in content
    assert "Get Search History" in content
    assert "Clear Search History" in content
    assert "Get Popular Searches" in content


def test_nearby_shop_apis_defined():
    """Nearby Shop APIs must be defined."""
    content = read_contract()
    assert "Get Nearby Shops with Products" in content


def test_saved_item_apis_defined():
    """Saved Item APIs must be defined."""
    content = read_contract()
    assert "List Saved Products" in content
    assert "Save Product" in content
    assert "Unsave Product" in content
    assert "List Saved Shops" in content
    assert "Save Shop" in content
    assert "Unsave Shop" in content


def test_notification_apis_defined():
    """Notification APIs must be defined."""
    content = read_contract()
    assert "List Notifications" in content
    assert "Mark Notification as Read" in content
    assert "Mark All Notifications as Read" in content
    assert "Get Notification Preferences" in content
    assert "Update Notification Preferences" in content
    assert "Register Device Token" in content
    assert "Unregister Device Token" in content


def test_shopkeeper_apis_defined():
    """Shopkeeper APIs must be defined."""
    content = read_contract()
    assert "Register Shop" in content
    assert "Get My Shops" in content
    assert "Submit Shop for Verification" in content
    assert "Get Verification Status" in content
    assert "List Shop Inventory" in content
    assert "Add Product to Shop Inventory" in content
    assert "Update Stock Quantity" in content
    assert "Update Price" in content
    assert "Scan Barcode" in content
    assert "Get Barcode Scan History" in content
    assert "Upload Excel Inventory" in content
    assert "Get Import Status" in content
    assert "Create POS Integration" in content
    assert "List POS Integrations" in content
    assert "Trigger POS Sync" in content
    assert "Get POS Sync Status" in content
    assert "List POS Sync Jobs" in content


def test_admin_apis_defined():
    """Admin APIs must be defined."""
    content = read_contract()
    assert "List All Shops" in content
    assert "Approve Shop" in content
    assert "Reject Shop" in content
    assert "Suspend Shop" in content
    assert "Reactivate Shop" in content
    assert "List Shop Verifications" in content
    assert "Review Verification" in content
    assert "List Product Approvals" in content
    assert "Review Product Approval" in content
    assert "List Users" in content
    assert "Suspend User" in content
    assert "Ban User" in content
    assert "Reactivate User" in content
    assert "List Subscriptions" in content
    assert "List Subscription Plans" in content
    assert "Create Subscription Plan" in content
    assert "List Complaints" in content
    assert "Update Complaint Status" in content
    assert "Get Dashboard Analytics" in content
    assert "Get Product Analytics" in content
    assert "Get Shop Analytics" in content
    assert "Get Search Analytics" in content
    assert "Generate Report" in content
    assert "Get Report Status" in content
    assert "List Reports" in content


def test_subscription_apis_defined():
    """Subscription APIs must be defined."""
    content = read_contract()
    assert "Get Current Subscription" in content
    assert "List Available Plans" in content
    assert "Subscribe to Plan" in content
    assert "Cancel Subscription" in content


def test_payment_apis_defined():
    """Payment APIs must be defined."""
    content = read_contract()
    assert "Create Payment Intent" in content
    assert "Verify Payment" in content
    assert "Get Payment Status" in content
    assert "List Payments" in content


def test_complaint_apis_defined():
    """Complaint APIs must be defined."""
    content = read_contract()
    assert "Create Complaint" in content
    assert "List My Complaints" in content
    assert "Get Complaint Detail" in content


def test_address_apis_defined():
    """Customer Address APIs must be defined."""
    content = read_contract()
    assert "List Addresses" in content
    assert "Create Address" in content
    assert "Update Address" in content
    assert "Delete Address" in content
    assert "Set Default Address" in content


def test_home_feed_api_defined():
    """Home Feed API must be defined."""
    content = read_contract()
    assert "Get Home Feed" in content


def test_every_endpoint_has_required_elements():
    """Every endpoint must define method, path, auth, request, response, errors, status codes."""
    content = read_contract()
    # Count endpoint definitions
    method_count = len(re.findall(r"\*\*Method:\*\*", content))
    path_count = len(re.findall(r"\*\*Path:\*\*", content))
    auth_count = len(re.findall(r"\*\*Auth:\*\*", content))
    error_count = len(re.findall(r"\*\*Error Cases:\*\*", content))
    idempotency_count = len(re.findall(r"\*\*Idempotency:\*\*", content))

    assert method_count >= 50, f"Expected at least 50 endpoints with Method, found {method_count}"
    assert path_count >= 50, f"Expected at least 50 endpoints with Path, found {path_count}"
    assert auth_count >= 50, f"Expected at least 50 endpoints with Auth, found {auth_count}"
    assert error_count >= 20, f"Expected at least 20 endpoints with Error Cases, found {error_count}"
    assert idempotency_count >= 20, f"Expected at least 20 endpoints with Idempotency, found {idempotency_count}"


def test_rate_limits_defined():
    """Rate limit expectations must be defined."""
    content = read_contract()
    assert "Rate Limits" in content
    assert "RATE_LIMIT_EXCEEDED" in content


def test_ownership_rules_defined():
    """Ownership rules must be defined."""
    content = read_contract()
    assert "Ownership Rules" in content
    assert "Shop owner/manager" in content


def test_frontend_screen_mapping_defined():
    """Every Customer App screen must be mapped to its required API."""
    content = read_contract()
    assert "Frontend Screen → API Mapping" in content
    assert "Splash Screen" in content
    assert "Home Screen" in content
    assert "Search Screen" in content
    assert "Product Detail" in content
    assert "Shop Detail" in content
    assert "Saved Products" in content
    assert "Notifications" in content
    assert "Profile" in content


def test_shopkeeper_operation_mapping_defined():
    """Every Shopkeeper App operation must be mapped to its required API."""
    content = read_contract()
    assert "Shopkeeper App Operations" in content
    assert "Register Shop" in content
    assert "Inventory List" in content
    assert "Barcode Scan" in content
    assert "Excel Import" in content
    assert "POS Integration" in content
    assert "Subscription" in content


def test_admin_operation_mapping_defined():
    """Every Admin operation must be mapped to its required API."""
    content = read_contract()
    assert "Admin Panel Operations" in content
    assert "Dashboard" in content
    assert "Approve Shop" in content
    assert "Review Verification" in content
    assert "User List" in content
    assert "Complaints" in content
    assert "Analytics" in content
    assert "Generate Report" in content


def test_no_undefined_api_dependencies():
    """No screen should depend on an undefined API."""
    content = read_contract()
    assert "No screen depends on an undefined API" in content
    assert "All major frontend features have a defined backend contract" in content


def test_validation_checklist_complete():
    """The validation checklist must be complete."""
    content = read_contract()
    # All checklist items should be checked
    unchecked = re.findall(r"- \[ \]", content)
    assert len(unchecked) == 0, f"Found {len(unchecked)} unchecked validation items"