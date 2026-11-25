# Happy Bangladesh — Android app (Flutter)

One app for SR, DSR and Retailer. Flow and behaviour: [`../docs/MOBILE_APP_FLOW.md`](../docs/MOBILE_APP_FLOW.md). API: [`../docs/api/`](../docs/api/README.md).

Nothing here is built automatically. Build only when asked (see below).

## Requirements
Flutter 3.47+ (Dart 3.13), Android SDK, JDK 17. Check with `flutter doctor`.
Windows note: if Flutter lives in a path with a space (`C:\Users\Rasel Boss\flutter`), call it from PowerShell: `& "C:\Users\Rasel Boss\flutter\bin\flutter.bat" …` (cmd/bash break on the space).

## Build environment notes (verified: release APK builds)
* Flutter and the Android SDK live in space-free paths (`C:lutter`, `C:ndroidsdk`) — the Android tools break on spaces. Keep it that way.
* `android/app/build.gradle.kts` uses `compileSdk = max(flutter default, 37)` and `android/gradle.properties` carries compatibility flags (`android.newDsl=false`, `android.builtInKotlin=false`, `suppressUnsupportedCompileSdk`) needed by the current plugins; do not remove them.
* A release APK is ≈ 80 MB (all CPU types). For a smaller file per phone: `flutter build apk --release --split-per-abi` and upload the `arm64-v8a` one (almost every phone since 2017).

## Server address
Default: `https://v2.happybangladesh.com` (`lib/core/config.dart`). Override at build time:
```
flutter build apk --release --dart-define=API_BASE=https://your-domain.com
```
On the login screen, tap the logo 7 times to type another server (for testing). **Release builds accept https only.** Debug builds also allow `http://` (e.g. emulator → XAMPP: `http://10.0.2.2/happybasic`).

## Run on a device / emulator (development)
```
cd mobile-app
flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2/happybasic     # emulator + local XAMPP
```

## Version numbers
`pubspec.yaml` → `version: 1.0.0+1` = **versionName + build number**. Every APK you publish needs a **higher build number** (Admin → Mobile App rejects a repeated one, and the app compares build numbers for updates).

## Release signing (once)
```
keytool -genkey -v -keystore happybangladesh.jks -keyalg RSA -keysize 2048 -validity 10000 -alias happybd
```
Create `android/key.properties` (git-ignored):
```
storeFile=C:/path/to/happybangladesh.jks
storePassword=…
keyAlias=happybd
keyPassword=…
```
**Back up the `.jks` and passwords.** An update must be signed with the same key as the installed app; if it is lost every user has to uninstall and reinstall. Without `key.properties` the release APK is signed with the debug key (OK for testing only).

## Build the APK (only when asked)
```
flutter build apk --release --dart-define=API_BASE=https://v2.happybangladesh.com
# → build/app/outputs/flutter-apk/app-release.apk
```
Then upload it in **Admin → Mobile App**.
Server needs PHP `upload_max_filesize` and `post_max_size` ≥ APK size (set 100M).

## Push notifications (Firebase)
1. console.firebase.google.com → create a project → add an **Android app** with package name `com.happybangladesh.happy_bangladesh`.
2. Download `google-services.json` → put it in `mobile-app/android/app/` (git-ignored). The Gradle build picks it up automatically (without it the app builds fine, just without push).
3. Project settings → Service accounts → **Generate new private key** → save the JSON on the server (e.g. `storage/firebase-service-account.json`, not in git) and set in the server `.env`:
   `FCM_SERVICE_ACCOUNT=storage/firebase-service-account.json`
4. Rebuild the APK. Test: dispatch a trip in the partner panel → the DSR phone gets a notification.

## Server realtime setup
Live notifications and the live map use the Node service in `services/node` (already deployed by `deploy.sh` through PM2 — `pm2 startOrRestart ecosystem.config.cjs`). Two things on the VPS:

1. `.env` must have `INTERNAL_SERVICE_TOKEN=<long random string>` (publishing is refused without it) and `APP_URL=https://<your-domain>`.
2. The web server must forward `/rt/` to Node **without buffering**. CloudPanel → the site → Vhost → add inside the `server { }` block:
```
location /rt/ {
    proxy_pass http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_set_header Host $host;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 1h;
}
```
Test: `curl -i https://<domain>/rt/app` must answer **401** (not 404). A 404 means the proxy is missing; the app still works, only without instant events.
Local XAMPP has no proxy, so the app and the partner map fall back to their normal refresh there.

## Folder map
```
lib/
  main.dart            app start, role gate (login → SR / DSR / Retailer)
  core/                api, offline queue, session, tracker (GPS), push, printer, cache, formatting
  ui/                  theme, shared widgets, account / printer / update pages
  auth/                login
  sr/                  order page + editor, add shop, dashboard / history / profile
  dsr/                 home, attendance (QR), delivery + stop, damage, ready sale, van stock, expenses, settlement
  retailer/            today / history / notifications, invoice
android/               manifest (permissions), Gradle (signing, desugaring, optional google-services)
```

## Android permissions used
Location (+ foreground service) for DSR tracking and shop pins · Camera (attendance QR) · Notifications · Bluetooth (printer) · Internet. Each is requested when first needed.

## Checks
`flutter analyze` (no errors/warnings) · `flutter test` (on Windows a space in the Flutter/user path can break it with "Building native assets failed" — run from a path without spaces) · manual test checklist: login as each role → SR order offline (airplane mode) then back online → DSR attendance, deliver a stop, ready sale, settlement → partner approves → retailer sees invoice.
