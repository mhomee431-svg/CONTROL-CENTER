# MASTER PROMPT

# HYPERLOCAL PRODUCT DISCOVERY PLATFORM

# CUSTOMER FLUTTER APP — COMPLETE FRONTEND IMPLEMENTATION 0→100%

You are a senior Flutter architect, mobile UI/UX engineer, application architect, state-management engineer, API integration engineer, Firebase engineer, Maps/location engineer, accessibility engineer, performance engineer, QA engineer, and release engineer.

You are working ONLY on the:

CUSTOMER FLUTTER APP

for my existing:

HYPERLOCAL PRODUCT DISCOVERY PLATFORM

This is an existing application.

Your job is NOT to blindly rebuild it.

Your job is to:

AUDIT
→ UNDERSTAND
→ PRESERVE WORKING CODE
→ FIX PROBLEMS
→ COMPLETE MISSING FEATURES
→ CONNECT REAL APIs
→ IMPROVE ARCHITECTURE
→ TEST
→ VERIFY
→ DELIVER A STABLE PRODUCTION-READY CUSTOMER APP

==================================================

# 1. PRODUCT PURPOSE

==================================================

Core product promise:

"Search any product. Instantly know which nearby shop has it, at what price, whether it is available, and how far the shop is."

Customer flow:

Search Product
→ Understand Product
→ Find Nearby Shops
→ Compare Price
→ Check Availability
→ Check Distance
→ Check Rating
→ View Shop
→ Get Directions
→ Visit Physical Shop
→ Purchase Offline

IMPORTANT:

This is a LOCAL DISCOVERY PLATFORM.

This is NOT:

- grocery delivery
- general food delivery
- home delivery marketplace
- normal e-commerce checkout platform

The customer normally completes purchase OFFLINE at the physical shop.

==================================================

# 2. CUSTOMER APP RESPONSIBILITY

==================================================

The Customer App must allow customers to:

- discover products
- search products
- discover nearby shops
- compare prices
- see availability
- see freshness of availability data
- compare distance
- see ratings
- view shop information
- view product information
- view maps
- get directions
- save products
- save shops
- maintain search history
- see notifications
- manage profile
- manage saved addresses
- manage location preferences
- manage notification preferences
- contact support
- manage privacy/settings
- logout/delete account where supported

==================================================

# 3. APPROVED BUSINESS CATEGORIES

==================================================

Only use these approved categories:

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

DO NOT add:

- Grocery
- General Food

Restaurants are allowed as a business category.

Restaurant discovery must NOT automatically become food delivery.

Transport / Personal Transport / Personal Travel are service-oriented categories and must use appropriate profile/details rather than pretending they are normal physical products.

Do not create multiple independent category lists.

ONE source of truth.

==================================================

# 4. PRODUCT SEARCH PRINCIPLE

==================================================

Product discovery should primarily understand:

PRODUCT NAME
+
BRAND
+
CATEGORY
+
VARIANT
+
IDENTIFIER/BARCODE WHERE SUPPORTED

Do NOT build frontend logic that assumes detailed material/specification understanding is required for normal product matching.

Examples:

"Dove Shampoo 650ml"
"Colgate Toothpaste"
"Bosch Drill"
"NCERT Class 10 Book"

Search should be optimized primarily around real product naming.

==================================================

# 5. CURRENT AUTHENTICATION

==================================================

CUSTOMER AUTHENTICATION:

Firebase Phone Authentication / OTP

Flow:

Customer Flutter App
        ↓
Phone Number
        ↓
Firebase OTP
        ↓
Firebase Authentication
        ↓
Firebase ID Token
        ↓
FastAPI
        ↓
Backend Verification
        ↓
Application Customer
        ↓
Customer App Session

Firebase = authentication

FastAPI = authorization/application access

PostgreSQL/backend = application source of truth

DO NOT create a second custom authentication system.

DO NOT create a second OTP provider unless explicitly required by backend architecture.

==================================================

# 6. OTP UX

==================================================

Support:

Enter mobile number
→ Send OTP
→ OTP screen
→ 6-digit OTP
→ verification
→ authenticated state

Handle:

- invalid OTP
- expired OTP
- wrong OTP
- resend
- resend timer
- network failure
- Firebase failure
- cancelled flow
- session expired

Never expose technical Firebase errors directly.

==================================================

# 7. OTP SECURITY

==================================================

Never store:

OTP
Firebase Admin credentials
AWS secrets
database password

in Flutter.

Firebase handles authentication.

Backend must verify the ID token.

Client must never decide its own authentication authority.

==================================================

# 8. APP STARTUP

==================================================

Startup flow:

App Launch
 ↓
Firebase Initialization
 ↓
Load Configuration
 ↓
Check Authentication State
 ↓
Check Customer Session
 ↓
Check Backend Profile
 ↓
Determine Route

Possible routes:

Unauthenticated
→ Onboarding/Login

Authenticated + profile incomplete
→ Customer Profile

Authenticated + profile complete
→ Home

Suspended/blocked
→ Account Status

Initialization failure
→ Retry screen

Avoid route flickering.

Use a controlled initialization state.

==================================================

# 9. ONBOARDING

==================================================

Create/use onboarding flow:

Screen 1:
Welcome

Screen 2:
Search Nearby Products

Screen 3:
Compare Price & Availability

Screen 4:
Find Shop & Get Directions

Screen 5:
Get Started

Keep onboarding simple.

Do NOT force unnecessary permission requests during onboarding.

Location permission should be requested when its purpose is clear, or through a clear onboarding step if the existing UX intentionally does this.

==================================================

# 10. WELCOME SCREEN

==================================================

Brand:

HyperLocal

Subtitle:

Find Products Nearby

Core visual:

local shop
+
location pin
+
search concept

Primary CTA:

Get Started

Secondary:

Login / Continue

==================================================

# 11. CUSTOMER LOGIN

==================================================

Title:

Welcome Back

Fields:

Mobile Number

CTA:

Continue

Then:

OTP verification

Do not show password unless existing backend explicitly requires it.

==================================================

# 12. CUSTOMER REGISTRATION

==================================================

After successful first authentication, collect minimal profile information.

Possible:

Full Name
Email optional
Preferred location/address optional

Avoid unnecessary profile fields.

Do not ask for information that the discovery experience does not actually require.

==================================================

# 13. CUSTOMER PROFILE

==================================================

Profile should support:

Full Name
Mobile
Email if available
Profile image if supported
Saved addresses
Notification settings
App settings
Privacy
Help
Terms
Logout
Delete account if backend supports it

Do not expose internal IDs.

==================================================

# 14. LOCATION SYSTEM

==================================================

Location is a core feature.

Support:

Current Location
Manual Location
Map Selection
Saved Addresses
Recent Locations

Use location permission only when needed.

Handle:

permission granted
permission denied
permanently denied
GPS disabled
poor accuracy
network unavailable

Never claim 100% GPS accuracy.

==================================================

# 15. LOCATION ACCURACY

==================================================

Customer location should include:

latitude
longitude
accuracy
timestamp

Use the backend's authoritative location/distance calculations.

Frontend must not pretend that a location is exact when the device reports uncertainty.

==================================================

# 16. LOCATION SCREEN

==================================================

Title:

Find Products Around You

Options:

Use Current Location
Choose on Map
Enter Area/Address
Choose Saved Address

Show map preview where appropriate.

Primary CTA:

Continue

==================================================

# 17. SAVED ADDRESSES

==================================================

Customer can:

Add Address
Edit Address
Delete Address
Select Default Address

Potential labels:

Home
Work
Other

Do not assume these labels must exist if backend model does not support them.

==================================================

# 18. HOME SCREEN

==================================================

Home is the central discovery screen.

Header:

Location
Profile

Main:

Search bar

Examples:

Search products, brands...

Sections:

Popular Categories
Nearby Shops
Recent Searches
Popular/Trending Products if backend supports
Latest Offers if backend supports
Recently Viewed

Do not render fake sections when backend has no data.

==================================================

# 19. HOME PERSONALIZATION

==================================================

When customer has history/location:

Use actual data to personalize.

Examples:

Recent searches
Recently viewed
Saved shops
Saved products
Nearby discovery

For new users:

show general discovery.

Do not generate fake personalized information.

==================================================

# 20. SEARCH EXPERIENCE

==================================================

Search must feel extremely fast.

Support:

Product name
Brand
Category
Variant
Barcode where supported

Search bar:

debounce input
clear button
loading state
suggestions
recent searches

Do not call backend for every character without debounce.

==================================================

# 21. SEARCH SUGGESTIONS

==================================================

While typing show:

Product suggestions
Brand suggestions
Category suggestions
Recent searches

Examples:

Dove Shampoo
Dove Body Wash
Dove Soap
Dove Conditioner

Allow:

tap suggestion
submit keyboard search
clear search

==================================================

# 22. RECENT SEARCHES

==================================================

Store/show recent searches according to backend/local design.

Features:

Recent Searches
Clear One
Clear All

Do not expose sensitive information unnecessarily.

==================================================

# 23. SEARCH RESULT FLOW

==================================================

Search:

"Dove Shampoo 650ml"

Flow:

Search Query
 ↓
Backend Search
 ↓
Product Understanding
 ↓
Matching Product
 ↓
Nearby Shop Search
 ↓
Results
 ↓
Filters/Sort
 ↓
Product/Shop Detail

==================================================

# 24. SEARCH RESULTS SCREEN

==================================================

Header:

Search Results for "Dove Shampoo"

Show:

matched product
+
nearby shops

Each result card can include:

Shop Name
Price
Availability
Distance
Rating
Freshness
Offer
Open/Closed where available

Primary CTA:

View Shop

Optional:

View Product

==================================================

# 25. RESULT SORTING

==================================================

Support where backend supports:

Distance
Price
Rating
Relevance
Availability
Offers

Default sort should be defined centrally and not separately in multiple screens.

==================================================

# 26. RESULT FILTERS

==================================================

Filters may include:

Distance
Price Range
Availability
Rating
Offers
Open Now
Category
Brand

Do not expose filters whose backend functionality does not exist.

==================================================

# 27. FILTER UX

==================================================

Use:

Filter Sheet

with:

Apply
Reset

Preserve selected values while browsing.

Do not reset everything unexpectedly when navigating back.

==================================================

# 28. PRICE COMPARISON

==================================================

Customer should be able to understand:

Shop A
₹248

Shop B
₹253

Shop C
₹260

with:

distance
availability
rating

Do not label any shop as "best" through arbitrary frontend ranking.

Present factual sortable/filterable data.

==================================================

# 29. AVAILABILITY

==================================================

Show clear statuses:

IN STOCK
LOW STOCK
OUT OF STOCK
UNKNOWN

Use backend-controlled availability.

Do not infer inventory truth from UI state.

==================================================

# 30. INVENTORY FRESHNESS

==================================================

Show where backend supplies it:

Updated 5 min ago
Updated today
Updated yesterday
Stale
Unknown

Customer should understand that availability can change.

Do NOT guarantee that an item will still be in stock when the customer arrives.

==================================================

# 31. PRODUCT DETAILS

==================================================

Product detail page:

Product Image
Product Name
Brand
Category
Variant
MRP
Current Price
Offer
Availability
Last Updated/Freshness

Sections:

Product Information
Available Nearby Shops
Price Comparison
Offers

==================================================

# 32. PRODUCT DETAILS — NEARBY SHOPS

==================================================

Show:

Shop Name
Price
Availability
Distance
Rating
Open/Closed

CTA:

View Shop

Another optional CTA:

Directions

Do not create a purchase/cart flow.

==================================================

# 33. PRODUCT IMAGE HANDLING

==================================================

Handle:

loading
loaded
missing
broken
placeholder

Do not crash when image URL is missing.

Use efficient image loading/caching.

Do not load full-resolution assets unnecessarily.

==================================================

# 34. BARCODE SEARCH — CUSTOMER

==================================================

Where supported, optionally allow:

Scan Barcode

Flow:

Camera Permission
 ↓
Barcode Scan
 ↓
Identify Product
 ↓
Search Nearby Shops

Do not create product data from a barcode on the frontend.

Barcode lookup remains backend-driven.

If this feature is not yet supported by backend:

hide/disable it gracefully.

==================================================

# 35. BARCODE EDGE CASES

==================================================

Handle:

camera denied
invalid barcode
unsupported barcode
barcode not found
multiple results
network error
server error

Fallback:

Manual Search

==================================================

# 36. SHOP PROFILE

==================================================

Shop Profile should show:

Shop Image
Shop Name
Category
Rating
Review count if backend supports it
Verification state if backend supports it
Address
Distance
Open/Closed
Opening Hours
Contact
Description
Services/categories

Actions:

Call
Directions
Share
Save Shop

Only show actions when data/capability exists.

==================================================

# 37. SHOP PROFILE — CONTACT

==================================================

Call action:

Use platform phone intent.

Do not expose private contact data that backend does not intend customers to see.

==================================================

# 38. SHOP PROFILE — DIRECTIONS

==================================================

Directions flow:

Current Location
+
Shop Location
 ↓
Map
 ↓
Route / External Navigation

Support map marker.

Use Google Maps integration where the project has selected Google Maps.

Google's Flutter Maps integration supports map markers and location visualization; keep map behavior behind a service abstraction so the app does not spread map SDK details across features.

Do not implement an unnecessary custom navigation engine.

==================================================

# 39. MAP SCREEN

==================================================

Map should support:

customer location
shop marker
selected shop
zoom
recenter
route/directions action

Handle:

location unavailable
map loading
map error
API/key error
network failure

==================================================

# 40. MULTIPLE SHOP MARKERS

==================================================

When multiple nearby shops are shown:

Use efficient markers.

If many markers exist:

use clustering or another scalable map strategy supported by the chosen map implementation.

Do not render hundreds of heavy widgets over the map.

==================================================

# 41. SHOP HOURS

==================================================

Show:

Open
Closed
Opening Soon
Closing Soon

where backend provides enough data.

Do not calculate business hours incorrectly in multiple frontend screens.

Centralize formatting.

==================================================

# 42. RATINGS

==================================================

Display ratings only when provided.

Potential:

4.3 ★
128 ratings

Do not manufacture ratings.

Do not calculate a new ranking in Flutter from partial data unless backend contract explicitly defines it.

==================================================

# 43. FAVORITES

==================================================

Customer can save:

Products
Shops

Features:

Save
Unsave
Favorites list

Handle:

authenticated user
unauthenticated user

If authentication is required to save:

show a clean sign-in prompt rather than silently failing.

==================================================

# 44. FAVORITES SCREEN

==================================================

Tabs:

Saved Products
Saved Shops

Product card:

Product
Price
Availability

Shop card:

Shop
Distance
Rating
Status

Provide:

Remove
Open

==================================================

# 45. SEARCH HISTORY

==================================================

History can contain:

Search query
Date
Recent result/context where backend provides it

Actions:

Open
Delete
Clear All

Do not treat history as purchase history.

==================================================

# 46. RECENTLY VIEWED

==================================================

Where supported:

Products
Shops

Allow:

Open
Clear

Do not claim customer purchased something just because they viewed it.

==================================================

# 47. NOTIFICATIONS

==================================================

Use Firebase Cloud Messaging for push notifications where backend is configured.

Potential categories:

Price Drops
Offers
Saved Product Updates
Shop Updates
Availability Updates
System Messages

FCM has different handling for foreground, background, and terminated states; implement all applicable app-state pathways and notification-tap handling.

==================================================

# 48. NOTIFICATION PERMISSION

==================================================

Request permission at an appropriate time.

Do not block the core product-discovery experience if notification permission is denied.

On Android 13+, notifications require runtime permission.

==================================================

# 49. NOTIFICATION DEEP LINK

==================================================

Notification examples:

Price Drop
→ Product Details

Shop Update
→ Shop Profile

Offer
→ Product/Shop

Availability
→ Product Result

System Message
→ Notification Detail

Do not trust an arbitrary route from notification data.

Validate supported notification types.

==================================================

# 50. FOREGROUND NOTIFICATION

#--------------------------------------------------

When notification arrives while app is open:

show an appropriate in-app notification/banner/snackbar/dialog according to UX.

Do not interrupt the user unnecessarily.

==================================================

# 51. BACKGROUND / TERMINATED NOTIFICATION

#--------------------------------------------------

Handle:

background tap
terminated-state tap
initial notification

Do not lose navigation context after opening the app.

==================================================

# 52. CUSTOMER ACCOUNT

#--------------------------------------------------

Account screen:

Profile
Saved Products
Saved Shops
Search History
Saved Addresses
Notifications
Settings
Help
Privacy
Terms
Logout

==================================================

# 53. SETTINGS

#--------------------------------------------------

Settings should logically include:

Account
Notifications
Location
Privacy
Language
Appearance if supported
Help & Support
Terms
Privacy Policy
About
Logout
Delete Account if backend supports

==================================================

# 54. NOTIFICATION SETTINGS

#--------------------------------------------------

Possible toggles:

Offers
Price Updates
Availability Updates
Shop Updates
System Notifications

Do not create settings that backend does not support.

==================================================

# 55. LOCATION SETTINGS

#--------------------------------------------------

Show:

Current Location
Default Address
Location Permission Status

Provide:

Use Current Location
Manage Addresses

==================================================

# 56. PRIVACY

#--------------------------------------------------

Include:

Privacy Policy
Data use explanation
Location usage information
Notification preferences
Account deletion

Do not write misleading privacy claims.

==================================================

# 57. DELETE ACCOUNT

#--------------------------------------------------

Only implement if backend supports it.

Flow:

Delete Account
→ Explain impact
→ Confirm
→ Re-authenticate if required
→ Backend request
→ Firebase logout
→ Clear local session
→ Return to entry screen

Do not perform destructive deletion only in Flutter.

==================================================

# 58. HELP & SUPPORT

#--------------------------------------------------

Support section:

FAQ
Contact Support
Report Issue
Terms & Conditions

Report Issue:

Category
Description
Optional attachment if backend supports

Handle:

submitted
failed
success

==================================================

# 59. OFFLINE EXPERIENCE

#--------------------------------------------------

Detect:

Online
Offline
Reconnecting

When offline:

show clear status

Allow safe cached data where implemented.

DO NOT show stale data as live.

DO NOT tell customer:

"Available"

when the app is merely displaying old cached data.

Use:

"Last updated..."

where appropriate.

==================================================

# 60. NETWORK FAILURE

#--------------------------------------------------

Handle:

timeout
no internet
server unavailable
partial network failure

Show:

Retry

Do not trap the customer.

==================================================

# 61. API ERROR MAPPING

#--------------------------------------------------

Map backend status codes:

401
→ session/authentication issue

403
→ access denied

404
→ unavailable/not found

409
→ conflict

422
→ validation

429
→ too many requests

500+
→ server issue

Use readable messages.

Never show stack traces.

==================================================

# 62. API CLIENT

#--------------------------------------------------

Use ONE shared API client.

Responsibilities:

base URL
authentication token
headers
timeouts
request IDs
status handling
safe retry behavior
logging in development

Do not create separate API clients per screen.

==================================================

# 63. AUTH TOKEN HANDLING

#--------------------------------------------------

Use Firebase ID token for backend requests.

When necessary:

refresh token safely.

Never store tokens in plain application state longer than needed.

Do not hardcode credentials.

==================================================

# 64. API RESPONSE MODELS

#--------------------------------------------------

Use typed models.

Do not keep raw dynamic JSON throughout the UI.

Support:

nullable fields
optional fields
unknown enum values
API version changes

Gracefully handle missing fields.

==================================================

# 65. FEATURE ARCHITECTURE

#--------------------------------------------------

Recommended:

lib/
  app/
    app.dart
    router/
    theme/
    config/

  core/
    auth/
    network/
    location/
    maps/
    storage/
    connectivity/
    notifications/
    permissions/
    errors/
    constants/
    utils/
    widgets/

  features/
    authentication/
    onboarding/
    home/
    search/
    search_results/
    product_details/
    shops/
    map/
    favorites/
    history/
    notifications/
    location/
    profile/
    settings/
    support/

  main.dart

Use existing sound architecture where present.

Do NOT force this structure if current code is already clean.

==================================================

# 66. FLUTTER ARCHITECTURE

#--------------------------------------------------

Preferred logical structure:

View
 ↓
ViewModel / State Controller
 ↓
Repository
 ↓
Service / API

Optional:

ViewModel
 ↓
Use Case
 ↓
Repository

Only introduce use-cases when complexity/reuse justifies them.

Flutter's current architecture guidance explicitly emphasizes Views, ViewModels, Repositories and Services, with repositories serving as sources of truth and services isolating external data sources.

==================================================

# 67. VIEW RULE

#--------------------------------------------------

Views should contain:

layout
simple display decisions
animation
basic routing actions

Views should NOT contain:

database logic
Firebase backend verification logic
large business logic
complex API transformations

==================================================

# 68. VIEWMODEL RULE

#--------------------------------------------------

ViewModels manage:

UI state
commands
loading
error
filter state
search state
pagination state
mutation state

Avoid conflicting boolean states.

Prefer explicit state models.

==================================================

# 69. REPOSITORY RULE

#--------------------------------------------------

Repositories own:

cached application data
API data
retry
refresh
mapping
data source coordination

Potential repositories:

AuthRepository
CustomerProfileRepository
LocationRepository
SearchRepository
ProductRepository
ShopRepository
SavedItemsRepository
HistoryRepository
NotificationRepository
SupportRepository

Create only where justified.

==================================================

# 70. SERVICE RULE

#--------------------------------------------------

Services wrap external systems:

Firebase Auth
Firebase Messaging
REST API
Location plugin
Maps plugin
Local file/device APIs

Services should not become giant business-logic containers.

==================================================

# 71. STATE MANAGEMENT

#--------------------------------------------------

Use the existing project state-management approach.

If existing state management is sound:

KEEP IT.

Do not migrate the entire app to another framework without a real architectural reason.

Possible conceptual states:

Initial
Loading
Loaded
Empty
Refreshing
Saving
Success
Error

==================================================

# 72. SINGLE SOURCE OF TRUTH

#--------------------------------------------------

Avoid:

searchResultsA
searchResultsB

productCache1
productCache2

shopListCopy

unless there is a deliberate repository/cache architecture.

One logical source of truth per domain.

==================================================

# 73. SEARCH STATE

#--------------------------------------------------

Search state must preserve:

query
suggestions
results
filters
sort
pagination
loading
error

When returning from Product Details:

preserve query/filter/sort where appropriate.

==================================================

# 74. RESULT PAGINATION

#--------------------------------------------------

Search results may be large.

Use backend pagination.

Prefer cursor/keyset pagination when backend supports it.

Never load thousands of shops/products at once.

==================================================

# 75. PRODUCT LIST PERFORMANCE

#--------------------------------------------------

Use efficient lists.

Avoid:

nested unnecessary scroll views
large rebuild areas
heavy widgets in every list row

Use lazy rendering.

==================================================

# 76. MAP PERFORMANCE

#--------------------------------------------------

Avoid creating extremely heavy marker/widget trees.

Optimize:

markers
images
location updates
route requests

Do not repeatedly request location when the user has not moved meaningfully.

==================================================

# 77. IMAGE PERFORMANCE

#--------------------------------------------------

Use:

appropriate image sizes
cache
placeholders
error widgets
lazy loading

Do not download original high-resolution images everywhere.

==================================================

# 78. SEARCH DEBOUNCE

#--------------------------------------------------

Debounce search input.

Example concept:

user typing
→ wait a short period
→ request

Cancel obsolete queries.

If response for older query arrives late:

do not overwrite newer results.

==================================================

# 79. RACE CONDITIONS

#--------------------------------------------------

Search:

"Dove"

then immediately:

"Dove Shampoo"

The response for "Dove" must not overwrite the newer query.

Implement request/version protection.

==================================================

# 80. REFRESH

#--------------------------------------------------

Support pull-to-refresh where useful.

After mutation:

update affected state where possible.

Do not reload the entire app unnecessarily.

==================================================

# 81. DEEP LINKING

#--------------------------------------------------

Prepare routes for:

Product
Shop
Search
Offer
Notification

When opening a deep link:

validate:
entity exists
entity available
user auth state
required context

Fallback gracefully if content no longer exists.

==================================================

# 82. SEARCH SHARING

#--------------------------------------------------

Where appropriate support:

Share Product
Share Shop

Use platform share functionality.

Never expose internal tokens or identifiers unintentionally.

==================================================

# 83. CUSTOMER SEARCH UX

#--------------------------------------------------

Search bar should support:

clear
voice/search extension point if later enabled
suggestions
recent search
loading

Do not implement voice AI unless explicitly supported.

Prepare an extension point only.

==================================================

# 84. CUSTOMER PRODUCT DISCOVERY LOGIC

#--------------------------------------------------

Product discovery should support:

Exact product name
Brand
Variant
Category
Barcode

Optional future:

semantic/AI search

Do not make AI a hard dependency of the core search experience.

Core search must work without AI.

==================================================

# 85. CATEGORY DISCOVERY

#--------------------------------------------------

Home/category browsing may show approved categories.

Category tap:

Category
→ relevant products
→ nearby shops

Do not use hardcoded category results.

==================================================

# 86. RESTAURANT CATEGORY

#--------------------------------------------------

Restaurants can appear as businesses.

Customer profile may show:

restaurant name
location
hours
rating
contact
available products/services when backend supports

Do NOT automatically create:

cart
food delivery
delivery rider
checkout

unless a separate future feature is explicitly added.

==================================================

# 87. TRANSPORT CATEGORY

#--------------------------------------------------

Transport businesses should be represented as service providers.

Possible future:

service details
availability
contact
booking/request

Only implement booking if backend contract exists.

Do not fake transport booking.

==================================================

# 88. PERSONAL TRANSPORT / TRAVEL

#--------------------------------------------------

Could support:

travel agency profile
transport provider profile
service information
contact
location
request/booking entry point where backend exists

Do not force product-style price/stock UI onto every service category.

Use capability-driven UI.

==================================================

# 89. CATEGORY-CAPABILITY MODEL

#--------------------------------------------------

Where appropriate, category/business type can determine available customer-facing information.

Example:

Physical product business:
price
stock
distance

Restaurant:
business details
hours
services/menu if supplied

Travel/service business:
service details
contact
location
booking/request if supported

Do NOT create one giant universal screen with irrelevant fields.

==================================================

# 90. SHOP DISCOVERY

#--------------------------------------------------

Customer can browse:

Nearby Shops
Category Shops
Saved Shops

Use:

distance
rating
status
availability where applicable

==================================================

# 91. SHOP CARD

#--------------------------------------------------

Card can include:

image
name
rating
distance
open/closed
verification
relevant price/availability where context exists

CTA:

View Shop

Avoid overloading the card.

==================================================

# 92. PRODUCT RESULT CARD

#--------------------------------------------------

Card:

Product image
Product name
Shop name
Price
Availability
Distance
Rating
Freshness

CTA:

View Shop

Optional:

View Product

==================================================

# 93. EMPTY STATES

#--------------------------------------------------

Every major list needs an empty state.

Examples:

No search results
No favorites
No saved shops
No history
No notifications
No nearby shops
No products

Each should provide a useful next action.

==================================================

# 94. SEARCH NO RESULT

#--------------------------------------------------

Show:

"No products found"

Suggestions:

Check spelling
Try another product
Search brand
Browse category
Change location

Do not present invented matches.

==================================================

# 95. LOCATION NO RESULT

#--------------------------------------------------

If no nearby result:

"No nearby shops found"

Actions:

Increase radius
Change location
Search another area

Only offer actions supported by backend.

==================================================

# 96. LOADING STATES

#--------------------------------------------------

Use proper loading UX:

Skeletons where helpful
Progress indicator for mutations
Map loading state
Search loading state

Avoid endless spinners.

==================================================

# 97. SKELETON RULE

#--------------------------------------------------

Skeleton must approximate actual layout.

Do not show generic full-screen spinners for every API call.

Use:

inline skeletons
list placeholders
button progress

where appropriate.

==================================================

# 98. ERROR STATES

#--------------------------------------------------

Reusable:

ErrorState
RetryButton

Screen-specific messages.

Example:

"Unable to load nearby shops."

Retry.

==================================================

# 99. SESSION EXPIRED

#--------------------------------------------------

When backend returns 401:

attempt safe refresh if applicable

If authentication is no longer valid:

clear protected state

route to Login

Do not loop infinitely.

==================================================

# 100. LOCAL DATA

#--------------------------------------------------

Possible local non-sensitive data:

theme preference
recent UI state
cached discovery data
search draft
selected filters
recent searches if intended local behavior

Do not store sensitive authentication secrets unnecessarily.

==================================================

# 101. SECURE STORAGE

#--------------------------------------------------

Use secure storage only for data that actually requires it.

Do not store:

AWS credentials
Firebase Admin credentials
database passwords

in the app.

==================================================

# 102. LOCATION PRIVACY

#--------------------------------------------------

Do not collect location continuously unless feature requires it.

For nearby discovery:

use location when needed.

Provide understandable location permission UX.

==================================================

# 103. CUSTOMER DATA PRIVACY

#--------------------------------------------------

Do not expose:

internal IDs
private shopkeeper information
backend-only metadata
tokens
secrets

Only display fields intended for customers.

==================================================

# 104. AUTHORIZED DATA ONLY

#--------------------------------------------------

Customer app must consume customer-authorized APIs.

Never assume a frontend-hidden field is secure.

Backend is authoritative.

==================================================

# 105. MATERIAL DESIGN

#--------------------------------------------------

Use Material 3 principles unless existing design system intentionally uses another compatible system.

Flutter supports Material 3 and provides adaptive components for modern Flutter apps.

Do not randomly mix Material 2 and Material 3 styling.

==================================================

# 106. VISUAL DESIGN SYSTEM

#--------------------------------------------------

Use the approved HyperLocal visual direction.

Primary:

Deep/Royal Blue
Electric Blue

Supporting:

White
Very Light Gray
Green success
Orange highlight
Red error
Dark text

Design language:

rounded cards
clear hierarchy
soft shadows
clean icons
comfortable spacing
large touch targets
mobile-first

==================================================

# 107. BRAND CONSISTENCY

#--------------------------------------------------

Use one centralized:

AppTheme
Colors
Typography
Spacing
Radius
Shadows
Button styles
Input styles

Do not define random per-screen colors.

==================================================

# 108. CUSTOMER BOTTOM NAVIGATION

#--------------------------------------------------

Recommended primary navigation:

Home
Search
Saved
Notifications
Profile

Map can be contextual rather than permanent bottom navigation.

Use the project's existing navigation architecture if already established.

==================================================

# 109. NAVIGATION RULE

#--------------------------------------------------

Every button must have an intentional result.

Examples:

Search
→ Search

Result card
→ Shop/Product

Directions
→ Map/External Navigation

Save
→ Saved

Notification
→ Relevant screen

Profile
→ Account

No dead buttons.

==================================================

# 110. BACK NAVIGATION

#--------------------------------------------------

Back behavior must be predictable.

Examples:

Product Detail
→ Search Results

Shop Profile
→ Search Results

Filter sheet
→ Results

Map
→ Shop/Product

Do not reset the entire customer journey unnecessarily.

==================================================

# 111. UNSAVED SEARCH/FORM STATE

#--------------------------------------------------

Preserve temporary state when useful.

Example:

Search
→ Filter
→ Product
→ Back

Keep:

query
filter
sort

where appropriate.

==================================================

# 112. ACCESSIBILITY

#--------------------------------------------------

Support:

semantic labels
touch targets
readable typography
adequate contrast
screen-reader usability
keyboard input on supported platforms

Do not communicate important information by color alone.

Flutter explicitly recommends considering different input methods and accessibility when designing adaptive applications.

==================================================

# 113. RESPONSIVE UI

#--------------------------------------------------

Support:

small phones
large phones
different aspect ratios
tablets where project scope requires
orientation changes where appropriate

Do not use fixed screen coordinates.

Use responsive/adaptive layouts.

==================================================

# 114. FONT SCALING

#--------------------------------------------------

Support larger system font sizes without:

overflow
clipping
hidden buttons
broken layouts

Test important screens with increased text scale.

==================================================

# 115. KEYBOARD

#--------------------------------------------------

Forms must handle:

keyboard
focus
next
done
dismiss
scroll-to-field

Search screen should keep keyboard behavior natural.

==================================================

# 116. TOUCH INTERACTION

#--------------------------------------------------

Provide clear:

pressed state
loading state
disabled state

Prevent accidental duplicate taps.

==================================================

# 117. NETWORK RETRY

#--------------------------------------------------

Retry should be safe.

Do not repeat a destructive or mutating operation blindly.

GET/search requests can generally retry according to timeout policy.

Mutations require idempotency awareness from backend contract.

==================================================

# 118. ANALYTICS

#--------------------------------------------------

If analytics is already part of the project:

track only useful product events.

Examples:

search_started
search_submitted
result_opened
product_viewed
shop_viewed
directions_clicked
saved_product
saved_shop

Do not collect sensitive information unnecessarily.

Never log OTP or tokens as analytics events.

==================================================

# 119. PERFORMANCE OBSERVABILITY

#--------------------------------------------------

Monitor:

startup
screen load
search latency from client perspective
image loading
map rendering
memory
crashes

Do not add excessive third-party SDKs.

==================================================

# 120. FIREBASE CONFIGURATION

#--------------------------------------------------

Inspect existing Firebase setup first.

If already configured:

reuse.

Do not recreate Firebase project/configuration.

Firebase Flutter Authentication requires Firebase client setup and enabled providers in Firebase Console.

==================================================

# 121. FIREBASE PHONE AUTH

#--------------------------------------------------

Verify:

Android configuration
SHA configuration
iOS configuration
Firebase Auth provider
real device behavior

Phone authentication has platform-specific requirements and should be tested on supported target devices.

==================================================

# 122. FIREBASE MESSAGING

#--------------------------------------------------

If notifications are part of backend scope:

FCM token flow:

Flutter
→ FCM token
→ FastAPI
→ stored server-side/device registration

Handle token refresh.

FCM documentation notes that registration tokens can change and that token refresh should be handled by the client.

==================================================

# 123. MAPS CONFIGURATION

#--------------------------------------------------

Inspect existing map implementation.

If Google Maps is selected:

keep SDK details behind a MapService abstraction.

Do not scatter SDK-specific logic throughout the application.

==================================================

# 124. LOCATION SERVICE

#--------------------------------------------------

Create/use one LocationService.

Responsibilities:

permission
current location
accuracy
location state

Do not duplicate location handling in multiple screens.

==================================================

# 125. CONNECTIVITY SERVICE

#--------------------------------------------------

Centralize connectivity state.

Features can observe:

Online
Offline
Reconnecting

==================================================

# 126. NOTIFICATION SERVICE

#--------------------------------------------------

Centralize FCM lifecycle.

Responsibilities:

token
permissions
foreground message
background message
notification tap
initial message
deep-link routing

Do not duplicate notification listeners in every screen.

==================================================

# 127. ERROR SYSTEM

#--------------------------------------------------

Create/use centralized:

AppException
Failure
ErrorMessageMapper

The UI should receive meaningful errors.

==================================================

# 128. FORM VALIDATORS

#--------------------------------------------------

Centralize reusable validators:

phone
email
search
pincode where used
name
address

Do not duplicate validation code everywhere.

==================================================

# 129. DATE/TIME

#--------------------------------------------------

Backend timestamps must be handled consistently.

Display local user-friendly times.

Do not mix UTC/local incorrectly.

==================================================

# 130. DISTANCE FORMAT

#--------------------------------------------------

Distance presentation should be consistent.

Examples:

850 m
1.2 km
4.8 km

Centralize formatting.

==================================================

# 131. CURRENCY

#--------------------------------------------------

Use INR where project market requires it.

Format:

₹248

Do not use floating-point arithmetic for financial transformations that can lose precision.

Prefer backend-provided monetary values or safe parsing/formatting.

==================================================

# 132. PRICE DISPLAY

#--------------------------------------------------

Where provided:

MRP
Selling Price
Offer Price

Clearly distinguish:

Original Price
Current Price
Offer

Do not falsely calculate discounts if backend does not supply valid values.

==================================================

# 133. SECURITY

#--------------------------------------------------

Never:

store backend secrets
hardcode AWS keys
hardcode database passwords
store Firebase Admin private keys
connect directly to PostgreSQL
trust client-side authorization
trust arbitrary shop IDs for protected operations

==================================================

# 134. API SECURITY

#--------------------------------------------------

All protected calls:

Firebase Token
→ FastAPI
→ verified backend identity

Do not send sensitive data unnecessarily.

==================================================

# 135. CUSTOMER ACCOUNT SWITCHING

#--------------------------------------------------

Do not build multiple customer profiles/accounts unless backend explicitly supports it.

One authenticated customer session at a time.

==================================================

# 136. LOGOUT

#--------------------------------------------------

Flow:

Profile
→ Logout
→ Confirm
→ Firebase signOut
→ clear customer session state
→ Login/Welcome

Do not leave authenticated customer data exposed after logout.

==================================================

# 137. ACCOUNT DELETION

#--------------------------------------------------

Only when backend endpoint exists.

Clear:

Firebase session
local customer session
cached protected data
saved local state associated with account

Do not delete backend data locally and pretend account was deleted.

==================================================

# 138. FEATURE CAPABILITIES

#--------------------------------------------------

Frontend must support backend capability flags where necessary.

Example:

canSave
canViewRatings
canShowOffers
canUseBarcode
canOpenDirections
canContactShop

Do not hardcode entitlement/availability logic in many screens.

==================================================

# 139. FUTURE AI SEARCH

#--------------------------------------------------

Prepare extension point for future:

AI/semantic search
voice search
image search

BUT:

Core product search must work without AI.

Do not add unnecessary AI dependency to MVP.

==================================================

# 140. FUTURE SMART RECOMMENDATIONS

#--------------------------------------------------

Possible future:

Recommended Products
Nearby Popular
Frequently Searched
Personalized Discovery

Only show when backend provides real data.

==================================================

# 141. FUTURE OFFERS

#--------------------------------------------------

Price drops
Offers
Saved product changes

These should plug into notifications and product/shop screens later.

Do not build a separate duplicate notification system.

==================================================

# 142. NO E-COMMERCE CHECKOUT

#--------------------------------------------------

Do NOT implement:

cart
checkout
online payment
home delivery
delivery address for shipping
order tracking

unless a future product decision explicitly adds them.

Core customer journey ends at:

Search
→ Discover
→ Compare
→ Directions
→ Visit Shop
→ Offline Purchase

==================================================

# 143. NO FAKE DATA

#--------------------------------------------------

Never use fake permanent data to make UI look complete.

Mock data may be used only:

during UI development/testing
and must be clearly isolated
and removable.

Production screens must use real backend data.

==================================================

# 144. NO DEAD ENDS

#--------------------------------------------------

Every screen must define:

loading
success
empty
error
back
retry
next action

Do not create a page that only looks good.

==================================================

# 145. UI COMPONENT SYSTEM

#--------------------------------------------------

Create reusable components where beneficial:

AppHeader
SearchBar
LocationHeader
ProductCard
ShopCard
PriceCard
AvailabilityBadge
RatingBadge
FilterSheet
SortSheet
EmptyState
ErrorState
LoadingState
MapPreview
FavoriteButton
ShareButton
PrimaryButton
SecondaryButton
SectionHeader
NotificationCard
AddressCard

Do not create hundreds of unnecessary components.

==================================================

# 146. SINGLE RESPONSIBILITY

#--------------------------------------------------

Each component should have one clear responsibility.

Do not create one giant:

HomeController

that handles:

auth
search
maps
notifications
favorites
profile
settings

Separate domains.

==================================================

# 147. HOME DATA

#--------------------------------------------------

Home may aggregate data from:

LocationRepository
Search/DiscoveryRepository
ShopRepository
SavedItemsRepository
NotificationRepository

But keep composition in the appropriate ViewModel/domain logic.

==================================================

# 148. SEARCH DATA

#--------------------------------------------------

Search repository should manage:

query
API
pagination
retry
mapping
cached recent results where appropriate

==================================================

# 149. SAVED DATA

#--------------------------------------------------

SavedItemsRepository handles:

saved products
saved shops

Do not duplicate favorite logic in every screen.

==================================================

# 150. NOTIFICATION DATA

#--------------------------------------------------

NotificationRepository manages:

list
read state
mark read
mark all read
pagination

FCM service handles delivery.

Separate transport from application state.

==================================================

# 151. CACHE STRATEGY

#--------------------------------------------------

Cache only useful read data.

Potential:

recent search
last known location preference
recent product data
recent shop data
home content where safe

Do not cache sensitive account data unnecessarily.

==================================================

# 152. CACHE INVALIDATION

#--------------------------------------------------

When backend data changes:

refresh affected state.

Do not display indefinite stale data.

==================================================

# 153. BACKEND SOURCE OF TRUTH

#--------------------------------------------------

Customer frontend is NOT source of truth for:

price
availability
distance
rating
verification
shop status

Backend is authoritative.

==================================================

# 154. SEARCH RESULT TRUST

#--------------------------------------------------

Display:

"Updated X minutes ago"

when provided.

Do not guarantee stock.

Use factual language:

"In stock"
based on backend data

not:

"Guaranteed available"

==================================================

# 155. CUSTOMER LOCATION + SHOP DISTANCE

#--------------------------------------------------

Distance should ideally come from backend or approved geo service.

Do not calculate inconsistent distances independently on different screens.

One formatting rule.

==================================================

# 156. SHOP VERIFICATION

#--------------------------------------------------

If shop is verified:

show backend-controlled verified indicator.

Do not assume all shops are verified.

Do not create fake verification badges.

==================================================

# 157. OPEN/CLOSED

#--------------------------------------------------

If business hours available:

calculate/display according to backend/timezone contract.

Do not duplicate business-hour rules in multiple widgets.

==================================================

# 158. CUSTOMER APP DATA FLOW

#--------------------------------------------------

MAIN FLOW:

Customer
 ↓
Firebase Phone Authentication
 ↓
Firebase ID Token
 ↓
FastAPI
 ↓
Customer Session
 ↓
Location
 ↓
Search
 ↓
Search Results
 ↓
Product
 ↓
Nearby Shops
 ↓
Shop Profile
 ↓
Directions
 ↓
Offline Visit/Purchase

Supporting:

Saved
History
Notifications
Profile
Settings
Support

==================================================

# 159. CUSTOMER SEARCH DATA FLOW

#--------------------------------------------------

Customer enters:

"Dove Shampoo 650ml"

↓

Search API

↓

Product Matching

↓

Nearby Shop Search

↓

Results:

Shop
Price
Availability
Distance
Rating
Freshness

↓

Product/Shop Details

↓

Directions

==================================================

# 160. CUSTOMER HOME DATA FLOW

#--------------------------------------------------

App startup
 ↓
Auth
 ↓
Location
 ↓
Home API
 ↓
Nearby products/shops
 ↓
Personalization from real data
 ↓
Render sections

==================================================

# 161. FAVORITES DATA FLOW

#--------------------------------------------------

Tap Save
 ↓
Auth check
 ↓
API
 ↓
Repository update
 ↓
UI state update
 ↓
Saved screen updated

If unauthenticated:

prompt login.

==================================================

# 162. NOTIFICATION DATA FLOW

#--------------------------------------------------

Backend
 ↓
FCM
 ↓
Device
 ↓
Foreground/Background/Terminated handling
 ↓
Notification tap
 ↓
Validate type
 ↓
Deep link
 ↓
Relevant screen

==================================================

# 163. MAP DATA FLOW

#--------------------------------------------------

Customer Location
+
Shop Location
 ↓
Map Service
 ↓
Map UI
 ↓
Directions Action

==================================================

# 164. TESTABILITY

#--------------------------------------------------

All major logic must be testable independently from widgets.

Flutter provides unit, widget and integration testing layers; use each for the appropriate confidence level.

==================================================

# 165. UNIT TESTS

#--------------------------------------------------

Test:

validators
formatters
search state
filter state
sorting state
mapping
distance formatting
price formatting
notification routing
auth state transitions

==================================================

# 166. WIDGET TESTS

#--------------------------------------------------

Test:

login
OTP
search
filter
result card
product detail
shop profile
favorite button
empty states
error states
settings

==================================================

# 167. INTEGRATION TESTS

#--------------------------------------------------

Test critical flows:

App startup
→ Auth
→ Location
→ Search
→ Results
→ Product
→ Shop
→ Directions

and:

Search
→ Save Product
→ Saved

and:

Notification
→ Deep Link
→ Product/Shop

Flutter's integration-test tooling is intended for testing complete app behavior across connected components.

==================================================

# 168. AUTH TEST CASES

#--------------------------------------------------

Test:

valid phone
invalid phone
OTP success
wrong OTP
expired OTP
resend
cancel
network failure
Firebase failure
session expiration
logout

==================================================

# 169. LOCATION TEST CASES

#--------------------------------------------------

Test:

permission granted
permission denied
permanent denial
GPS disabled
low accuracy
map selection
manual location
saved location

==================================================

# 170. SEARCH TEST CASES

#--------------------------------------------------

Test:

normal query
empty query
rapid typing
no results
network error
pagination
filter
sort
back navigation
old response race condition

==================================================

# 171. PRODUCT TEST CASES

#--------------------------------------------------

Test:

product exists
product missing
image missing
price missing
availability unknown
shop list empty
offer missing

==================================================

# 172. SHOP TEST CASES

#--------------------------------------------------

Test:

shop available
shop unavailable
missing image
missing hours
closed
open
directions
call
share
save

==================================================

# 173. FAVORITES TEST CASES

#--------------------------------------------------

Test:

save
unsave
duplicate tap
unauthenticated
network failure
already saved
removed item

==================================================

# 174. NOTIFICATION TEST CASES

#--------------------------------------------------

Test:

foreground
background
terminated
tap
invalid payload
unsupported notification type
deep-link target unavailable

==================================================

# 175. OFFLINE TEST CASES

#--------------------------------------------------

Test:

offline launch
offline search
cached data
reconnect
retry

Never show false success.

==================================================

# 176. UI QUALITY TEST

#--------------------------------------------------

Check:

no overflow
no clipped text
no broken keyboard
no tiny touch targets
no inconsistent padding
no inconsistent icons
no accidental scroll lock
no nested scroll problems

==================================================

# 177. PERFORMANCE QUALITY

#--------------------------------------------------

Check:

startup
list scrolling
search latency
map
images
memory
rebuilds
network calls

Avoid unnecessary rebuilds.

==================================================

# 178. MEMORY SAFETY

#--------------------------------------------------

Dispose:

controllers
listeners
streams
camera
map resources
subscriptions

Avoid duplicate subscriptions.

==================================================

# 179. CAMERA SAFETY

#--------------------------------------------------

If barcode scan exists:

initialize only when needed
release when leaving
handle app lifecycle
avoid background camera usage

==================================================

# 180. APP LIFECYCLE

#--------------------------------------------------

Handle:

foreground
background
resume

Refresh appropriate data after resume.

Do not blindly reload the entire application.

==================================================

# 181. ERROR LOGGING

#--------------------------------------------------

Development logs:

useful and structured

Production:

safe logs only

Never log:

OTP
Firebase ID token
private account data
credentials

==================================================

# 182. ENVIRONMENTS

#--------------------------------------------------

Support:

LOCAL
STAGING
PRODUCTION

Use centralized environment configuration.

Do not hardcode production API URL throughout the app.

==================================================

# 183. PACKAGE MANAGEMENT

#--------------------------------------------------

Before adding dependency:

check whether existing dependency solves the requirement.

Do not add packages unnecessarily.

Before replacing a package:

inspect current usage.

Avoid dependency sprawl.

==================================================

# 184. EXISTING PROJECT RULE

#--------------------------------------------------

Before modifying any file:

inspect usages.

Before deleting:

check:

routes
imports
providers
services
tests
API consumers
configuration

Do not delete working functionality blindly.

==================================================

# 185. DUPLICATE CODE RULE

#--------------------------------------------------

Search the whole repo before creating:

AuthService
SearchService
LocationService
MapService
ApiClient
Repository
Provider
ViewModel
Model
Widget

Do not create:

ApiClientV2
SearchServiceNew
LocationManager2
ProductRepositoryNew

without a real architecture reason.

==================================================

# 186. DEAD CODE CLEANUP

#--------------------------------------------------

Remove dead code only after proving:

unused
unreferenced
obsolete
safe to delete

Update imports after cleanup.

==================================================

# 187. MIGRATION RULE

#--------------------------------------------------

Do not perform giant rewrites.

Prefer:

small safe refactor
→ test
→ continue

==================================================

# 188. IMPLEMENTATION PHASE 1

#--------------------------------------------------

FULL AUDIT ONLY.

Inspect:

Flutter version
Dart version
existing architecture
Firebase
routing
state management
API layer
screens
repositories
services
theme
location
maps
notifications
storage
tests

Deliver:

CURRENT STATE REPORT

No large implementation yet.

==================================================

# 189. PHASE 2

#--------------------------------------------------

ARCHITECTURE CONTRACT

Define:

routes
state ownership
repositories
services
models
errors
theme
API integration
location
maps
notification flow

==================================================

# 190. PHASE 3

#--------------------------------------------------

APP FOUNDATION

Verify:

main
Firebase
configuration
routing
theme
dependency injection
error handling
connectivity

==================================================

# 191. PHASE 4

#--------------------------------------------------

AUTHENTICATION

Implement/verify:

Splash
Login
Phone number
OTP
Auth state
Backend session
Logout

==================================================

# 192. PHASE 5

#--------------------------------------------------

ONBOARDING + LOCATION

Implement:

Welcome
Location permission
Current location
Manual selection
Saved locations

==================================================

# 193. PHASE 6

#--------------------------------------------------

HOME

Implement:

Search
Categories
Nearby discovery
Recent searches
Saved/relevant sections

==================================================

# 194. PHASE 7

#--------------------------------------------------

SEARCH

Implement:

query
debounce
suggestions
history
search result
pagination
filter
sort
no result
errors

==================================================

# 195. PHASE 8

#--------------------------------------------------

PRODUCT

Implement:

Product Detail
images
price
availability
freshness
nearby shops
offers

==================================================

# 196. PHASE 9

#--------------------------------------------------

SHOP

Implement:

Shop Profile
rating
hours
contact
directions
share
save
map

==================================================

# 197. PHASE 10

#--------------------------------------------------

SAVED + HISTORY

Implement:

saved products
saved shops
search history
recently viewed where supported

==================================================

# 198. PHASE 11

#--------------------------------------------------

NOTIFICATIONS

Implement:

FCM
permission
token
foreground
background
terminated
deep links
read/unread

==================================================

# 199. PHASE 12

#--------------------------------------------------

PROFILE + SETTINGS

Implement:

profile
addresses
notification settings
location settings
privacy
terms
help
logout
delete account if supported

==================================================

# 200. PHASE 13

#--------------------------------------------------

SYSTEM STATES

Implement:

loading
empty
error
offline
retry
session expired
unauthorized
maintenance

==================================================

# 201. PHASE 14

#--------------------------------------------------

PERFORMANCE

Audit:

API calls
rebuilds
lists
images
maps
startup
memory

==================================================

# 202. PHASE 15

#--------------------------------------------------

ACCESSIBILITY + RESPONSIVENESS

Test:

small devices
large devices
font scaling
keyboard
screen readers
touch targets

==================================================

# 203. PHASE 16

#--------------------------------------------------

UNIT TESTS

==================================================

# 204. PHASE 17

#--------------------------------------------------

WIDGET TESTS

==================================================

# 205. PHASE 18

#--------------------------------------------------

INTEGRATION TESTS

==================================================

# 206. PHASE 19

#--------------------------------------------------

FINAL BUG FIX + HARDENING

Fix:

compile errors
analyzer errors
routing errors
state bugs
race conditions
overflow
memory leaks
broken API mappings
permission issues

==================================================

# 207. PHASE 20

#--------------------------------------------------

RELEASE VALIDATION

Run:

flutter analyze

flutter test

integration tests

formatting

build validation

Where environment allows:

Android debug
Android release
iOS validation

==================================================

# 208. NO-BREAK RULE

#--------------------------------------------------

A change is NOT complete until:

existing affected functionality
+
new functionality
+
navigation
+
state
+
API mapping
+
error handling

are verified.

==================================================

# 209. EVERY FEATURE CONTRACT

#--------------------------------------------------

For every feature answer:

1. Entry point?
2. Screen?
3. State?
4. API?
5. Loading?
6. Success?
7. Empty?
8. Error?
9. Retry?
10. Back behavior?
11. Offline behavior?
12. Permission requirement?
13. Auth requirement?
14. Deep link?
15. Analytics event if applicable?

If any critical answer is undefined:

resolve it before implementation.

==================================================

# 210. FINAL CUSTOMER NAVIGATION

#--------------------------------------------------

FINAL LOGICAL FLOW:

APP START
 ↓
AUTH CHECK
 ↓
ONBOARDING / LOGIN
 ↓
LOCATION
 ↓
HOME
 ↓
SEARCH
 ↓
SEARCH RESULTS
 ↓
PRODUCT DETAILS
 ↓
NEARBY SHOPS
 ↓
SHOP PROFILE
 ↓
MAP / DIRECTIONS
 ↓
VISIT PHYSICAL SHOP
 ↓
OFFLINE PURCHASE

Supporting:

HOME
├── Categories
├── Nearby Shops
├── Recent Searches
├── Offers where supported
└── Discovery

SAVED
├── Products
└── Shops

NOTIFICATIONS

PROFILE
├── Account
├── Addresses
├── Settings
├── Privacy
├── Help
└── Logout

==================================================

# 211. FINAL CUSTOMER DATA FLOW

#--------------------------------------------------

CUSTOMER FLUTTER APP
        |
        +---- Firebase Phone Authentication
        |
        ↓
     Firebase ID Token
        |
        ↓
      FASTAPI
        |
        +---- Search
        +---- Products
        +---- Shops
        +---- Location
        +---- Saved Items
        +---- History
        +---- Notifications
        +---- Customer Profile
        |
        ↓
   Backend / PostgreSQL
        |
        ↓
Authoritative Customer-facing Data

Maps:
Flutter
→ Map Service
→ Map Provider

Push:
Backend
→ FCM
→ Customer Device

==================================================

# 212. FINAL UI CONTRACT

#--------------------------------------------------

All screens must follow one consistent HyperLocal design language:

Deep Blue
+
Electric Blue
+
White
+
Light Gray
+
Green
+
Orange highlights

Use:

Material 3 compatible design
rounded cards
clear typography
consistent spacing
soft elevation
large touch targets
clean icons
minimal clutter
production-quality visual hierarchy

Do not create different designs for every feature.

==================================================

# 213. FINAL BUSINESS CONTRACT

#--------------------------------------------------

Customer sees:

PRODUCT
PRICE
AVAILABILITY
DISTANCE
RATING
SHOP
DIRECTIONS

Customer does NOT see internal:

database IDs
shopkeeper private details
backend secrets
technical error information
internal verification metadata

==================================================

# 214. FINAL PRODUCT PRINCIPLE

#--------------------------------------------------

The app must make this action extremely easy:

SEARCH
→ UNDERSTAND
→ COMPARE
→ FIND NEARBY
→ CHECK AVAILABILITY
→ CHECK PRICE
→ VIEW SHOP
→ GET DIRECTIONS
→ VISIT SHOP

Do not make the customer navigate through unnecessary screens to accomplish this.

==================================================

# 215. FINAL QUALITY GATE

#--------------------------------------------------

Do not declare the Customer App complete merely because all screens compile.

COMPLETE means:

[ ] Firebase initialization works
[ ] Phone authentication works
[ ] OTP flow works
[ ] Auth state works
[ ] Profile works
[ ] Location works
[ ] Home works
[ ] Search works
[ ] Search suggestions work
[ ] Search history works
[ ] Search results work
[ ] Filters work
[ ] Sorting works
[ ] Pagination works
[ ] Product details work
[ ] Nearby shops work
[ ] Shop profile works
[ ] Map works
[ ] Directions works
[ ] Save Product works
[ ] Save Shop works
[ ] Favorites works
[ ] Notifications work where backend exists
[ ] Notification deep links work
[ ] Account works
[ ] Settings work
[ ] Help works
[ ] Offline state works
[ ] Network errors work
[ ] Session expiry works
[ ] Permission handling works
[ ] Empty states work
[ ] Error states work
[ ] Loading states work
[ ] Accessibility checked
[ ] Responsive layout checked
[ ] No direct DB access
[ ] No secrets in Flutter
[ ] No duplicate architecture
[ ] No major dead code
[ ] No broken routes
[ ] No UI overflow
[ ] No obvious memory leaks
[ ] Analyzer passes
[ ] Unit tests pass
[ ] Widget tests pass
[ ] Integration tests pass where configured
[ ] Production build validated

==================================================

# 216. FINAL REPORT REQUIRED

#--------------------------------------------------

After every major phase provide:

1. What was inspected
2. What already existed
3. What was reused
4. What was changed
5. What was created
6. What was removed
7. API contracts used
8. Firebase changes
9. Maps changes
10. Notification changes
11. State-management changes
12. Route changes
13. Tests executed
14. Analyzer result
15. Build result
16. Remaining issues
17. Manual actions required

FINAL REPORT MUST ALSO INCLUDE:

A. FINAL FOLDER TREE

B. FINAL ROUTE MAP

C. SCREEN INVENTORY

D. FEATURE INVENTORY

E. AUTHENTICATION FLOW

F. LOCATION FLOW

G. SEARCH FLOW

H. PRODUCT FLOW

I. SHOP FLOW

J. MAP/DIRECTIONS FLOW

K. SAVED/HISTORY FLOW

L. NOTIFICATION FLOW

M. PROFILE/SETTINGS FLOW

N. ERROR/EMPTY/OFFLINE FLOW

O. API INTEGRATION MAP

P. FIREBASE INTEGRATION MAP

Q. TEST RESULTS

R. KNOWN LIMITATIONS

S. FUTURE EXTENSION POINTS

==================================================

# 217. ABSOLUTE DO-NOT RULES

#--------------------------------------------------

DO NOT:

- rebuild the entire project unnecessarily
- change working architecture without reason
- duplicate services
- duplicate repositories
- duplicate API clients
- duplicate models
- duplicate state managers
- hardcode production data
- hardcode secrets
- connect Flutter directly to PostgreSQL
- connect Flutter directly to private AWS storage using permanent credentials
- create fake API responses for production
- create fake ratings
- create fake availability
- create fake distance
- create fake sales/order data
- implement delivery
- implement e-commerce checkout
- add Grocery category
- add General Food category
- build unnecessary AI dependency
- add unnecessary dependencies
- create unnecessary microservices on frontend
- create dead-end screens
- create buttons with no defined behavior
- silently swallow errors
- silently claim failed mutations succeeded

==================================================

# 218. EXISTING CUSTOMER APP PROTECTION

#--------------------------------------------------

The existing Customer App may already contain many completed screens.

Therefore:

FIRST inspect.

THEN:

KEEP
→ if correct

IMPROVE
→ if buggy

COMPLETE
→ if incomplete

REFACTOR
→ if architecture is duplicated

DELETE
→ only when proven obsolete

Never rewrite working screens just to make the code look different.

==================================================

# 219. MASTER DEVELOPMENT LOOP

#--------------------------------------------------

For every phase:

AUDIT
 ↓
PLAN
 ↓
IMPLEMENT
 ↓
ANALYZE
 ↓
TEST
 ↓
RUN
 ↓
VERIFY
 ↓
FIX
 ↓
ONLY THEN CONTINUE

Never make a giant untested change.

==================================================

# 220. FINAL ARCHITECTURAL CONTRACT

#--------------------------------------------------

The final customer app should conceptually look like:

```
            CUSTOMER
                |
                ↓
         FLUTTER APP
                |
    +-----------+------------+
    |           |            |
  Auth       Location      FCM
    |           |            |
    +-----------+------------+
                |
                ↓
          FASTAPI API
                |
    +-----------+-----------+
    |           |           |
 Search      Products     Shops
    |           |           |
 Saved       History     Profile
                |
                ↓
          Backend Data
                |
                ↓
        PostgreSQL/PostGIS
```

Maps are handled through the chosen map provider/service.

Firebase handles authentication and push-messaging client functions.

FastAPI remains the API boundary.

Backend remains the authoritative source of customer-facing business data.

==================================================

# 221. FINAL PRODUCT EXPERIENCE

#--------------------------------------------------

The customer should feel:

FAST
CLEAR
TRUSTWORTHY
LOCAL
EASY

The most important action must remain:

"Find the product I need near me."

The app should minimize friction between:

SEARCH

and

PHYSICAL SHOP VISIT.

# ==================================================
END OF MASTER PROMPT

