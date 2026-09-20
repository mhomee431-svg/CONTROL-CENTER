# Shop Location — Real Device Verification

> GPS fix, permission dialog, manual correction and drift prompt on a **physical
> Android device**. Deterministic unit/widget coverage lives in
> `test/shop_location_details_test.dart`, `test/shop_location_drift_test.dart`,
> `test/location_system_test.dart`; this document covers the parts those tests
> cannot reach.

## 1. Status

| Item | State |
|------|-------|
| Dart/Flutter logic (capture, validation, drift guard, copy) | ✅ implemented + unit/widget tested |
| Android/iOS location permissions | ✅ declared in `AndroidManifest.xml` / `Info.plist` |
| Map tiles (Google Maps SDK key) | ✅ wired via the Phase-15 `MAPS_API_KEY` placeholder |
| **On-device execution of the protocol below** |  **not yet run** — fill §5 after a device run |

Nothing in this document is claimed as verified until §5 records an actual
device run.

## 2. Prerequisites

1. **Phone** with USB debugging enabled (Settings → Developer options → USB
   debugging), connected and authorised (`adb devices` shows `device`).
2. **Dev backend** running on the workstation (login and reverse geocoding use
   it). The harness opens the USB tunnel itself:
   `adb reverse tcp:8000 tcp:8000`.
3. **Google Maps API key** — without it the map surface renders blank (GPS
   capture, coordinate fields and the drift guard still work). The key is
   injected at build time by Gradle and never committed:

   | Resolution order | Where |
   |------------------|-------|
   | 1 | `MAPS_API_KEY` environment variable (CI) |
   | 2 | `MAPS_API_KEY` in `apps/shopkeeper_app/android/local.properties` (gitignored) |
   | 3 | Gradle property `-PMAPS_API_KEY=…` |
   | 4 | empty → blank map surface |

   `android/app/build.gradle.kts` resolves the value into the
   `manifestPlaceholders["MAPS_API_KEY"]` placeholder that
   `AndroidManifest.xml` reads as `${MAPS_API_KEY}` (same Phase-15 mechanism as
   the customer app).

   To create your own key:

   1. Google Cloud Console → APIs & Services → Library → enable
      **Maps SDK for Android**.
   2. Credentials → Create credentials → API key.
   3. Restrict it to *Android apps* with package name `com.hyperlocal.app`
      (both apps share this applicationId) and your debug SHA-1:
      ```powershell
      keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" `
        -alias androiddebugkey -storepass android -keypass android
      ```
   4. Add the line to `apps/shopkeeper_app/android/local.properties`:
      ```properties
      MAPS_API_KEY=AIza...
      ```

   A workstation-local dev key is already present in that gitignored file, so a
   debug build renders tiles out of the box. Replace it with your own key
   before any production build.

## 3. Run the harness

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/device_shop_location_test.ps1
```

Options:

| Flag | Meaning |
|------|---------|
| `-SkipBuild` | reuse the existing debug APK |
| `-DeviceId TKIBRWQO8P7P7LGQ` | pick a device when several are attached |
| `-ApiBaseUrl http://127.0.0.1:8000` | dev backend seen through `adb reverse` |
| `-Scenario gpsOn` | run one scenario (`permissionDenied`, `gpsOn`, `gpsOff`) |

The script builds, installs, opens the USB tunnel, sets the permission / GPS
state for each scenario, clears and captures logcat, asserts the evidence
strings and writes everything to `build/device-shop-location/` (gitignored):
one `*.log` per scenario plus `*-result.json`. Device state is restored in a
`finally` block.

## 4. Scenarios and evidence

| Scenario | Device state set by the script | You do on the phone | Asserted from logcat |
|----------|-------------------------------|---------------------|----------------------|
| `permissionDenied` | both location permissions revoked, GPS on | reach step 3 → **Get Current Location** → tap **Deny** | `[LOC] serviceEnabled=true`, `[LOC] requestPermission=LocationPermission.denied`, `[STARTUP] API Base URL` |
| `gpsOn` | permissions granted, GPS on | tap **Get Current Location**, allow the prompt | `[LOC] checkPermission=LocationPermission.(whileInUse\|always)`, `[LOC] Using last-known position` **or** `[LOC] Fresh GPS fix:`, `[LOC] acquireBestLocation started` |
| `gpsOff` | permissions granted, GPS off | tap **Get Current Location** | `[LOC] serviceEnabled=false`, and **no** `[LOC] Fresh GPS fix:` |

Evidence strings come from the app's own `debugPrint` calls in
`lib/features/shops/data/location_service.dart`; nothing test-only is added to
`lib/`.

### 4.1 Checkpoints only a human can judge

- [ ] Map tiles render (blank surface ⇒ missing/invalid `MAPS_API_KEY`).
- [ ] `Getting location...` spinner appears first, then `Location found`.
- [ ] Accuracy shows a real radius + tier (e.g. `Excellent — Accuracy: 6 m`);
      the UI never claims "100% accurate".
- [ ] Tap/drag the pin >150 m from the GPS fix → prompt
      `This pin is about N m away from your GPS location. Are you sure this is
      your shop entrance?`
- [ ] `Yes, this is my shop entrance` → `Confirm Location and Continue` works;
      before confirming, **Next is refused** with
      `This pin is far from your GPS location…`.
- [ ] Manual `Latitude` / `Longitude` entry applies the pin; map, chip and
      fields stay consistent.
- [ ] For an adjusted pin the accuracy line reads
      `Location accuracy: unknown for the adjusted pin` (the GPS radius is shown
      separately as `Original GPS estimate — …`).
- [ ] Editing the `Address` text never moves the pin.
- [ ] `Deny` permission and retry shows the `Permission denied` card;
      GPS off shows `Location services are turned off…`; both offer Retry.
- [ ] Reverse-geocoded address prefill appears after confirming the pin
      (requires the dev backend + network).

## 5. Results

Fill in after running §3. Until then the on-device leg is **unverified**.

| Date | Device | Build | permissionDenied | gpsOn | gpsOff | Manual checkpoints | Notes |
|------|--------|-------|------------------|-------|--------|--------------------|-------|
| — | — | — | — | — | — | — | not yet executed |

## 6. Known limitations

- **Blank map surface without a key** — an invalid/absent `MAPS_API_KEY` still
  allows GPS capture and pin adjustment, but tiles (and possibly the marker
  overlay) will not draw. Not a code defect.
- **Drift + manual correction have no logcat evidence** — they are pure UI
  state changes; §4.1 is the only verification path. The guard logic itself is
  covered deterministically by `test/shop_location_drift_test.dart`.
- **`pm revoke` can fail** on some OEM builds for permissions the app has never
  requested; the script ignores that and still sets GPS state, so verify the
  printed `dumpsys` line before trusting a `permissionDenied` result.
- **Mock-location signal only** — `isMock` (stored as
  `location_integrity_status`) is an advisory client signal, never tamper-proof.
- Reverse geocoding falls back Google → Mappls → OSM; with no Google/Places key
  the address text depends on the OSM fallback being reachable.