# Mobile app — how it works

One Android app for **SR, DSR and Retailer**. The user types phone + password on a single login screen; the account's role opens the matching panel. Code: `mobile-app/` (Flutter). Server: `services/php` (`/api/v1`, see [api/README.md](api/README.md)).

```
Login ──► POST /auth/login ──► { token, role, profile }
              │
              ├─ role = sr        ──► SrHome       (অর্ডার · ড্যাশবোর্ড · ইতিহাস · আমি)
              ├─ role = dsr       ──► DsrHome      (হোম · ডেলিভারি · ভ্যান · খরচ · সেটেলমেন্ট)  + GPS tracking
              └─ role = retailer  ──► RetailerHome (আজ · হিস্ট্রি · নোটিফিকেশন · আমি)
```
The role comes from the account (set in Admin / Partner panels), never from the app. A token only works for its own role's endpoints.

## App structure (`mobile-app/lib`)

| Folder | What |
|---|---|
| `core/api.dart` | HTTP client: bearer token, `X-App-Version`, 401 → logout, 426 → update screen, network errors, idempotency key |
| `core/offline.dart` | offline write queue (persisted, ordered, retried automatically) |
| `core/session.dart` | signed-in user / role, login, logout |
| `core/tracker.dart` | DSR GPS (foreground service) |
| `core/push.dart` | Firebase push + local notifications |
| `core/printer.dart` | Bluetooth thermal printing |
| `core/store.dart`, `format.dart`, `config.dart` | local cache, Bangla numbers/dates/money, server URL |
| `ui/` | theme, shared widgets, account page, printer page, update screens |
| `auth/` `sr/` `dsr/` `retailer/` | the screens of each panel |

## SR (salesman)

1. **অর্ডার tab** loads `GET /sr/bootstrap` once (catalog + all shops + today's orders) and caches it on the phone. Shops are sorted by distance from the phone's GPS; search by name / phone / address; long-press a shop → open in Maps.
2. Tap a shop → **order editor**: per product enter dozen/pcs (unit conversion is automatic) and the **total taka** (defaults to pcs × dealer price; change it and the difference is the O/C, shown live). Save → `POST /sr/orders`.
3. **Offline**: if there is no internet, the order is saved in the queue ("সিঙ্ক বাকি"), shown in the list, and sent automatically when the network returns. The order keeps the time it was taken (`at`). Same for "Complete day".
4. **Complete today's orders** → partner can now put them on a trip. **Reopen** is possible until an order is on a trip.
5. Edit / cancel an order: only while it is still pending (online). New shop: needs internet (gets a real id) and GPS.
6. Dashboard (today / month vs targets), history by date, profile (month performance, photo, password).

**SR tracking**: like the DSR, an SR's phone sends GPS points (`POST /sr/track`) while the app runs, so the partner sees SRs on the live map ("(SR)") and can replay an SR's route. The green/red strip on the order page shows the state; the battery button asks Android not to stop the app with the screen off.

## DSR (delivery man)

* **Tracking**: right after login (and when DSR Home opens) the app starts GPS as an Android foreground service — a notification stays visible and points are sent in batches (~30 s) to `POST /dsr/track`; the partner sees the live map / route. Points are kept on the phone while offline. Stops on logout.
* **Attendance**: scan the godown QR (camera) → app sends token + GPS → server checks distance and duty start (late minutes).
* **Delivery**: list of shops of the open trip (pending first; date bar for older trips). Open a shop → per order, delivered pcs per product (± buttons, capped by van stock), cancel an order with a reason, damages (from the **ড্যামেজ** screen), payment amount (up to bill + the shop's old due). Save → `POST /dsr/stops/{shop}`. Long-press a shop → turn-by-turn in Google Maps; call button.
* **Ready sale**: sell van stock at the loaded price to an existing shop (search the full directory) or a new shop pinned at the DSR's GPS. A receipt can be printed.
* **Van stock**, **Expenses** (add/delete), **Settlement**: shows the net amount to hand over, goods to return to the godown, due shops; the DSR counts notes (৳1000 … ৳1), sees the difference, submits. The partner approves or sends it back with a note (the DSR sees it on Home / Settlement and fixes it).
* **Offline** (queued): save stop, damages, ready sale (existing shop), add expense. A stop with a queued save shows "সিঙ্ক বাকি". Online only: attendance, new-shop ready sale, reset stop, delete expense, settlement submit.

## Retailer (shop)

Read-only. **আজ**: today's incoming goods grouped by delivery (SR, company, bill, status "পথে আছে / এসেছে / পরে আসবে"), total bill; tap a card → **invoice** (lines, damage, paid/due, MRP & profit) → **print** on a Bluetooth printer. **হিস্ট্রি**: past days → invoices. **নোটিফিকেশন**: order taken / on the way / arrived, unread badge; checked every minute while the app is open and pushed when it is closed.

## Offline queue — how "never lost, never twice" works

```
user action ─► try POST with X-Op-Id: <new id>
                 ├─ ok ........................... done
                 ├─ 4xx (rule/validation) ........ show the message, nothing queued
                 └─ no network / timeout / 5xx ... save {id, method, path, body} on the phone
                                                   retry (same id) when: network returns · every 45 s · app starts
queue item  ─► server answers 4xx   -> marked "ব্যর্থ", stays visible (সিঙ্ক অবস্থা) so the user can read the reason / delete it
            ─► network/5xx          -> stays, retried later (items are sent in order)
```
The server stores the result of every `X-Op-Id` (`offline_ops`), so a retry after a lost response returns the stored result instead of repeating the action. Cached screens (last downloaded data) show a yellow "ইন্টারনেট নেই" banner.

## Realtime — notifications and live map

Two layers, both started after login:

1. **Live connection** (`core/realtime.dart` ⇄ `services/node` over Server-Sent Events): while the app is open, events arrive within a second — a notification, or "something changed" (screens reload quietly). The partner's browser uses the same service for the live map, so a DSR/SR pin moves the moment a GPS batch arrives instead of on the next 8-second poll.
2. **Firebase push** (`app/Services/Push.php`, FCM HTTP v1): reaches the phone when the app is closed. Registered with `POST /device`.

Both carry the same `nid`, so one event = one notification. Everything is sent **after** the API response, in parallel, so it can never slow down or fail a user's action. If the live service is down the app falls back to pull-to-refresh / resume / 60-second refresh; if Firebase is not configured only closed-app push is missing.

| Event | Who is notified |
|---|---|
| SR places an order | the shop (retailer) |
| Partner dispatches a trip | the DSR and every shop on the trip |
| DSR saves a shop's delivery | the shop ("মাল পৌঁছেছে" / "অর্ডার বাতিল"); the SR's screens refresh |
| Partner approves / sends back a settlement | the DSR |

Setup: [mobile-app/README.md](../mobile-app/README.md#push-notifications-firebase) and [#server-realtime-setup](../mobile-app/README.md#server-realtime-setup).

## Printing

Bluetooth thermal printers (58 / 80 mm). Bengali does not exist in ESC/POS code pages, so each receipt is drawn as an image with the phone's Bengali font and printed as a raster — it prints correctly on any printer. Pair the printer in Android Bluetooth settings first, then **আমি → ব্লুটুথ প্রিন্টার** → choose it, pick paper size, test print. Printing is used for: retailer invoices, DSR ready-sale receipts.

## Distribution (no Play Store yet)

1. Build the release APK (see mobile-app/README.md) with the next build number.
2. **Admin → Mobile App**: upload the APK, version name, build number, notes (tick "force update" to block old builds).
3. Share the public page `https://<domain>/app` (or the direct `/app/download` link). Users install the APK ("install unknown apps" must be allowed).
4. The app asks `GET /app/version` after login; if a newer build exists it offers the update (forced ones cannot be skipped). To block very old builds set `APP_MIN_VERSION_CODE` in `.env`.

## Known limits (by design, for now)

* Android only (the Flutter code is portable; iOS needs a Mac build + Apple account).
* SR editing/cancelling an existing order, adding a shop, DSR attendance and settlement submit need internet.
* Background GPS depends on the phone: on some brands (Xiaomi, Oppo, Vivo, Samsung power saving) the user must set the app to "no battery restriction" or tracking pauses when the screen is off.
* Push needs Google services on the phone and the Firebase setup; the retailer's in-app 60 s check is the fallback while the app is open.
* Product pictures and profile photos are cached after the first view; a picture never seen before needs internet.
