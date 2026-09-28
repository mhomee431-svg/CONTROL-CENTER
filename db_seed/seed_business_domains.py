#!/usr/bin/env python
"""seed_business_domains.py -- Realistic catalog for the 11 approved business domains.

Specification: grocery / general food retail is OUT OF SCOPE.
Provides products for Pharmacy, Beauty, Furniture, Household, Sports,
Books, Automotive, Hardware, Restaurants, Transport, Personal Travel.
"""
from __future__ import annotations

import sys
from pathlib import Path

# Make the backend ``app`` package importable so the canonical category
# registry (the single source of truth for the 11 approved names/codes) can be
# imported here. Runs whether this file is executed directly
# (`python db_seed/seed_data.py`) or imported by the test suite.
_BACKEND_DIR = Path(__file__).resolve().parents[1] / "backend"
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from app.models.merchant_category import (  # noqa: E402
    MERCHANT_CATEGORY_NAMES,
    MerchantCategoryCode,
)

BUSINESS_DOMAIN_CATALOG = [
    # ── 1. PHARMACY & HEALTHCARE ────────────────────────────────────────────
    ("Pharmacy & Healthcare", [
        ("Paracetamol 650mg", "10 tabs", 22, 35, ["10 tabs", "20 tabs"]),
        ("Pain Relief Spray", "150 ml", 120, 180, ["150 ml"]),
        ("Digital Thermometer", "1 pc", 120, 250, ["1 pc"]),
        ("Blood Pressure Monitor", "1 pc", 1400, 2600, ["1 pc"]),
        ("Diabetes Test Strips", "50 strips", 600, 900, ["50 strips", "100 strips"]),
        ("Multivitamin Tablets", "30 tabs", 180, 320, ["30 tabs", "60 tabs"]),
        ("Omega-3 Fish Oil", "60 caps", 350, 550, ["60 caps"]),
        ("Cough Syrup", "150 ml", 85, 140, ["150 ml"]),
        ("Antacid Liquid", "170 ml", 90, 130, ["170 ml"]),
        ("First Aid Kit", "1 kit", 250, 450, ["1 kit"]),
        ("Hand Sanitizer", "500 ml", 85, 130, ["250 ml", "500 ml"]),
        ("Face Mask (N95)", "5 pack", 150, 250, ["5 pack", "20 pack"]),
        ("Whey Protein (Chocolate)", "1 kg", 1800, 2600, ["1 kg"]),
        ("ORS Sachets", "5 pc", 40, 65, ["5 pc", "20 pc"]),
    ]),
    # ── 2. BEAUTY & PERSONAL CARE ───────────────────────────────────────────
    ("Beauty & Personal Care", [
        ("Face Wash (Neem)", "150 ml", 120, 180, ["150 ml"]),
        ("Moisturizing Cream", "100 ml", 180, 280, ["100 ml"]),
        ("Hair Oil (Coconut)", "300 ml", 85, 140, ["200 ml", "300 ml"]),
        ("Herbal Shampoo", "340 ml", 160, 240, ["180 ml", "340 ml"]),
        ("Hair Conditioner", "200 ml", 140, 220, ["200 ml"]),
        ("Body Lotion", "400 ml", 180, 260, ["400 ml"]),
        ("Sunscreen SPF 50", "50 g", 320, 480, ["50 g"]),
        ("Lip Balm", "15 g", 90, 140, ["15 g"]),
        ("Kajal", "0.35 g", 120, 200, ["1 pc"]),
        ("Nail Polish", "9 ml", 90, 150, ["9 ml"]),
        ("Cold Cream", "100 g", 110, 170, ["100 g"]),
        ("Talcum Powder", "500 g", 130, 200, ["500 g"]),
    ]),
    # ── 3. FURNITURE & HOME CARE ────────────────────────────────────────────
    ("Furniture & Home Care", [
        ("Study Table", "1 pc", 3200, 5500, ["1 pc"]),
        ("Foldable Chair", "1 pc", 750, 1200, ["1 pc"]),
        ("Bookshelf (3 Tier)", "1 pc", 2800, 4200, ["1 pc"]),
        ("TV Stand", "1 pc", 3800, 6500, ["1 pc"]),
        ("Wooden Stool", "1 pc", 500, 850, ["1 pc"]),
        ("Cloth Wardrobe", "1 pc", 1800, 3200, ["1 pc"]),
        ("Air Mattress", "Queen", 1400, 2200, ["Queen"]),
        ("Pillow Set (2)", "2 pc", 450, 750, ["2 pc"]),
        ("Mosquito Net", "Double", 220, 380, ["Single", "Double"]),
        ("Door Mat", "1 pc", 120, 200, ["1 pc"]),
    ]),
    # ── 4. HOUSEHOLD GOODS ──────────────────────────────────────────────────
    ("Household Goods", [
        ("Pressure Cooker 5L", "1 pc", 1500, 2600, ["5 L", "3 L"]),
        ("Non-stick Frying Pan", "24 cm", 550, 900, ["24 cm"]),
        ("Steel Dinner Set (12)", "12 pc", 1200, 2200, ["12 pc"]),
        ("Water Bottle (1L)", "1 L", 150, 250, ["750 ml", "1 L"]),
        ("Tiffin Box", "3 layer", 380, 650, ["3 layer"]),
        ("Vacuum Flask", "1 L", 280, 450, ["1 L"]),
        ("Utensil Drainer", "1 pc", 180, 300, ["1 pc"]),
        ("Broom (Unbreakable)", "1 pc", 85, 140, ["1 pc"]),
        ("Bucket (Heavy Duty)", "10 L", 120, 190, ["10 L", "15 L"]),
        ("Storage Containers (4)", "4 pc", 350, 600, ["4 pc"]),
    ]),
    # ── 5. SPORTS, FITNESS & OUTDOOR ────────────────────────────────────────
    ("Sports, Fitness & Outdoor", [
        ("Cricket Bat", "Full Size", 700, 1500, ["Full Size"]),
        ("Football", "Size 4", 450, 800, ["Size 4", "Size 5"]),
        ("Yoga Mat", "6 mm", 350, 650, ["6 mm", "8 mm"]),
        ("Dumbbells (Pair 2kg)", "2 kg", 600, 1000, ["2 kg", "5 kg"]),
        ("Skipping Rope", "1 pc", 120, 220, ["1 pc"]),
        ("Badminton Racket", "1 pc", 350, 700, ["1 pc"]),
        ("Swimming Goggles", "1 pc", 180, 320, ["1 pc"]),
        ("Camping Tent (2 person)", "1 pc", 1800, 3200, ["2 person"]),
        ("Exercise Resistance Band", "1 pc", 220, 380, ["1 pc"]),
        ("Walking Shoes (Men)", "UK 9", 1200, 2500, ["UK 8", "UK 9", "UK 10"]),
    ]),
    # ── 6. BOOKS, MEDIA & STATIONERY ────────────────────────────────────────
    ("Books, Media & Stationery", [
        ("School Notebook", "172 pages", 45, 75, ["172 pages"]),
        ("Geometry Box", "1 pc", 120, 220, ["1 pc"]),
        ("Crayon Set (24)", "24 pc", 180, 280, ["12 pc", "24 pc"]),
        ("Sketch Pens (12)", "12 pc", 110, 190, ["12 pc"]),
        ("Exam Diary", "1 pc", 45, 80, ["1 pc"]),
        ("Story Book (Children)", "1 pc", 120, 220, ["1 pc"]),
        ("Hindi-English Dictionary", "1 pc", 160, 280, ["1 pc"]),
        ("Fountain Pen", "1 pc", 250, 450, ["1 pc"]),
        ("Printer Paper (REAM)", "500 sheets", 280, 380, ["500 sheets"]),
        ("Binder Clip (Box)", "100 pc", 70, 110, ["100 pc"]),
    ]),
    # ── 7. AUTOMOTIVE PARTS & TOOLS ─────────────────────────────────────────
    ("Automotive Parts & Tools", [
        ("Engine Oil 10W-40", "1 L", 320, 480, ["1 L"]),
        ("Air Filter", "Universal", 180, 350, ["Universal"]),
        ("Spark Plug", "1 pc", 90, 180, ["1 pc"]),
        ("Battery Maintainer", "1 pc", 800, 1400, ["1 pc"]),
        ("Car Vacuum Cleaner", "12 V", 1200, 2000, ["12 V"]),
        ("Wiper Blades (Set)", "2 pc", 250, 450, ["2 pc"]),
        ("Tyre Inflator", "12 V", 900, 1500, ["12 V"]),
        ("Reflector Tape (2m)", "2 m", 60, 95, ["2 m"]),
        ("Phone Holder for Car", "1 pc", 280, 450, ["1 pc"]),
        ("Car Shampoo", "500 ml", 160, 250, ["500 ml"]),
    ]),
    # ── 8. HARDWARE ─────────────────────────────────────────────────────────
    ("Hardware", [
        ("Hammer (300g)", "1 pc", 180, 320, ["1 pc"]),
        ("Screwdriver Set (8)", "8 pc", 250, 420, ["8 pc"]),
        ("Drill Machine", "650W", 2200, 3800, ["650 W"]),
        ("Door Handle Set", "2 pc", 350, 600, ["2 pc"]),
        ("Padlock (Heavy)", "1 pc", 150, 260, ["1 pc"]),
        ("Plumbing Tape (PTFE)", "10 m", 60, 95, ["10 m"]),
        ("Electrical Wire (14 AWG)", "15 m", 220, 350, ["15 m", "30 m"]),
        ("Switch Board (4 way)", "1 pc", 180, 300, ["1 pc"]),
        ("Wall Paint Brush (4 inch)", "1 pc", 110, 180, ["1 pc"]),
        ("Spirit Level", "24 inch", 190, 320, ["24 inch"]),
    ]),
    # ── 9. RESTAURANTS (discovery only) ─────────────────────────────────────
    ('Restaurants', [
        ('Chicken Biryani Thali', '1 plate', 160, 240, ['1 plate']),
        ('Paneer Tikka (8 pcs)', '8 pcs', 140, 220, ['8 pcs']),
        ('Dal Makhani + Naan Combo', '1 plate', 120, 190, ['1 plate']),
        ('Masala Dosa', '1 plate', 60, 110, ['1 plate']),
        ('Butter Chicken (Half)', 'half', 180, 280, ['Half', 'Full']),
        ('Veg Fried Rice', '1 plate', 90, 150, ['1 plate']),
        ('Gulab Jamun (4 pcs)', '4 pcs', 50, 90, ['4 pcs', '8 pcs']),
        ('Coffee Special', '1 cup', 40, 80, ['1 cup']),
        ('Family Thali (4 pcs)', '4 plates', 450, 650, ['4 plates']),
    ]),

    # ── 10. TRANSPORT ───────────────────────────────────────────────────────
    ('Transport', [
        ('Mini Truck Rental (per km)', '1 km', 28, 45, ['per km']),
        ('Tempo Pickup Rental', '1 trip', 1200, 2200, ['per trip']),
        ('Bike Taxi (per km)', '1 km', 8, 15, ['per km']),
        ('Auto Hire (per km)', '1 km', 12, 20, ['per km']),
        ('Car Rental (per day)', '1 day', 1600, 3200, ['per day']),
        ('Bus Booking (30 seats)', 'per trip', 4500, 7500, ['per trip']),
    ]),

    # ── 11. PERSONAL TRANSPORT & TRAVEL ────────────────────────────────────
    (MERCHANT_CATEGORY_NAMES[MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value], [
        ('City Tour Package', '1 day', 1500, 2800, ['1 day']),
        ('Weekend Getaway', '2 days', 4500, 7800, ['2 days']),
        ('Rail Ticket Booking Fee', '1 booking', 35, 60, ['1 booking']),
        ('Airport Transfer (Sedan)', '1 trip', 900, 1600, ['1 trip']),
        ('Ride Booking (per km)', '1 km', 11, 18, ['per km']),
        ('Outstation Cab (per km)', '1 km', 13, 22, ['per km']),
        ('Travel Insurance (domestic)', '1 trip', 120, 220, ['per trip']),
    ]),
]

# Cities with real coordinates for geo-seeds
SEED_CITIES = [
    ('Bengaluru', 'Karnataka', 12.9716, 77.5946),
    ('Mumbai', 'Maharashtra', 19.0760, 72.8777),
    ('Delhi', 'Delhi', 28.6139, 77.2090),
    ('Hyderabad', 'Telangana', 17.3850, 78.4867),
    ('Chennai', 'Tamil Nadu', 13.0827, 80.2707),
    ('Kolkata', 'West Bengal', 22.5726, 88.3639),
    ('Pune', 'Maharashtra', 18.5204, 73.8567),
    ('Ahmedabad', 'Gujarat', 23.0225, 72.5714),
    ('Jaipur', 'Rajasthan', 26.9124, 75.7873),
    ('Lucknow', 'Uttar Pradesh', 26.8467, 80.9462),
]

# Realistic Indian brand names per domain
BRAND_NAMES = {
    'Pharmacy & Healthcare': ['Apollo', 'Cipla', 'Dr. Morepen', 'MedPlus', 'Zandu', 'Dabur'],
    'Beauty & Personal Care': ['Lotus', 'Himalaya', 'Dabur', 'Tata', 'Vicco', 'Godrej'],
    'Furniture & Home Care': ['Nilkamal', 'Wakefit', 'Pepperfry', 'Durian', 'Godrej'],
    'Household Goods': ['Hawkins', 'Prestige', 'Butterfly', 'Milton', 'Cello'],
    'Sports, Fitness & Outdoor': ['Nivia', 'Cosco', 'Vector-X', 'HRX', 'SG'],
    'Books, Media & Stationery': ['Classmate', 'Navneet', 'Reynolds', 'Parker', 'Cello'],
    'Automotive Parts & Tools': ['Castrol', 'Exide', 'MRF', 'Bosch', 'Lumax'],
    'Hardware': ['Taparia', 'Bosch', 'Havells', 'Polycab', 'Finolex'],
    'Restaurants': ['Annapurna', 'Biryani Blues', 'Mei Mei', 'Sagar Ratna', 'Krishna'],
    'Transport': ['Savaari', 'Raftaar', 'LorryMerchant', 'VeriTrip'],
    "Personal Transport / Personal Travel": ['Ola', 'Uber', 'MakeMyTrip', 'Railyatri', 'Goibibo'],
}

# Physical shop names per domain (for realistic seed shops)
SHOP_NAMES = {
    'Pharmacy & Healthcare': ['Apollo Pharmacy', 'MedPlus', 'Jan Aushadhi Kendra', 'Krishna Medicals', 'Wellness Pharmacy'],
    'Beauty & Personal Care': ['Lotus Beauty Salon Store', 'Lakme Studio Store', 'Naturals Beauty Supply', 'Sharma Beauty Store'],
    'Furniture & Home Care': ['Nilkamal Furniture', 'Urban Home Studio', 'Arun Furniture House', 'Dream Decor'],
    'Household Goods': ['Prestige Kitchen Store', 'Cello House', 'Modern Home Store', 'Milton World'],
    'Sports, Fitness & Outdoor': ['Decathlon Select', 'Sports World', 'Fitness First Store', 'Nivia Sports Hub'],
    'Books, Media & Stationery': ['Oxford Book Store', 'Stationery Junction', 'Prem Prakash Books', 'Campus Store'],
    'Automotive Parts & Tools': ['Auto Parts House', 'GearUp Autos', 'Vehicle Care Zone', 'Krishna Motors Parts'],
    'Hardware': ['Taparia Hardware', 'Hardware Corner', 'Sharma Hardware Works', 'Tools & Fix'],
    'Restaurants': ['Annapurna Restaurant', 'Biryani Blues', 'Sagar Ratna', 'Mei Mei Asian Kitchen'],
    'Transport': ['Savaari Rentals', 'City Movers', 'Raftaar Logistics', 'Green Ride Services'],
    "Personal Transport / Personal Travel": ['Ola Hub', 'Uber Lounge', 'TravelDesk India', 'Railyatri Center'],
}


# ── Invariant: this seeder's 11 domains must EXACTLY equal the canonical
# registry (codes + names). Enforced at import time so a re-typed or leaked
# grocery / legacy name can never sneak in. Names must be derived from
# app.models.merchant_category, NEVER re-typed.
_DOMAIN_NAMES = {name for name, _ in BUSINESS_DOMAIN_CATALOG}
assert _DOMAIN_NAMES == set(MERCHANT_CATEGORY_NAMES.values()), (
    "BUSINESS_DOMAIN_CATALOG names drifted from canonical MERCHANT_CATEGORY_NAMES "
    "— do NOT re-type category names here; derive from app.models.merchant_category"
)
assert set(BRAND_NAMES.keys()) == _DOMAIN_NAMES, "BRAND_NAMES keys drifted from canonical names"
assert set(SHOP_NAMES.keys()) == _DOMAIN_NAMES, "SHOP_NAMES keys drifted from canonical names"


def build_domain_catalog():
    """Return the domain catalog for the seeder."""
    return BUSINESS_DOMAIN_CATALOG


def count_products() -> int:
    """Total number of (item, pack) products across all domains."""
    total = 0
    for _, items in BUSINESS_DOMAIN_CATALOG:
        for _, _, _, _, packs in items:
            total += len(packs)
    return total
