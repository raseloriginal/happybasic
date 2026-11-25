# Auth, profile, push device, app version

See [README.md](README.md) for headers, error format and idempotency.

## `POST /auth/login` (public)

One login screen for every role. The server finds the account by phone and returns its role; the app opens that panel.

Request
```json
{ "phone": "01711889012", "password": "secret123" }
```
* SR / DSR: password is the one set by the partner/admin.
* Retailer: type the **shop's phone number** in the password field too (any format: `01712-345678`, `+8801712345678`). The retailer account is created automatically on the first sign-in if an active shop has that phone.

Response
```json
{
  "ok": true,
  "token": "9f2c…64 hex…",
  "role": "sr",
  "profile": { "user_id": 4, "name": "Salman khan", "phone": "01711889012", "role": "sr",
               "sr_id": 1, "code": "SR-0001", "area": "Bagha", "company": "ACI Limited", "partner": "Muhammad Muzahid",
               "photo": "https://…/uploads/sr/x.webp", "daily_target": 50000 }
}
```
Profile by role

| role | extra fields |
|---|---|
| `sr` | `sr_id, code, area, company, partner, photo, daily_target` |
| `dsr` | `dsr_id, code, partner, photo` |
| `retailer` | `shops: [{id, name, address}]` |

Errors: 422 wrong phone/password · 403 account inactive · 429 locked (5 failed tries / 15 min / IP).

## `GET /auth/me`
Same `role` + `profile` as login (use it to refresh the profile / check the session).

## `POST /auth/logout`
Revokes the token. Optional body `{ "fcm_token": "…" }` also stops pushes to that phone.

## `POST /auth/password` (SR, DSR)
```json
{ "current_password": "old", "password": "new-min-6", "password_confirmation": "new-min-6" }
```
Signs out the user's other devices (this token stays valid). Retailer → 403 (their phone number is the password).

## `GET /auth/channels`
Realtime channels this token may listen to: `{ "ok": true, "channels": ["user:4"] }`. Called by the Node realtime service, not by the app.

## `POST /device`
Registers the phone for push notifications (call after login and whenever Firebase issues a new token).
```json
{ "fcm_token": "…", "platform": "android", "app_version": "1.0.0" }
```
A token belongs to whoever registered it last. Invalid/uninstalled tokens are deleted automatically when FCM rejects them.

### Push messages sent by the server (`data.type`)

| Event | To | `type` |
|---|---|---|
| An SR places a new order | the shop's retailer account | `order` |
| Partner dispatches a trip | the DSR; every retailer on that trip | `trip` / `delivery` |
| DSR saves a shop's delivery | that shop's retailer account ("মাল পৌঁছেছে" / "অর্ডার বাতিল") | `delivery` |
| Partner approves a settlement | the DSR | `settlement` |
| Partner sends a settlement back | the DSR (body = the partner's note) | `settlement` |

Every message also goes through the live connection (see *Realtime* in the README) with the same `nid`.

Notification channel id: `hb_default`. Sending never blocks or fails the business action.

## `GET /app/version?code=<build>` (public)
```json
{ "ok": true, "update": true, "force": false, "version_name": "1.0.3", "version_code": 4,
  "notes": "What's new", "size": 61234567, "sha256": "…", "url": "https://…/app/download" }
```
`update:false` when the app is current or nothing is published. `force:true` = the app blocks until updated.
`GET /app/download` (public, web route) redirects to the newest active `.apk`; `GET /app` is the public download page to share.

## Admin → Mobile App (web)
Upload a build (APK + version name + build number + notes + "force update"), deactivate/delete builds, copy the public link. Files go to `public/uploads/app/`.
