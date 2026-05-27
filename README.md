# Raksha — Silent Safety Companion

A Flutter-based personal safety app for Android that enables **passive, hands-free emergency detection** without requiring the user to unlock or interact with their device.

## Features

- **Voice Trigger Detection** — 24/7 background voice monitoring using Android SpeechRecognizer. User sets 3 custom trigger words; saying any of them activates SOS.
- **Gesture Detection** — Real-time hand gesture recognition using MediaPipe. Any of 4 gestures (Thumbs Up/Down, Peace, Fist) triggers SOS.
- **Shake Detection** — 5 rapid hard shakes (accelerometer-based) triggers SOS — works even with screen off.
- **SOS Flow** — 10-second countdown notification with cancel option → vibration phase → SMS sent to all emergency contacts with live GPS location every 60 seconds.
- **Stealth Recording** — On SOS trigger, automatically starts recording audio (mic) and video (back camera) silently using Camera2 API + MediaRecorder.
- **Secure Vault** — All recordings stored in encrypted app-private storage, accessible only via fingerprint/face ID or vault password.
- **Safety Map** — Nearby hospitals, police stations, and pharmacies via OpenStreetMap + Overpass API with one-tap Google Maps directions.
- **Background Persistence** — Foreground Service with WakeLock + BootReceiver ensures detection runs 24/7 even after phone restart.

## Tech Stack

- **Flutter** (Dart) — UI
- **Kotlin** — Native Android services
- **MediaPipe Tasks Vision** — Gesture recognition
- **Camera2 API** — Background video recording
- **Android SpeechRecognizer** — Voice detection
- **Firebase** (Auth, Firestore, Storage) — Backend
- **OpenStreetMap / Overpass API** — Safety map
- **local_auth** — Biometric vault access

## Setup

1. Clone the repo
2. Add your `google-services.json` to `android/app/`
3. Run `flutter pub get`
4. Run `flutter run`

## Requirements

- Android 10+ (API 29+)
- Microphone, Camera, Location, SMS permissions
- Battery optimization disabled for Raksha (Settings → Apps → Raksha → Battery → No restrictions)
