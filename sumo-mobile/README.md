# Sumobot Mobile Controller

Flutter app to control the ESP32 sumobot over WiFi (HTTP endpoints: `/maju`, `/mundur`, `/kiri`, `/kanan`, `/stop`).

## Setup

1. Install Flutter: https://docs.flutter.dev/get-started/install
2. From this folder, scaffold platform files:
   ```
   flutter create .
   ```
3. Install dependencies:
   ```
   flutter pub get
   ```
4. For Android, add internet + cleartext HTTP permission. In `android/app/src/main/AndroidManifest.xml` add inside `<manifest>`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
   And on the `<application>` tag add:
   ```
   android:usesCleartextTraffic="true"
   ```
5. Connect phone to same WiFi as ESP32. Run:
   ```
   flutter run
   ```
6. In the app, tap the gear icon and enter the IP shown on the Arduino Serial Monitor.

## Controls

- Hold an arrow to move (forward / backward / rotate left / rotate right)
- Release to stop automatically
- Center red button = emergency stop
