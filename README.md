# Raksha

A Flutter-based personal safety app for Android. Enables passive, hands-free emergency detection without requiring the user to unlock or interact with their device.

## Features

- Voice trigger detection — background voice monitoring using Android SpeechRecognizer with custom trigger words
- Gesture recognition — real-time hand gesture detection using MediaPipe
- Shake detection — accelerometer-based trigger (5 rapid shakes)
- SOS flow — 10-second countdown with cancel option, SMS to emergency contacts with live GPS location
- Stealth recording — automatic audio and video recording on SOS trigger using Camera2 API
- Secure vault — biometric-protected storage for emergency recordings
- Safety map — nearby hospitals, police stations, pharmacies via OpenStreetMap
- Multilingual support — 12 Indian languages for voice trigger words

## Tech Stack

Flutter, Kotlin, MediaPipe, Firebase (Auth, Firestore, Storage), Camera2 API, Android SpeechRecognizer, ML Kit, OpenStreetMap

## Setup

1. Clone the repo
2. Add `google-services.json` to `android/app/`
3. Run `flutter pub get`
4. Run `flutter run`

Requires Android 10+ with microphone, camera, location, and SMS permissions.
