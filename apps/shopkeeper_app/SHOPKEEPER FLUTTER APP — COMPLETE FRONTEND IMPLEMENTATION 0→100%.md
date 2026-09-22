# MASTER PROMPT

# HYPERLOCAL PRODUCT DISCOVERY PLATFORM

# SHOPKEEPER FLUTTER APP — COMPLETE FRONTEND IMPLEMENTATION 0→100%

You are a senior Flutter architect, mobile product designer, UX engineer, state-management engineer, API integration engineer, security engineer, QA engineer, and production release engineer.

You are implementing ONLY the:

SHOPKEEPER FLUTTER APP

for my existing Hyperlocal Product Discovery Platform.

This prompt is the complete frontend product contract for the Shopkeeper App.

The objective is:

BUILD THE SHOPKEEPER APP FROM THE EXISTING REPOSITORY TO A COMPLETE, STABLE, PRODUCTION-READY FRONTEND WITHOUT CONFUSION, DUPLICATION, BROKEN NAVIGATION, STATE LOSS, UI INCONSISTENCY, OR UNNECESSARY REWRITES.

---

# 0. ABSOLUTE PROJECT RULE

---

The Shopkeeper App must behave as one connected product.

Every screen must belong to one clear flow.

Every button must have a defined destination/action.

Every form must have validation.

Every API action must have loading/success/error handling.

Every authenticated screen must have authorization-aware navigation.

Every important state must have a UI representation.

Do NOT create isolated demo screens.

Do NOT create fake flows just to make the UI appear complete.

Do NOT create placeholder buttons with no behavior unless the feature is explicitly marked FUTURE.

Do NOT duplicate features under different names.

Do NOT create multiple competing architectures.

Do NOT rebuild unrelated Customer App code.

---

# 1. CURRENT PROJECT CONTEXT

---

Platform:

HyperLocal Product Discovery Platform

Business model:

Customer discovers a product and nearby physical shops.

Customer can see:

* product
* nearby shops
* price
* availability
* distance
* rating
* shop profile
* directions

Customer purchases offline at the physical shop.

This is NOT:

* food delivery
* grocery delivery
* e-commerce home delivery

---

# 2. SHOPKEEPER APP CORE PURPOSE

---

The Shopkeeper App allows a physical business/shopkeeper to:

1. Sign in
2. Create one Shopkeeper profile
3. Set up one shop/business profile
4. Manage business information
5. Manage shop location
6. Add products
7. Find products using barcode
8. Manually add products
9. Update inventory
10. Update prices
11. Create offers
12. Upload products/inventory through Excel/CSV
13. Support POS data/import where available
14. Monitor inventory freshness
15. View low-stock information
16. Manage shop profile
17. View supported business insights/reports
18. Receive app notifications
19. Manage settings
20. Contact support
21. Log out safely

---

# 3. CURRENT AUTHENTICATION DECISION

---

CURRENT MVP AUTHENTICATION:

Google Sign-In
+
Firebase Authentication

DO NOT IMPLEMENT OTP NOW.

DO NOT IMPLEMENT:

* Phone OTP
* SMS OTP
* FAST2SMS
* custom OTP service
* password authentication unless an already-existing approved project dependency requires it
* custom JWT login system

Future:

Phone OTP may be added later.

Design the architecture so adding Phone OTP later is possible without rewriting the entire app.

---

# 4. CURRENT ACCOUNT MODEL

---

CURRENT MVP:

ONE Firebase account
↓
ONE application user
↓
ONE Shopkeeper profile
↓
ONE shop/business profile

DO NOT IMPLEMENT NOW:

* multiple shops
* business switching
* multiple Shopkeeper profiles
* staff/team accounts
* role switching
* multi-business dashboard

The code must remain extensible for future multi-shop support.

---

# 5. APPROVED BUSINESS CATEGORIES

---

Only use these categories:

1. Pharmacy & Healthcare
2. Beauty & Personal Care
3. Furniture & Home Care
4. Household Goods
5. Sports, Fitness & Outdoor
6. Books, Media & Stationery
7. Automotive Parts & Tools
8. Hardware
9. Restaurants
10. Transport
11. Personal Transport / Personal Travel

IMPORTANT:

DO NOT add:

* Grocery
* Food

Restaurants are allowed.

Do not create category values separately in different screens.

Create one source of truth.

---

# 6. COMPLETE APP JOURNEY

---

The complete Shopkeeper flow must be:

APP START
↓
Splash / Initialization
↓
Authentication Check
↓
Google Sign-In
↓
Firebase Authentication
↓
Backend Token Verification
↓
Application User Check
↓
Shopkeeper Profile Check
↓
┌──────────────────────────────┐
│ Profile Exists?              │
└──────────────────────────────┘
↓ YES
Home
↓ NO
Create Shopkeeper Profile
↓
Shop Setup
↓
Shopkeeper Home
↓
┌────────────────────────────────────────────┐
│ Main Shopkeeper Features                  │
├────────────────────────────────────────────┤
│ Dashboard                                  │
│ Products                                   │
│ Inventory                                  │
│ Pricing & Offers                           │
│ Imports / POS                              │
│ Reports / Insights                         │
│ Shop Profile                               │
│ Notifications                              │
│ Settings                                   │
│ Support                                    │
└────────────────────────────────────────────┘

---

# 7. ROOT APP STRUCTURE

---

Use a clear production structure.

Recommended:

lib/
app/
app.dart
router/
app_router.dart
route_names.dart
route_guards.dart
theme/
app_theme.dart
app_colors.dart
app_text_styles.dart
app_spacing.dart
app_radius.dart
app_shadows.dart
config/
app_config.dart
environment.dart

core/
network/
auth/
storage/
location/
permissions/
errors/
logging/
connectivity/
utils/
constants/
widgets/
dialogs/
formatters/
validators/

features/
authentication/
profile/
onboarding/
home/
business/
products/
barcode/
inventory/
pricing/
offers/
imports/
pos/
notifications/
reports/
analytics/
shop_profile/
support/
settings/

main.dart

test/
integration_test/

Use the existing project structure if it already follows a sound architecture.

DO NOT force this exact folder tree blindly.

Audit first.

---

# 8. ARCHITECTURE RULE

---

Use separation of concerns.

UI
↓
View / Screen
↓
ViewModel / State Controller
↓
Repository
↓
Data Source / API Service
↓
Backend

Where complex client business logic genuinely exists:

UI
↓
ViewModel
↓
Use Case / Domain logic
↓
Repository

Do NOT put:

* API calls
* database logic
* business logic
* Firebase configuration
* permission logic

directly into UI widgets.

Flutter's current architecture guidance emphasizes Views/ViewModels, repositories/services, separation of concerns, immutable state and unidirectional data flow.

---

# 9. SINGLE SOURCE OF TRUTH

---

There must be one source of truth for each important state.

Examples:

Auth state
Profile state
Business state
Product state
Inventory state
Price state
Import state
Notification state

Do not keep multiple copies of the same mutable data in different providers/controllers.

Avoid:

productList1
productList2
productCacheList

unless there is an explicit repository/cache architecture.

---

# 10. NAVIGATION ARCHITECTURE

---

Use the existing router if sound.

If router implementation is missing or unsuitable, use go_router.

Define named routes centrally.

Major route groups:

/auth
/profile
/onboarding
/home
/products
/barcode
/inventory
/pricing
/offers
/imports
/pos
/reports
/analytics
/shop-profile
/notifications
/settings
/support

Protected routes must require authentication.

Shopkeeper routes must require:

Authenticated
+
SHOPKEEPER access

Unauthenticated:

→ Authentication

Authenticated without profile:

→ Create Profile

Authenticated with profile:

→ Home

Suspended/blocked:

→ Account Status

---

# 11. ROUTE GUARD LOGIC

---

At app startup:

1. Initialize Flutter
2. Initialize Firebase
3. Check Firebase auth state
4. Determine authenticated state
5. If unauthenticated → Login
6. If authenticated → retrieve Firebase user
7. Get ID token
8. Sync/check backend application user
9. Fetch Shopkeeper profile
10. Route accordingly

Do not show Home before required account state is known.

Avoid route flickering.

Use an initialization/splash state.

---

# 12. SCREEN INVENTORY

---

The app should cover these logical screens.

AUTHENTICATION

1. Splash
2. Welcome/Login
3. Google Account Selection handled by provider
4. Authentication Loading
5. Authentication Error
6. Account Creation / Profile Required

PROFILE / ONBOARDING

7. Create Shopkeeper Profile
8. Edit Shopkeeper Profile
9. Shop Setup
10. Location Permission
11. Shop Location Picker
12. Shop Details Review
13. Setup Complete

HOME

14. Shopkeeper Dashboard
15. Dashboard Notifications
16. Quick Actions

PRODUCTS

17. Product List
18. Product Search
19. Product Filters
20. Add Product
21. Edit Product
22. Product Details
23. Product Availability
24. Product Image state
25. Empty Product State

BARCODE

26. Barcode Permission
27. Barcode Scanner
28. Barcode Found
29. Product Found
30. Product Not Found
31. Barcode Conflict
32. Manual Add after Scan

INVENTORY

33. Inventory Dashboard
34. Inventory List
35. Update Stock
36. Stock History
37. Low Stock
38. Out of Stock
39. Inventory Freshness
40. Inventory Sync Status

PRICING

41. Price List
42. Update Price
43. Price History
44. Create Offer
45. Active Offers
46. Expired Offers
47. Offer Details

IMPORT

48. Import Center
49. Download Sample
50. File Picker
51. Upload Progress
52. Import Preview
53. Validation Errors
54. Import Processing
55. Import Success
56. Partial Success
57. Import Failed
58. Import History

POS

59. POS Integration
60. POS Connection Setup
61. POS Sync
62. Sync Progress
63. Sync Result
64. Sync History
65. POS Error

SHOP PROFILE

66. Shop Profile
67. Edit Shop
68. Business Information
69. Shop Location
70. Business Category
71. Operating Hours
72. Shop Status

REPORTS

73. Reports
74. Sales/Business Insights
75. Product Performance
76. Inventory Insights

NOTIFICATIONS

77. Notification Center
78. Notification Detail
79. Notification Preferences

SETTINGS

80. Account
81. Security
82. App Settings
83. Notification Settings
84. Privacy
85. Terms
86. About
87. Logout Confirmation

SUPPORT

88. Help Center
89. FAQ
90. Contact Support
91. Report Issue

SYSTEM STATES

92. Offline
93. Network Error
94. Server Error
95. Permission Denied
96. Session Expired
97. Unauthorized
98. Maintenance
99. Generic Retry
100. Empty State

Do not automatically create 100 Dart files.

Many states can be reusable components inside feature screens.

---

# 13. SCREEN 1 — SPLASH / INITIALIZATION

---

Show:

HyperLocal logo
Shopkeeper App

During initialization:

Firebase initialization
authentication state
local storage loading
app configuration

Do not show random progress percentages.

If initialization fails:

show retry.

---

# 14. SCREEN 2 — LOGIN

---

Title:

Welcome Back

Subtitle:

Manage your shop, products and inventory.

Primary:

Continue with Google

Optional:

Terms & Privacy

DO NOT show OTP.

DO NOT show phone login.

DO NOT show password login.

On success:

new user → profile creation

existing profile → home

---

# 15. GOOGLE AUTHENTICATION

---

Use Firebase Authentication.

Flow:

Google Sign-In
↓
Firebase User
↓
Firebase ID Token
↓
FastAPI
↓
Backend verification
↓
Application user
↓
Shopkeeper role
↓
Profile

Do not trust client-provided:

uid
role
profileId
shopId

Use Firebase identity + backend authorization.

---

# 16. CREATE SHOPKEEPER PROFILE

---

Title:

Create Your Shopkeeper Profile

Fields:

Full Name
Shop / Business Name
Business Category
Business Type
Email
Contact Number (optional)

Google email may be prefilled.

Google display name may be prefilled.

User can edit display name.

CTA:

Create Profile

After success:

→ Shop Setup

---

# 17. SHOP SETUP

---

Shop setup should collect only relevant initial business information.

Fields:

Shop Name
Category
Business Type
Description
Address
City
State
Pincode
Landmark
Operating Hours

Location:

Get Current Location

or

Choose on Map

Do not overfill initial setup with future verification requirements.

---

# 18. SHOP LOCATION

---

Support:

GPS
Map
Manual correction
Address
Latitude
Longitude
Accuracy

Show:

Getting location...
Location found
Location accuracy
Unable to get location
Permission denied

Allow user to confirm and adjust.

Never claim 100% accuracy.

---

# 19. CATEGORY-SPECIFIC FIELDS

---

The frontend should support dynamic category-specific requirements.

Architecture:

Selected Category
↓
Backend Requirements
↓
Required Fields
↓
Render UI

Do not hardcode every future verification field into one giant form.

Examples:

Pharmacy:
drug-license-related data in future

Restaurant:
FSSAI-related data in future

Transport:
transport-related fields in future

Current phase:

Only show fields that backend currently supports.

---

# 20. SHOPKEEPER HOME DASHBOARD

---

Header:

Good Morning, {Name}

Shop:

{Shop Name}

Status:

Active / Setup Required / Suspended

Summary cards:

Products
Inventory
Low Stock
Offers

Quick Actions:

Add Product
Barcode Scan
Update Inventory
Upload Excel
Update Price

Additional sections:

Recent activity
Inventory freshness
Important notifications
Setup completion

Do NOT show fake sales numbers.

If actual business/sales data is not available:

show:

"Sales insights will appear when data is available."

---

# 21. DASHBOARD PRINCIPLE

---

Dashboard must prioritize actions.

Top priorities:

1. Low stock
2. Failed import
3. Inventory stale
4. Important notification
5. Profile/setup issue

Then:

Products
Inventory
Pricing
Reports

---

# 22. PRODUCT MANAGEMENT

---

Product architecture:

PRODUCT MASTER
+
PRODUCT VARIANT
+
SHOP PRODUCT

Shopkeeper manages shop-specific association.

Do not duplicate Product Master unnecessarily.

---

# 23. PRODUCT LIST

---

Show:

Product image
Product name
Brand
Variant
Price
Stock
Availability
Freshness
Last updated

Search.

Filters:

Category
Brand
Availability
Stock
Price range
Recently updated

Sort:

Name
Price
Stock
Recently updated

---

# 24. ADD PRODUCT — THREE METHODS

---

Primary methods:

1. Manual
2. Barcode
3. Excel/Bulk

Future/POS integration:

4. POS import/sync

UX:

Add Product
↓
Choose Method

Manual
Barcode
Bulk Excel
POS where enabled

---

# 25. MANUAL PRODUCT

---

Fields only required by backend.

Possible:

Product Name
Brand
Category
Subcategory
Variant
Barcode
MRP
Selling Price
Availability
Quantity
Product Image
Description

Use conditional fields.

Do not make every field mandatory unless backend requires it.

---

# 26. BARCODE SCANNER

---

Flow:

Barcode Permission
↓
Scanner
↓
Scan
↓
Normalize
↓
Find Product
↓
┌─────────────────┐
│ Product Found?  │
└─────────────────┘
YES → Product Details
NO → Not Found

Product found:

show:

Name
Brand
Variant
Image
Identifier/barcode

Shopkeeper can:

Add to Shop
Edit shop-specific data
Set stock
Set price

---

# 27. BARCODE EDGE CASES

---

Handle:

camera permission denied
camera unavailable
barcode unreadable
invalid barcode
duplicate barcode
unsupported barcode
product not found
multiple matches
network unavailable
server error
already added to shop

Never trap the user on scanner screen.

Always provide:

Back
Retry
Manual Add

---

# 28. PRODUCT NOT FOUND

---

Show:

"Product not found"

Actions:

Try Again
Enter Manually

Do not silently invent a Product Master.

If backend supports product suggestion/request:

show only when API exists.

---

# 29. INVENTORY

---

Inventory belongs to Shop Product.

Shopkeeper should be able to:

view
update
search
filter
sort
inspect history

Stock states:

IN_STOCK
LOW_STOCK
OUT_OF_STOCK
UNKNOWN
DISCONTINUED

Use server values from API rather than duplicating enum definitions in multiple places.

---

# 30. UPDATE STOCK

---

Screen:

Product
Current Stock

Quantity control:

minus
current quantity
plus

or direct input.

Possible update source:

Manual
Barcode
POS
Excel

Show:

Last updated
Updated by
Source

CTA:

Save Stock

Prevent duplicate submission.

---

# 31. STOCK VALIDATION

---

Do not allow:

negative stock
invalid numbers
overflowing quantities

Backend remains authoritative.

If backend rejects:

display readable error.

---

# 32. INVENTORY HISTORY

---

Show:

date/time
old quantity
new quantity
change
source
actor where available

Example:

+50 Added
-10 Removed
Current 40

Use timeline or clean list.

---

# 33. LOW STOCK

---

Dedicated screen.

Show:

Product
Current Stock
Threshold
Restock action

Actions:

Update Stock
Open Product

Show warning banner only when appropriate.

---

# 34. INVENTORY FRESHNESS

---

Display:

Fresh
Recently Updated
Stale
Unknown

Example:

Updated 8 minutes ago

Do not invent freshness data.

Use backend timestamp.

---

# 35. PRICING

---

Shopkeeper can:

view price
edit price
view price history
create offers
activate/deactivate offers

Money values must use proper decimal/string handling.

Do not use floating point for financial presentation/calculation where data handling would lose precision.

---

# 36. PRICE UPDATE

---

Fields:

MRP
Selling Price

Optional:

Offer

Validation:

Selling Price

> = 0

MRP

> = 0

Do not allow invalid relationships where backend rules prohibit them.

Show current and previous value where useful.

---

# 37. PRICE HISTORY

---

Display:

Old price
New price
Date
Source
Updated by if available

Do not fabricate history.

---

# 38. OFFERS

---

Offer types may include:

Percentage
Fixed Discount
Promotional Price

Fields:

Offer Name
Offer Type
Value
Start Date
End Date

States:

Draft
Scheduled
Active
Expired
Disabled

Validate dates.

---

# 39. IMPORT CENTER

---

Central screen:

"Import & Sync"

Options:

Excel / CSV
POS

Show:

Last Import
Last Sync
Failed Imports
History

---

# 40. EXCEL / CSV FLOW

---

Flow:

Choose File
↓
Validate File
↓
Upload
↓
Preview
↓
Validate Rows
↓
Show Summary
↓
Confirm Import
↓
Processing
↓
Completed

Never immediately push an unreviewed file.

---

# 41. IMPORT PREVIEW

---

Show:

Total Rows
Valid Rows
Invalid Rows
Duplicate Rows

Preview:

Product
Brand
Category
Barcode
Price
Stock
Status

CTA:

Import Valid Rows

or:

Fix Errors

Only enable actions supported by backend.

---

# 42. IMPORT ERROR SCREEN

---

Show:

Row number
Field
Error
Suggested action

Examples:

Missing Product Name
Invalid Price
Duplicate Barcode
Invalid Category
Invalid Stock

Actions:

Download Error Report
Retry
Replace File

---

# 43. IMPORT PARTIAL SUCCESS

---

Example:

500 rows processed

482 successful
18 failed

Buttons:

View Results
View Errors
Done

Do not hide partial failures.

---

# 44. IMPORT HISTORY

---

Show:

Date
File
Rows
Success
Failed
Status

Statuses:

Uploaded
Validating
Processing
Completed
Partial Success
Failed

---

# 45. POS

---

POS is optional.

Do not make the whole app dependent on one POS provider.

The frontend should use provider-neutral concepts.

Screen:

POS Integration

Status:

Connected
Not Connected
Syncing
Error

Capabilities:

Connect
Sync Now
Last Sync
Sync History

If POS integration is unavailable:

show:

"POS integration is not configured for your account."

Do not fake connection.

---

# 46. BUSINESS PROFILE

---

Shopkeeper profile should show:

Profile Photo if available
Full Name
Email
Shop Name
Category
Business Type
Contact
Address
Location
Operating Hours
Status

Buttons:

Edit Profile
Edit Shop
Manage Location

---

# 47. SHOP PROFILE

---

Shop profile page:

Shop image
Shop name
category
description
location
address
contact
operating hours
status
verification state when backend supports it

Future verification modules should fit here.

---

# 48. SHOP STATUS

---

Possible frontend states:

ACTIVE
INACTIVE
SUSPENDED
SETUP_REQUIRED

Display clear explanation.

If suspended:

do not simply hide the app.

Show:

Account/Shop access restricted

and support contact.

---

# 49. NOTIFICATIONS

---

Notification categories:

Inventory
Products
Pricing
Offers
Imports
POS
Account
System
Support

Examples:

Low stock
Import completed
Import failed
Price update successful
Profile action required
Account status changed

---

# 50. NOTIFICATION CENTER

---

Features:

Read/unread
Mark read
Mark all read
Filter
Open related screen

Notification deep links:

Low Stock
→ Inventory

Import Failed
→ Import Result

Price Update
→ Product/Price

Profile Issue
→ Profile

Do not hardcode navigation IDs without validating the notification payload.

---

# 51. SETTINGS

#-------------------------------------------------

SETTINGS must contain logical groups.

ACCOUNT

My Profile
Shop Profile
Logout

SECURITY

Authentication
Session
Device/session information if backend supports it

APP

Notifications
Theme
Language
Data/Storage
About

LEGAL

Privacy Policy
Terms & Conditions

SUPPORT

Help Center
FAQs
Contact Support
Report Issue

---

# 52. LANGUAGE

---

Prepare the architecture for localization.

At minimum:

English

Do not hardcode every user-facing string directly into widgets if the project is being structured for future localization.

---

# 53. THEME

---

Use ONE centralized design system.

Reference style:

Primary:
HyperLocal blue / royal blue

Supporting:

Green
Orange
White
Light gray
Dark text

Use centralized:

colors
typography
spacing
radius
shadows
button styles
input styles
card styles

Do not create random colors per screen.

---

# 54. UI DESIGN LANGUAGE

---

All screens should feel like one app.

Use:

rounded cards
clean headers
consistent icons
clear section titles
bottom navigation where appropriate
large touch targets
readable forms
subtle shadows
minimal clutter
clear CTA

Avoid:

over-designed screens
too many gradients
tiny fonts
random animations
random colors
inconsistent padding

---

# 55. MAIN BOTTOM NAVIGATION

---

Use a logical persistent navigation.

Recommended:

Home
Products
Inventory
Reports
Profile

Additional actions can be available through:

Quick Actions
More
Floating/Add action
screen-level menus

Do not place every feature as a bottom-tab.

---

# 56. QUICK ACTION CENTER

---

Recommended actions:

Add Product
Barcode Scan
Update Stock
Upload Excel
Update Price
Create Offer

Only show actions appropriate to the current account state.

---

# 57. FORMS

#--------------------------------------------------

Every form must have:

labels
placeholders
required indicators
input format
keyboard type
validation
error state
loading state
success state
server error handling

Preserve user-entered data when validation fails.

Avoid clearing entire form after one error.

---

# 58. KEYBOARD UX

---

Forms must handle:

numeric keyboard
decimal keyboard
email keyboard
text keyboard
barcode/input types where applicable

Use:

next field
done
dismiss keyboard

properly.

Ensure keyboard does not cover important CTA buttons.

---

# 59. RESPONSIVENESS

---

Support:

small Android phones
medium phones
large phones
different aspect ratios
font scaling

Avoid:

fixed-width layouts
hardcoded screen coordinates
overflow-prone widgets

Use responsive layouts.

---

# 60. ACCESSIBILITY

---

Support:

semantic labels
accessible buttons
adequate contrast
large touch targets
readable text
meaningful error messages

Icons must not be the only indicator of important state.

Example:

Do not rely only on red color.

Use:

Low Stock

* icon/color

---

# 61. OFFLINE MODE

#--------------------------------------------------

The app should detect connectivity.

States:

Online
Offline
Reconnecting

When offline:

allow safe local read-only access to cached data where implemented.

Do NOT claim a write succeeded if backend did not accept it.

For pending writes, only use an explicit queue if the feature has been intentionally designed.

Never silently lose a user update.

---

# 62. LOCAL STORAGE

#--------------------------------------------------

Use secure storage for sensitive local credentials/state.

Use ordinary local storage/cache for non-sensitive data.

Potential local data:

last selected filters
temporary form draft
recent import metadata
cached non-sensitive shop data
UI preferences

Never store secrets unnecessarily.

Do not store Firebase private credentials.

---

# 63. ERROR HANDLING SYSTEM

#--------------------------------------------------

Create a centralized error model.

Handle:

NetworkError
TimeoutError
UnauthorizedError
ForbiddenError
NotFoundError
ConflictError
ValidationError
ServerError
UnknownError

Map technical errors to user-friendly messages.

---

# 64. SESSION EXPIRATION

#--------------------------------------------------

When backend returns unauthorized:

1. attempt safe token refresh if appropriate
2. retry only when safe
3. if session is invalid:
   clear app auth state
   route to login

Do not endlessly retry.

---

# 65. API CLIENT

#--------------------------------------------------

Use one centralized API client.

It must handle:

base URL
headers
Firebase token
timeouts
request IDs if supported
status code handling
token refresh
logging in development only

Do not create separate HTTP clients inside every feature.

---

# 66. API CONTRACT

#--------------------------------------------------

Never invent API response formats if backend contracts already exist.

Read existing backend contracts first.

Frontend models must map to backend DTOs.

Handle:

nullable fields
missing optional fields
enum additions
unknown values gracefully

---

# 67. MODEL DESIGN

#--------------------------------------------------

Separate:

API models
domain/application models
UI state

where complexity requires.

Do not use raw JSON maps throughout the entire app.

Avoid giant "UniversalModel" classes.

---

# 68. REPOSITORIES

#--------------------------------------------------

Have one clear repository per major data domain where justified.

Examples:

AuthRepository
ShopProfileRepository
ProductRepository
InventoryRepository
PricingRepository
ImportRepository
NotificationRepository
ReportRepository

Do not create repositories with unclear ownership.

Repositories are the data access abstraction / source of truth boundary. Flutter's architecture guidance explicitly recommends repositories as sources of truth for app data.

---

# 69. VIEW MODELS / STATE

#--------------------------------------------------

Each major screen should have a clear state controller/ViewModel.

Example state:

Initial
Loading
Loaded
Empty
Saving
Success
Error

Avoid dozens of unrelated booleans.

Bad:

isLoading
isSaving
isError
isSuccess
hasData
isEmpty
isUploading
...

when these states can contradict each other.

Prefer a coherent state model.

---

# 70. PRODUCT STATE

#--------------------------------------------------

Product state should cover:

list
pagination
search
filter
sort
detail
create
edit
delete/deactivate
loading
error

Do not lose list state unnecessarily when opening product detail and returning.

---

# 71. INVENTORY STATE

#--------------------------------------------------

Cover:

inventory list
filters
search
stock update
history
low stock
out of stock
refresh
pagination
loading
error

---

# 72. IMPORT STATE

#--------------------------------------------------

Cover:

no file
file selected
uploading
validation
preview
ready
processing
completed
partial success
failed

This must be explicit.

---

# 73. FORM DRAFTS

#--------------------------------------------------

Long forms must preserve drafts during temporary navigation.

Example:

Create Product
→ Barcode screen
→ returns
→ previously entered data remains.

Do not destroy controllers/state unnecessarily.

---

# 74. DESTRUCTIVE ACTIONS

#--------------------------------------------------

For actions such as:

deactivate product
remove offer
logout
disconnect POS

show confirmation.

Explain impact clearly.

---

# 75. DELETE VS DEACTIVATE

#--------------------------------------------------

Use backend-approved semantics.

Do not provide hard delete from UI unless backend explicitly allows it.

Prefer:

Deactivate
Archive

when historical data must remain.

---

# 76. LOADING UX

#--------------------------------------------------

Every async action should provide feedback:

loading indicator
button disabled state
progress where applicable

Examples:

Signing in...
Creating profile...
Saving product...
Updating inventory...
Uploading file...
Processing import...
Syncing POS...

---

# 77. EMPTY STATES

#--------------------------------------------------

Every list must have a useful empty state.

Product list:

"No products yet"

CTA:

Add Product

Inventory:

"No inventory found"

CTA:

Add Product / Import

Offers:

"No active offers"

CTA:

Create Offer

Notifications:

"You're all caught up"

Reports:

"No insights available yet"

Do not show blank white screens.

---

# 78. ERROR STATES

#--------------------------------------------------

Each feature must have:

Retry
Back
Alternative action where applicable

Example:

Import failed

→ View Details
→ Retry
→ Replace File

---

# 79. PERMISSIONS

#--------------------------------------------------

Handle runtime permissions for:

Camera
Location
Notifications where applicable
Photos/files depending on platform implementation

Never request all permissions at app launch.

Ask when feature requires it.

Explain why before request when useful.

---

# 80. BARCODE CAMERA PERMISSION

#--------------------------------------------------

When barcode scan first opens:

Explain:

"Camera access is needed to scan product barcodes."

Then request permission.

If denied:

Show:

Allow Camera
Enter Barcode Manually

If permanently denied:

provide system settings guidance.

---

# 81. LOCATION PERMISSION

#--------------------------------------------------

When setting shop location:

Ask location permission.

Handle:

granted
denied
denied forever
location services disabled

Provide fallback:

Choose Location on Map
Enter Address Manually

---

# 82. NOTIFICATION PERMISSION

#--------------------------------------------------

Do not block the entire app when notifications are denied.

Provide:

Enable Notifications

inside settings.

---

# 83. SECURITY

#--------------------------------------------------

Never put:

AWS access keys
AWS secret keys
Firebase Admin private credentials
backend secrets
database credentials

inside Flutter.

Flutter must communicate with FastAPI.

Flutter must never connect directly to PostgreSQL.

Flutter must never use permanent AWS credentials for S3.

---

# 84. FIREBASE CLIENT CONFIG

#--------------------------------------------------

Use normal Firebase client configuration for the app.

Do not put Firebase Admin SDK credentials into Flutter.

Google Sign-In must be configured through the Firebase project.

If Google Sign-In is not configured:

report exact required manual Firebase Console step rather than inventing configuration.

Firebase Authentication providers must be enabled in Firebase Console.

---

# 85. AWS FRONTEND ROLE

#--------------------------------------------------

The Shopkeeper Flutter app should NOT manage AWS infrastructure directly.

Frontend talks to:

FastAPI API

FastAPI handles:

database
S3
Redis
AWS services

Potential file flow:

Flutter
↓
FastAPI
↓
authorized upload URL
↓
S3

only when backend supports this architecture.

---

# 86. S3 MEDIA

#--------------------------------------------------

For future/implemented media:

Shop image
Product image
Documents
Import files

Frontend should receive controlled upload/download URLs from backend.

Do not hardcode bucket information unnecessarily.

---

# 87. ANALYTICS / REPORTS

#--------------------------------------------------

Only show real data.

Do NOT create fake sales/revenue charts just to make dashboard look populated.

Potential metrics when backend provides them:

Product views
Shop views
Search appearances
Inventory updates
Top products
Availability trends
Sales/business metrics when legally and technically available

If no data:

show a clear empty state.

---

# 88. SHOPKEEPER BUSINESS INSIGHTS

#--------------------------------------------------

Possible insight cards:

Top Products
Low Stock
Stale Inventory
Product Search Visibility
Offers Performance
Profile Completeness

These should be data-driven.

---

# 89. PROFILE COMPLETENESS

#--------------------------------------------------

Optionally show:

Profile completion %
Business information
Location
Shop photo
Operating hours
Other backend-supported setup requirements

Do not manufacture percentages.

Calculate from actual required fields.

---

# 90. SUPPORT

#--------------------------------------------------

Support section:

FAQs
Contact Support
Report Issue
Terms & Conditions

For Report Issue:

Category
Description
Optional screenshot/attachment if backend supports it

Status:

Submitted
In Progress
Resolved

Only implement ticket tracking if backend exists.

---

# 91. ACCOUNT MANAGEMENT

#--------------------------------------------------

Account screen:

Name
Email
Authentication provider
Profile
Shop

Actions:

Edit Profile
Settings
Logout

Show only the information actually available.

---

# 92. LOGOUT

#--------------------------------------------------

Flow:

Profile/Settings
↓
Logout
↓
Confirmation
↓
Firebase signOut
↓
Clear session-dependent app state
↓
Login

Do not leave old Shopkeeper profile data visible after logout unless intentionally cached and revalidated.

---

# 93. APP LIFECYCLE

#--------------------------------------------------

Handle:

background
foreground
token refresh
network reconnect
screen resume

On resume:

refresh important stale data where appropriate.

Do not reload every API on every frame or navigation event.

---

# 94. PAGINATION

#--------------------------------------------------

Large lists must not load everything.

Use backend pagination.

Prefer cursor/keyset pagination where backend supports it.

Screens requiring pagination:

Products
Inventory
Notifications
Import History
Price History
Reports where applicable

---

# 95. SEARCH

#--------------------------------------------------

Product search should support:

debounce
server search
local search where useful
empty state
no result
clear search
recent search if implemented

Do not trigger an API call for every keystroke.

---

# 96. FILTER / SORT

#--------------------------------------------------

Reusable filter UI.

Inventory filters:

Stock
Category
Freshness

Product filters:

Category
Brand
Availability
Price

Offer filters:

Active
Scheduled
Expired

Keep filter state predictable.

---

# 97. REFRESH

#--------------------------------------------------

Implement pull-to-refresh where useful.

Do not refresh unnecessarily.

After mutation:

prefer updating affected state or invalidating affected repository data instead of reloading the entire application.

---

# 98. PRODUCT IMAGE UX

#--------------------------------------------------

If backend supports product images:

show:

placeholder
loading
loaded
failed

Allow:

replace
remove

Never crash if image URL is null or invalid.

---

# 99. FILE HANDLING

#--------------------------------------------------

When selecting files:

validate:

type
size
supported extension

Show clear failure reason.

Never assume file exists after picker closes.

Handle cancellation.

---

# 100. DATE/TIME

#--------------------------------------------------

Use consistent localization.

Show user-friendly date/time.

Use backend timestamps safely.

Do not mix local/UTC incorrectly.

---

# 101. DATA FRESHNESS

#--------------------------------------------------

Every remote dataset may have freshness characteristics.

Display last updated time when useful.

Examples:

Inventory updated 5 min ago
Price updated today
Last POS sync yesterday

Do not display stale information as fresh.

---

# 102. ACCESS CONTROL

#--------------------------------------------------

The frontend should hide unavailable actions where backend/account capabilities do not permit them.

BUT:

UI hiding is not authorization.

Backend remains authoritative.

Frontend must gracefully handle:

403 Forbidden

---

# 103. FEATURE FLAGS / CAPABILITIES

#--------------------------------------------------

Where appropriate, backend can return capabilities.

Example:

canUsePos
canUploadExcel
canCreateOffers
canViewReports

Frontend can use these to conditionally show functionality.

Do not duplicate entitlement logic separately in many screens.

---

# 104. FUTURE SUBSCRIPTION SUPPORT

#--------------------------------------------------

Subscription/plan features may come later.

Do not hardcode paid feature logic everywhere.

Prepare one centralized capability/entitlement layer if future backend provides:

plan
subscription status
feature entitlements

Do not implement payments unless explicitly requested.

---

# 105. FUTURE VERIFICATION

#--------------------------------------------------

Future verification may include:

business identity
GST/Udyam
bank verification
category documents
admin review

Do not implement these now unless backend contract is ready.

Create clear extension points.

---

# 106. SHOPKEEPER DATA FLOW

#--------------------------------------------------

The final frontend flow must align with:

SHOPKEEPER
↓
GOOGLE SIGN-IN
↓
FIREBASE AUTH
↓
FIREBASE ID TOKEN
↓
FASTAPI
↓
APPLICATION USER
↓
SHOPKEEPER PROFILE
↓
SHOP
↓
PRODUCTS
↓
INVENTORY
↓
PRICES
↓
OFFERS
↓
IMPORT/POS
↓
SHOPKEEPER DASHBOARD

Backend data:

Flutter
↓
FastAPI
↓
PostgreSQL/PostGIS

Media:

Flutter
↓
FastAPI authorization
↓
S3

Optional cache/state:

FastAPI
↓
Redis/Valkey

---

# 107. PRODUCT DATA FLOW

#--------------------------------------------------

Manual:

Add Product
↓
Validate
↓
API
↓
Product/Shop Product
↓
Inventory
↓
Price
↓
Publish

Barcode:

Scan
↓
Resolve Product
↓
Attach to Shop
↓
Set Price
↓
Set Stock
↓
Publish

Excel:

Select File
↓
Upload
↓
Preview
↓
Validate
↓
Confirm
↓
Import
↓
Results

POS:

Connect/Import
↓
Normalize
↓
Preview/Sync
↓
Database

---

# 108. DATA CONSISTENCY

#--------------------------------------------------

After successful mutation:

repository state must become consistent with backend.

Examples:

Price updated
→ price state updated

Stock updated
→ inventory list updated

Product added
→ product list updates

Import completed
→ import history updates

Notification opened
→ unread count updates

---

# 109. CACHE RULE

#--------------------------------------------------

Cache only what is useful.

Never let stale cache become authoritative.

After mutations:

invalidate affected cached data.

---

# 110. PERFORMANCE

#--------------------------------------------------

Target:

fast startup
smooth scrolling
minimal unnecessary rebuilds
small API payloads
lazy loading
pagination
image optimization
debounced search
proper caching

Avoid:

heavy work inside build()
large synchronous loops
unnecessary global rebuilds
nested uncontrolled FutureBuilders
duplicate API calls

---

# 111. MEMORY MANAGEMENT

#--------------------------------------------------

Dispose controllers/listeners correctly.

Avoid:

memory leaks
duplicate listeners
repeated stream subscriptions
camera resource leaks
unbounded image caching

---

# 112. BARCODE CAMERA LIFECYCLE

#--------------------------------------------------

When leaving scanner:

pause/stop camera resources appropriately.

When reopening:

initialize cleanly.

Do not leave camera active in background.

---

# 113. APP STARTUP PERFORMANCE

#--------------------------------------------------

Do not load:

all products
all inventory
all notifications
all reports

during splash.

Only load the minimum necessary for routing/home.

Load secondary data lazily.

---

# 114. ARCHITECTURAL DUPLICATION CHECK

#--------------------------------------------------

Before creating any:

service
repository
model
provider
viewmodel
API client
storage helper
validator
widget

search the repository.

Reuse or refactor existing code.

Do NOT create:

AuthServiceV2
ProductRepositoryNew
ApiClientNew
ProfileProvider2

without an explicit architecture reason.

---

# 115. LEGACY CODE

#--------------------------------------------------

Existing code may contain:

duplicate files
unused files
obsolete screens
old providers
old API clients
dead imports

Do not delete immediately.

First:

find references
inspect dependencies
verify runtime usage
check tests
check routes

Then safely refactor.

---

# 116. DESIGN SYSTEM COMPONENTS

#--------------------------------------------------

Create reusable components where genuinely useful.

Examples:

AppHeader
PrimaryButton
SecondaryButton
AppTextField
DropdownField
StatusChip
ProductCard
InventoryCard
OfferCard
DocumentCard
EmptyState
ErrorState
LoadingState
ConfirmationDialog
SectionHeader
FilterSheet
BottomNav

Do not create hundreds of micro-widgets.

---

# 117. SCREEN REUSABILITY

#--------------------------------------------------

Do not copy-paste complete screens for similar features.

Example:

same ProductForm component can support:

Add
Edit

same PriceForm can support:

Create
Update

same ImportStatus component can support:

Processing
Success
Partial
Failed

---

# 118. DEEP LINKING

#--------------------------------------------------

Where practical, support internal navigation to:

Product Detail
Inventory
Import Result
Notification Detail
Shop Profile

A future notification can open the exact feature.

---

# 119. APP STATE AFTER BACK NAVIGATION

#--------------------------------------------------

When returning from detail/edit:

preserve list:

search
filter
sort
scroll position where practical

Do not reset entire feature unnecessarily.

---

# 120. UNSAVED CHANGES

#--------------------------------------------------

For forms:

if user has unsaved changes
and attempts to leave:

show confirmation:

"Discard changes?"

Allow:

Stay
Discard

---

# 121. CONFIRMATIONS

#--------------------------------------------------

Use confirmation for risky actions:

Logout
Deactivate Product
Deactivate Offer
Disconnect POS
Discard Import
Discard unsaved form

---

# 122. APP CONFIGURATION

#--------------------------------------------------

Centralize:

API base URL
environment
feature flags
Firebase configuration references
timeouts
app constants

Support:

LOCAL
STAGING
PRODUCTION

Do not hardcode production endpoints throughout files.

---

# 123. ENVIRONMENT SAFETY

#--------------------------------------------------

Never commit:

production secrets
private keys
Firebase Admin credentials
AWS credentials
database passwords

Use placeholders in:

.env.example

---

# 124. LOGGING

#--------------------------------------------------

Development:

use structured debug logging.

Production:

do not log sensitive information.

Never log:

Firebase ID tokens
AWS secrets
personal confidential information
private documents

---

# 125. CRASH PREVENTION

#--------------------------------------------------

Every external-data screen must tolerate:

null
empty
missing
unknown enum
malformed URL
network failure
server failure

Do not assume backend always returns perfect data.

---

# 126. ENUM FORWARD COMPATIBILITY

#--------------------------------------------------

When backend sends an unknown enum value:

do not crash.

Map to:

unknown/default state

and continue safely.

---

# 127. LOCALIZATION-READY TEXT

#--------------------------------------------------

Do not scatter hardcoded user-visible text across business logic.

Keep UI strings organized.

---

# 128. TESTING REQUIREMENT

#--------------------------------------------------

Minimum testing layers:

UNIT TESTS
for:

validators
formatters
viewmodels
mappers
business logic

WIDGET TESTS
for:

forms
buttons
error states
empty states
loading states

INTEGRATION TESTS
for:

login
profile creation
product creation
inventory update
price update
import flow

---

# 129. AUTH TEST CASES

#--------------------------------------------------

Test:

Google success
Google cancelled
Firebase failure
invalid token
backend unavailable
existing user
new user
profile exists
profile missing
logout
suspended account

---

# 130. PRODUCT TEST CASES

#--------------------------------------------------

Test:

manual add
barcode add
duplicate barcode
not found
invalid product
edit
deactivate
image unavailable
network failure

---

# 131. INVENTORY TEST CASES

#--------------------------------------------------

Test:

stock increase
stock decrease
zero
negative
large number
concurrent update response
stale inventory
network failure

---

# 132. PRICE TEST CASES

#--------------------------------------------------

Test:

valid price
zero
invalid negative price
decimal handling
price conflict
offer validation

---

# 133. IMPORT TEST CASES

#--------------------------------------------------

Test:

valid file
invalid file
cancelled picker
empty file
large file
duplicate barcode
invalid category
invalid price
partial success
server failure
retry

---

# 134. PERMISSION TESTS

#--------------------------------------------------

Test:

camera denied
camera permanently denied
location denied
location unavailable
notification denied

Every permission denial must have a usable alternative where possible.

---

# 135. UI TESTING

#--------------------------------------------------

Verify:

no overflow
no clipped text
no broken keyboard layout
no infinite loaders
no duplicate taps
correct back navigation
correct deep links
consistent theme
dark/light behavior only if implemented
small-device compatibility

---

# 136. NETWORK TESTING

#--------------------------------------------------

Verify behavior under:

fast internet
slow internet
offline
reconnect
server 500
server 401
server 403
server 404
server 409
server 422
server timeout

---

# 137. SECURITY TESTING

#--------------------------------------------------

Verify frontend never:

stores secret keys
stores AWS credentials
uses Firebase Admin credentials
connects directly to database
trusts role from local storage
trusts shop ID for authorization

---

# 138. RELEASE QUALITY

#--------------------------------------------------

Before completion run:

flutter analyze

flutter test

integration tests

formatting

build validation

where project supports:

Android debug
Android release
iOS build validation if environment permits

Fix all:

compile errors
analyzer errors
broken imports
routing errors
type errors
null crashes
overflow
dead states

---

# 139. NO BROKEN FLOW RULE

#--------------------------------------------------

For EVERY user-visible action answer these questions:

1. Where does the button go?
2. What API is called?
3. What loading state appears?
4. What success state appears?
5. What error state appears?
6. What happens if user presses back?
7. What happens if network fails?
8. What happens if permission is denied?
9. What happens if the user repeats the action?
10. What happens after app restart?

If an answer is undefined:

STOP and resolve architecture before implementation.

---

# 140. IMPLEMENTATION PHASES

#--------------------------------------------------

Do NOT build the entire app blindly in one pass.

Use this exact development order.

PHASE 1 — REPOSITORY AUDIT

Inspect:

Flutter version
Dart version
existing architecture
authentication
Firebase
routing
state management
API client
theme
network
storage
existing Shopkeeper code

Deliver:

architecture report

---

PHASE 2 — ARCHITECTURE CONTRACT

Define:

routing
state management
repositories
models
API layer
theme
error model
storage
permissions

Do not implement large UI yet.

---

PHASE 3 — APP FOUNDATION

Implement/verify:

main
Firebase
environment
router
theme
dependency injection
error handling
connectivity
secure storage
API client

---

PHASE 4 — AUTHENTICATION

Implement:

Splash
Login
Google Sign-In
Firebase auth state
FastAPI token exchange/verification integration
logout

NO OTP.

---

PHASE 5 — PROFILE

Implement:

Create Profile
Profile load
Edit Profile
Profile state
Profile persistence

---

PHASE 6 — SHOP SETUP

Implement:

Shop information
Category
Business type
Location
Operating hours
Setup completion

---

PHASE 7 — DASHBOARD

Implement:

Home
Quick actions
Notifications preview
Important status cards
profile completion

---

PHASE 8 — PRODUCT MANAGEMENT

Implement:

Product list
search
filter
sort
add
edit
details
deactivate
empty/error/loading states

---

PHASE 9 — BARCODE

Implement:

permission
scanner
scan result
product lookup
not found
manual fallback
duplicate handling

---

PHASE 10 — INVENTORY

Implement:

list
search
filter
update stock
history
low stock
out of stock
freshness

---

PHASE 11 — PRICING

Implement:

price list
update price
price history

---

PHASE 12 — OFFERS

Implement:

create
edit
active
scheduled
expired
deactivate

---

PHASE 13 — BULK IMPORT

Implement:

import center
file selection
upload
preview
validation
processing
success
partial
failure
history

---

PHASE 14 — POS

Implement ONLY if backend/API contract exists.

Connect
Sync
Status
History
Errors

---

PHASE 15 — REPORTS / INSIGHTS

Implement actual backend-supported data only.

No fake analytics.

---

PHASE 16 — NOTIFICATIONS

Implement:

center
read/unread
deep links
preferences

---

PHASE 17 — PROFILE / SETTINGS / SUPPORT

Implement:

Shop Profile
Edit Shop
Settings
Notifications
Privacy
Terms
Support
FAQ
Logout

---

PHASE 18 — SYSTEM STATES

Implement/reuse:

Loading
Empty
Offline
Error
Retry
Permission denied
Session expired
Unauthorized
Maintenance

---

PHASE 19 — PERFORMANCE

Audit:

rebuilds
API calls
list rendering
images
memory
startup
pagination

---

PHASE 20 — TESTING

Unit
Widget
Integration
Navigation
Auth
Import
Inventory
Barcode
Error states

---

PHASE 21 — FINAL HARDENING

Fix all remaining:

bugs
duplicate architecture
dead code
broken imports
UI overflow
routing issues
state issues
API mapping issues

---

# 141. VISUAL REFERENCE

#--------------------------------------------------

Use the previously approved Shopkeeper UI references as design direction.

Visual principles:

HyperLocal branding

Deep blue / royal blue
+
white/light backgrounds
+
green success states
+
orange warning highlights

Use:

rounded cards
clean forms
large CTA
consistent headers
professional icons
mobile-first composition
soft shadows
clear spacing
premium merchant-app appearance

Reference flow includes:

Login
Registration
Verification concept
Shop Setup
Dashboard
Add Product
Barcode Scan
Excel Upload
Inventory
Price Management
Product List
Low Stock
Reports
Shop Profile
Support

IMPORTANT:

The visual reference contains some older/example content.

Current technical rules override reference content where they conflict.

Examples:

OTP = future, not current MVP

Grocery = not approved category

Food = not approved scope

Subscription pricing = illustrative only

Sales data = only if real backend data exists

---

# 142. CURRENT AUTHENTICATION UI OVERRIDE

#--------------------------------------------------

Current UI:

Continue with Google

Future:

Phone OTP

Do not place OTP in current visible flow.

---

# 143. CURRENT SINGLE PROFILE OVERRIDE

#--------------------------------------------------

Current UI assumes:

ONE Shopkeeper
ONE profile
ONE shop/business

Do not show:

Switch Business
Add Another Shop
Manage Multiple Shops

until future phase.

---

# 144. CURRENT DATA OWNERSHIP

#--------------------------------------------------

Current authenticated user:

Firebase identity

Backend:

application user

Profile:

shopkeeper profile

Shop:

single business/shop

All API operations must be tied to authenticated user/backend identity.

---

# 145. DESIGN CONTRACT

#--------------------------------------------------

Use a predictable page hierarchy.

Top:

Back / Title / contextual action

Body:

sections/cards/forms

Bottom:

Primary CTA where necessary

Avoid:

multiple competing CTAs

---

# 146. BUTTON CONTRACT

#--------------------------------------------------

Every primary button must have:

normal
pressed
disabled
loading
error-safe behavior

Example:

Save Product

normal:
Save Product

loading:
Saving...

disabled:
disabled

success:
navigate/update state

---

# 147. STATE CONTRACT

#--------------------------------------------------

Every screen should clearly support:

INITIAL
LOADING
SUCCESS/LOADED
EMPTY
ERROR

For mutation screens additionally:

SAVING
SUCCESS
FAILURE

---

# 148. DATA CONTRACT

#--------------------------------------------------

Frontend is not source of truth for:

authorization
inventory truth
price truth
verification truth
profile ownership

Backend/database remains authoritative.

---

# 149. CUSTOMER APP IS OUT OF SCOPE

#--------------------------------------------------

DO NOT:

rebuild Customer App
redesign Customer App
change Customer screens unnecessarily
duplicate Customer features inside Shopkeeper App

Only make shared changes when technically required and backward compatible.

---

# 150. FINAL QUALITY GATE

#--------------------------------------------------

Do not declare the Shopkeeper App complete merely because:

screens compile
or
buttons navigate.

It is complete only when:

[ ] Authentication works
[ ] Google Sign-In works
[ ] Firebase session works
[ ] Backend auth integration works
[ ] One Shopkeeper profile works
[ ] Shop setup works
[ ] Navigation is coherent
[ ] Dashboard works
[ ] Product management works
[ ] Barcode flow works
[ ] Inventory works
[ ] Price management works
[ ] Offers work
[ ] Excel import works if backend exists
[ ] POS works if backend exists
[ ] Notifications work if backend exists
[ ] Reports show real data only
[ ] Settings work
[ ] Support works
[ ] Logout works
[ ] Offline/error states work
[ ] Permissions work
[ ] No duplicate services/models/providers
[ ] No broken imports
[ ] No auth bypass
[ ] No hardcoded secrets
[ ] No direct database access
[ ] No unnecessary AWS access in Flutter
[ ] No major UI overflow
[ ] No navigation dead ends
[ ] Analyzer passes
[ ] Tests pass

---

# 151. FINAL DELIVERABLE

#--------------------------------------------------

After implementation provide a complete report:

A. CURRENT PROJECT AUDIT

B. FINAL FOLDER TREE

C. SCREEN INVENTORY

D. ROUTE MAP

E. AUTHENTICATION FLOW

F. PROFILE FLOW

G. SHOP SETUP FLOW

H. PRODUCT FLOW

I. BARCODE FLOW

J. INVENTORY FLOW

K. PRICE/OFFER FLOW

L. IMPORT FLOW

M. POS FLOW

N. NOTIFICATION FLOW

O. SETTINGS FLOW

P. ERROR/EMPTY/OFFLINE STATES

Q. API CONTRACTS USED

R. MODELS CREATED/REUSED

S. REPOSITORIES CREATED/REUSED

T. VIEWMODELS/STATE CREATED

U. SHARED COMPONENTS CREATED

V. FILES CREATED

W. FILES MODIFIED

X. FILES REMOVED

Y. DUPLICATES REMOVED

Z. TESTS RUN

AA. ANALYZER RESULT

AB. BUILD RESULT

AC. MANUAL FIREBASE CONFIGURATION REQUIRED

AD. MANUAL BACKEND CONFIGURATION REQUIRED

AE. REMAINING FUTURE WORK

---

# 152. MOST IMPORTANT IMPLEMENTATION RULE

#--------------------------------------------------

WORK IN THIS ORDER:

AUDIT
→ ARCHITECTURE
→ FOUNDATION
→ AUTH
→ PROFILE
→ SHOP SETUP
→ HOME
→ PRODUCTS
→ BARCODE
→ INVENTORY
→ PRICING
→ OFFERS
→ IMPORT
→ POS
→ REPORTS
→ NOTIFICATIONS
→ SETTINGS
→ SUPPORT
→ SYSTEM STATES
→ TESTING
→ PERFORMANCE
→ RELEASE

After EACH PHASE:

1. Run analyzer
2. Run relevant tests
3. Verify navigation
4. Verify state transitions
5. Verify API mapping
6. Fix errors
7. Then continue

NEVER accumulate large numbers of untested changes.

---

# 153. FINAL PRINCIPLE

#--------------------------------------------------

The Shopkeeper App must feel like ONE connected system:

LOGIN
↓
PROFILE
↓
SHOP
↓
DASHBOARD
↓
PRODUCTS
↓
BARCODE / MANUAL / IMPORT
↓
INVENTORY
↓
PRICE
↓
OFFERS
↓
REPORTS
↓
PROFILE / SETTINGS
↓
SUPPORT / LOGOUT

Every feature must connect logically.

Every state must be handled.

Every data mutation must have feedback.

Every backend dependency must have an error state.

Every important permission must have a fallback.

Every authenticated route must be protected.

Every important piece of data must have one source of truth.

Do not optimize for number of screens.

Optimize for:

CORRECT FLOW
+
STABLE STATE
+
CLEAN ARCHITECTURE
+
REAL API INTEGRATION
+
PRODUCTION QUALITY
+
MAINTAINABILITY
+
LOW BUG RISK

END OF MASTER PROMPT
