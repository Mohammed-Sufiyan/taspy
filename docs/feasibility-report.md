# NFC PIN App — Milestone 1 feasibility report

Status: **core feasibility confirmed on device; lock-screen/background cases still to test.**

## Environment (checked 2026-10-09)

| Item | Value |
|---|---|
| Flutter / Dart | 3.44.9 stable / 3.12.2 |
| Android SDK | `C:\Android`, platform android-37, build-tools 36.0.0, JDK 21 |
| Test phone | Motorola edge 40 neo, Android 15 (API 35), connected via wireless debugging |
| Test card | User's credit card |
| Automated checks | `flutter analyze`: no issues · `flutter test`: 15 passed · debug APK builds |

Note: `flutter doctor` reports some Android SDK licences not accepted (`flutter doctor --android-licenses`). It did not block the debug build.

## What the app does (Milestone 1)

- Reads NFC hardware / enabled state natively and live-updates when NFC is toggled.
- Foreground scan via Android reader mode (NFC-A/B/F/V), with cancel and 30 s timeout.
- Registers a `TECH_DISCOVERED` filter (IsoDep, NfcA, NfcB, NfcF, NfcV) so Android can
  open the app when a card is tapped while the app is not scanning — this is the
  background experiment.
- Shows tech list, category, ID length and a **salted, truncated hash** of the ID.
  The raw ID never leaves native code. No commands (APDUs) are sent to the card, so no
  payment data is read. Nothing is written to the card. Nothing is persisted except the
  per-install salt.

## Device test steps

1. **Status:** open the app. Record NFC hardware / On. Turn NFC off in quick settings and
   confirm the screen shows "Off" and the settings button; turn it back on.
2. **Foreground scan:** tap *Scan NFC card*, hold the credit card on the back of the
   phone. Record the tech chips and category.
3. **Same-ID check:** keep scanning and tap the **same card** 5 times (lift it away fully
   between taps). Record the "Same ID on all N taps" / "N different IDs" card.
4. **Cancel / timeout:** start a scan, press *Stop scanning*. Start again and wait 30 s
   without a card — expect the timeout message.
5. **App open, not scanning:** with the app on screen but not scanning, tap the card.
6. **App in background:** press Home, tap the card on the home screen.
7. **App closed:** swipe the app away from Recents, tap the card.
8. **Phone locked:** lock the phone, wake the screen (don't unlock), tap the card.
   Then try with the screen off.
9. *(Optional)* repeat 2–7 with an NTAG sticker.

For steps 5–8: if a chooser appears, pick NFC PIN App → *Just once*. If you still see
"No supported application for this NFC tag", dispatch did not reach the app.
Use the copy icon (top right) to copy the report and paste it here.

## Results — credit card

| Test | Result |
|---|---|
| NFC hardware / enabled detected | ✅ Yes / On |
| Foreground detection | ✅ Detected (2 scans) |
| Technologies reported | IsoDep, NfcA · SAK 32 · ATQA 4400 · no NDEF |
| ID stable across taps? | ✅ Same ID on 3 of 3 taps (7-byte ID, no random-ID marker). 5-tap run still to do |
| App open, not scanning | |
| App in background | |
| App process terminated | ✅ Tap opened the app (`launch_closed`), same ID as foreground scans |
| Phone locked (screen on) | |
| Screen off | |
| NFC disabled | |

## Results — NTAG sticker (if available)

| Test | Result |
|---|---|
| Foreground detection | |
| App in background / terminated | |

## Background automation status

**Partly verified (2026-10-09).** With the app closed, tapping the credit card opened the
app and delivered the card's tap, replacing Android's "No supported application" message.
Still to test: app in background, app open not scanning, locked phone, screen off.

## Go / no-go

**Provisional GO** for the bank-card trigger on this phone and card:
- the card reports a stable 7-byte ID, so the app can recognise this specific card;
- Android dispatches the tap to the app even when it is closed.

Caveats: a static ID is not proof of ownership (it can be copied with cheap tools), so the
automation must stay low-risk (show a message / open something), never unlock secrets.
Behaviour on a locked phone is still unknown.

## Milestone 2 — registration + tap popup (2026-10-09)

- Registration requires two taps with the same ID before a card can be saved.
- Card taps are handled by `TapActivity` (transparent, own Flutter entry point `tapMain`),
  which shows a popup with the card's message over whatever is on screen.
- Automated: `flutter analyze` no issues, `flutter test` 47 passed.
- **Device:** user registered their credit card; tapping it showed the popup with the
  configured message. ✅
- Not yet individually confirmed on device: popup over another app, app swiped away,
  disabled card, unregistered card, locked phone.
