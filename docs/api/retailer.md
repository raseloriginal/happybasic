# Retailer API — `/api/v1/retailer/*`

Role `retailer` (shop owner). **Read-only**: see what is coming, what arrived, bills and notifications. Headers / errors: see [README.md](README.md).

Login: phone = the shop's phone, password = the same phone ([auth.md](auth.md)). One phone can own several shop records; everything below covers all of them.

## `GET /retailer/today`
```json
{ "ok": true, "date": "2026-11-25",
  "shop": { "name": "…", "address": "…", "phone": "…" },
  "day": { "orders": [ /* order */ ], "cards": [ /* delivery card */ ], "total": 3150, "counts": { "arrived": 0, "onway": 1, "later": 0 } },
  "unread": 2 }
```
**Delivery card** = all orders of one trip (one DSR visit):
`{ title:"ACI-এর মাল", dm:"DSR name", stage:"arrived|onway|later", chip:"পথে আছে", rows:[{sr,company,bill,id}], total, first }` — `first` = id of an order to open its invoice.

**Order / invoice object**
```json
{ "id": 5, "code": "HB-০০০৫", "company": "Transcom", "sr": "…", "dm": "…", "trip_id": 1,
  "stage": "arrived", "status": "বাকি", "tone": "warn", "time": "2:58", "delivered_at": "…", "date": "2026-11-22",
  "bill": 3210,
  "shop": { "name": "…", "address": "…", "phone": "…" }, "partner": { "name": "…", "address": "…", "phone": "…" },
  "items": [ { "name": "…", "mrp": 600, "pcs": 6, "rate": 529.92, "amount": 3179.5, "gain": 423.5, "short": 0 } ],
  "subtotal": 3179.5, "damage": 0, "total": 3179.5, "paid": 0, "due": 3179.5,
  "mrp_total": 3600, "profit": 420, "profit_per_100": 13, "words": "তিন হাজার একশত …" }
```
* Before delivery: `pcs` = ordered, `bill` = the SR's order total, `status` = `পথে আছে` / `অপেক্ষমান`.
* After delivery (`stage:"arrived"`): `pcs` = delivered, `short` = ordered − delivered, damage deducted, `paid`/`due` real. `tone`: `ok` (paid), `warn` (due / partial), `info` (on the way).
* `mrp`, `gain`, `profit*`, `mrp_total` are `null` when the product has no MRP.

## `GET /retailer/history`
`{ ok, rows:[{ date, day, month, total, sub, today }] }` — up to 60 days, newest first.

## `GET /retailer/day?date=YYYY-MM-DD`
`{ ok, date, date_label, orders, cards, total, counts }` — same as `today.day` for any date (use it for old invoices).

## `GET /retailer/notifications`
`{ ok, unread, events:[{ kind, at, title, sub?, group, when, unread, … }] }` — last 14 days, newest first.
`kind`: `order` (an SR took an order), `onway` (trip dispatched), `arrived` (goods delivered). `group` = আজ / গতকাল / date.

## `POST /retailer/notifications/seen`
Marks everything read (`unread` becomes 0).

## Realtime
* Push (when `FCM_SERVICE_ACCOUNT` is configured): "আপনার মাল রওনা হয়েছে" when the partner dispatches the trip.
* While the app is open it re-checks `/retailer/notifications` every 60 s and shows a local notification for new events.
