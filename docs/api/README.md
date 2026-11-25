# Mobile App API — `/api/v1`

The Android app (one app for **SR, DSR and Retailer**) talks to this API. Everything is JSON over HTTPS.

| Doc | Content |
|---|---|
| this file | conventions: auth, errors, offline / retry, versions |
| [auth.md](auth.md) | login, profile, password, push device, app version / download |
| [sr.md](sr.md) | SR endpoints |
| [dsr.md](dsr.md) | DSR endpoints |
| [retailer.md](retailer.md) | Retailer endpoints |
| [../MOBILE_APP_FLOW.md](../MOBILE_APP_FLOW.md) | how the app works end to end (screens, offline, GPS, push, printing) |

Code lives in `services/php`: routes in `routes/api.php`, controllers in `app/Controllers/Api/`, middleware in `app/Middleware/Api*.php`.
The API **reuses the web panels' own models and JSON actions**, so a rule (FIFO stock, O/C, settlement, dues…) is written once and the app can never disagree with the web.

## Base URL

`https://<your-domain>/api/v1` (local XAMPP: `http://localhost/happybasic/api/v1`).
The app's server address is compiled in (`--dart-define=API_BASE=...`) and can be changed on the login screen (tap the logo 7 times).

## Authentication

1. `POST /auth/login` with phone + password → returns `token` (64 hex chars) and the user's `role`.
2. Send it on every other call: `Authorization: Bearer <token>`.
3. The token is a normal tracked login session (`user_sessions`, 30 days, sliding). It appears in **Admin → Settings → Login Sessions** as `অ্যাপ · <phone model>` and can be revoked there. Changing the password signs out the user's other devices.
4. **401** on any call = session over → the app clears its data and shows the login screen.

Roles: `sr`, `dsr`, `retailer`. A role can only call its own prefix (`/sr/*`, `/dsr/*`, `/retailer/*`); another role's token gets **401**.
Partners and admins use the web panels, not the app.

## Required / useful headers

| Header | |
|---|---|
| `Authorization: Bearer <token>` | all calls except `/ping`, `/app/version`, `/auth/login` |
| `Content-Type: application/json` | for bodies (uploads use `multipart/form-data`) |
| `X-App-Version: <build number>` | the app's build (number after `+` in `pubspec.yaml`). If lower than `APP_MIN_VERSION_CODE` the server answers **426** |
| `X-Op-Id: <8-64 chars [A-Za-z0-9_-]>` | **idempotency key** for writes (see below) |
| `User-Agent: HappyBangladesh/1.0.0 (Samsung SM-A15; Android 14)` | shown as the device name in login sessions |

## Response format

Success: HTTP 200 and `{"ok": true, ...data}`.

Error: HTTP 4xx and
```json
{ "ok": false, "message": "বাংলা বার্তা — ইউজারকে দেখানোর জন্য", "errors": { "field": ["..."] } }
```

| Status | Meaning | App behaviour |
|---|---|---|
| 401 | not signed in / session revoked | go to login |
| 403 | account not active / not allowed | show `message` |
| 404 | not found | show `message` |
| 422 | validation or business rule (e.g. "not enough stock") | show `message`, do **not** retry |
| 426 | app build too old | show "update the app" screen |
| 429 | too many failed logins (5 per 15 min per IP) | show `message` |
| 5xx | server problem | treated like "offline": queued writes are retried later |

`message` is always safe to show to the user (Bangla). Messages from some deep business rules may still be English.

## Writes are safe to retry (`X-Op-Id`)

Every write (POST / PUT / DELETE) may carry `X-Op-Id`. The server runs that op **at most once per user** and stores the result;
a repeat of the same id (lost response, offline-queue retry, double tap) gets the stored response back with header `X-Op-Replayed: 1` and changes nothing.
Rules for the app: generate the id **once per user action**, reuse it for every retry of that action, never reuse it for a different action.
Applies to `/sr/*` and `/dsr/*` writes. (`/auth/*`, `/device` and `/retailer/*` are naturally repeatable.)

Offline-capable writes (the app queues them when there is no network): SR create order, SR complete day, DSR save stop, ready sale (existing shop), damages, expense add.
Online-only writes: login, SR add shop, DSR attendance, settlement submit, anything that edits/deletes an existing server record.

## Dates, money, ids

* Dates `YYYY-MM-DD`, server time zone `APP_TIMEZONE` (Asia/Dhaka in production). Timestamps `YYYY-MM-DD HH:MM:SS`.
* Money is a number in BDT (may be int, float or a string like `"345.00"` — parse defensively).
* Some ids are strings (`"id":"188"`) because the web UI compares them with DOM attributes; parse as integers when sending back.
* Image paths (`photo`, `image`) are absolute URLs in `profile`/`/auth` responses; in catalog responses they can be site-relative (`/uploads/products/x.webp`) — prefix the server origin.
* `at` (unix seconds) in order writes = when the SR actually took the order. Orders taken offline keep their real time; values older than 3 days or in the future are replaced by server time.

## Public endpoints

| | |
|---|---|
| `GET /ping` | `{ok:true,time}` — connectivity check |
| `GET /app/version?code=<build>` | newest published build, see [auth.md](auth.md) |

## Realtime (Server-Sent Events) — `services/node`

Instant events without polling. The Node service keeps open `GET /rt/app` connections (header `Authorization: Bearer <token>`); PHP tells it what happened (`POST /publish`, internal token) **after the response is sent**, so a slow or dead realtime service never slows or breaks an API call.

| Event | Channel | Sent when |
|---|---|---|
| `notify` `{title, body, nid, type}` | `user:<id>` | same moments as push (below) — the app shows it at once |
| `refresh` | `user:<id>` | a DSR saved a delivery → the SR who took that order refreshes |
| `location` / `order` | `partner:<id>` | a DSR/SR sent GPS points, an SR placed an order → the partner's live map updates instantly |

* The app opens `/rt/app` after login and reconnects with a growing delay (3 s … 5 min). If the service is unreachable the app still works: it refreshes on pull-down, on resume and every 60 s.
* `nid` is the same in the push message and in the live event, so the phone shows a notification only once.
* PHP is the only code that knows who a token/cookie belongs to: on every new connection Node calls `GET /api/v1/auth/channels` (apps) or `GET /partner/live/channels` (partner browser) with the client's own credentials and listens only to the channels PHP returns.
* Production: the web server must proxy `/rt/` to `127.0.0.1:3001` with buffering off (see [mobile-app/README.md](../../mobile-app/README.md#server-realtime-setup)). Node runs under PM2 (`ecosystem.config.cjs`).

## Server configuration (`.env`)

| Key | Purpose |
|---|---|
| `APP_MIN_VERSION_CODE` | builds below this get 426 (0 = off) |
| `FCM_SERVICE_ACCOUNT` | path to the Firebase service-account JSON; empty = push disabled (everything else works) |
| `INTERNAL_SERVICE_TOKEN` | shared secret between PHP and Node (already used by the other services); realtime publishing is refused without it |
| `APP_URL` | public site URL; the Node service calls it back to authenticate realtime connections |
| `REALTIME_AUTH_URL` | optional override of the URL Node uses for those calls (e.g. `http://127.0.0.1` behind a proxy) |

Apache must pass the `Authorization` header to PHP — `services/php/public/.htaccess` does this (`RewriteRule … E=HTTP_AUTHORIZATION`), and `Request::capture()` also falls back to `getallheaders()`.
Uploading an APK from the admin page needs PHP `upload_max_filesize` / `post_max_size` ≥ the APK size (≈ 60 MB; set 100M).

## Adding a new endpoint

1. Put the rule in a **model** (so web and app share it).
2. Add a thin controller method (or reuse the web panel's JSON action) and a route in `routes/api.php` inside the right role group.
3. Document it in the matching `docs/api/*.md` and in [MOBILE_APP_FLOW.md](../MOBILE_APP_FLOW.md) if the user flow changes.
