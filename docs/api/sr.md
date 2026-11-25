# SR API — `/api/v1/sr/*`

Role `sr`. Headers / errors / `X-Op-Id`: see [README.md](README.md).

An SR belongs to one partner and one company. Prices come from the partner's latest lot; the SR sees the **dealer price** and may enter a different **total** per line — the difference is the SR's **O/C** (`total − pcs × dealer price`). Orders can be edited/cancelled until the partner puts them on a trip; the SR then presses **Complete day**.

## `GET /sr/bootstrap` — everything the order screen needs (cache it for offline)
```json
{
  "ok": true, "server_time": 1795587450,
  "products": [ { "id": "1", "name": "Salman khan", "unit_type": "Dozen", "qty_per_unit": 12,
                  "unit_price": 6360, "pc_price": 530, "available_pcs": 813,
                  "image": "/uploads/products/x.webp", "tint": "#fefce8", "code": "SK" } ],
  "retailers": [ { "id": "2941", "name": "Said Anwar", "phone": "", "address": "…", "lat": 24.28, "lng": 88.75, "sr_id": 4, "due": 0 } ],
  "day": { "date": "2026-11-25", "completed": false, "locked": false, "orders": [ /* order */ ], "totals": { "orders": 0, "value": 0, "oc": 0 } },
  "day_completed": false
}
```
* `products`: only products that have a price. `available_pcs` is the partner's stock (a warning is returned if an order exceeds it; it is not blocked).
* `retailers`: **all shops** (retailers are global, not per partner) — thousands of rows (~450 KB, gzip ≈ 80 KB). Cache on the phone, sort by distance on the phone.

### Order object
```json
{ "id": 15, "code": "ORD-261123-00015", "date": "2026-11-23", "time": "07:30 PM",
  "sr_id": 4, "sr": "…", "company_id": 4, "company": "Transcom",
  "retailer_id": 261, "retailer": "…", "retailer_address": "", "retailer_phone": "…",
  "trip": null, "trip_date": null, "dsr": null,
  "base_total": 3180, "sr_total": 3150, "oc": -30,
  "delivered_total": 0, "paid": 0, "due": 0, "damage": 0, "notes": null, "cancel_reason": null,
  "status": "Pending", "status_key": "pending", "editable": true,
  "items": [ { "product_id": 1, "name": "…", "unit_type": "Dozen", "qty_per_unit": 12, "pcs": 6, "qty": "0 Dozen 6 pcs",
               "delivered_pcs": 0, "base_rate_pc": 530, "sr_rate_pc": 525, "total": 3150, "oc": -30, "image": "…", "code": "SK", "tint": "#fefce8" } ] }
```
`status_key`: `pending`, `assigned`, `delivered`, `partial`, `due`, `cancelled`. `editable:false` once the order is on a trip.

## Orders

### `POST /sr/orders` — place an order (offline-capable)
```json
{ "retailer_id": 261, "items": [ { "product_id": 1, "pcs": 6, "total": 3150 } ], "at": 1795587450 }
```
* One open (pending, no trip) order per shop per day: posting again for the same shop **replaces its items**.
* `pcs` > 0, `total` > 0 per line. `at` = unix seconds when the order was taken (offline orders keep their real time).
* 422 if today is already completed ("reopen the day to change orders").

Response: `{ ok, message, order, warnings:[…], day }` — `warnings` lists soft problems (e.g. stock lower than ordered).

### `PUT /sr/orders/{id}` — change an open order (online only)
Same body. 422 once the order is on a trip.

### `DELETE /sr/orders/{id}` — cancel (online only)
Response `{ ok, message, day }`.

### `GET /sr/orders/today`
`{ ok, day }` (same `day` object as bootstrap).

### `POST /sr/orders/complete` — complete today (offline-capable) · `POST /sr/orders/reopen` (online only)
Body `{ "at": <unix seconds> }`. Completing makes the SR's orders assignable to a trip. Reopen only works while no order is on a trip.

## Shops

### `GET /sr/retailers` → `{ ok, retailers:[…] }` (same list as bootstrap)

### `POST /sr/retailers` — add a shop (online only)
```json
{ "name": "রহিম স্টোর", "phone": "01712345678", "address": "বাজার রোড", "lat": 24.28, "lng": 88.75 }
```
`name`, `address`, `lat`, `lng` required (location must be real, not 0,0). A shop with the same name within ~30 m is rejected. Response `{ ok, message, retailer }`.

## Reports

### `GET /sr/dashboard`
`{ ok, date, profile:{name,initials,code,phone,area,company,partner,daily_target,monthly_target,oc_balance,retailers_added,status,…}, today:{…stats}, month:{…stats}, day_completed }`

`stats`: `orders, retailers, value, oc, over_oc, comm_oc, delivered, delivery_oc, pending, assigned, done, delivery_rate`.

### `GET /sr/history?date=YYYY-MM-DD`
`{ ok, date, today, orders:[order] }`. Without `date` → the latest day that has orders.

### `GET /sr/profile?date=YYYY-MM-DD`
`{ ok, date, today, day_summary:{date, stats, products:[{id,name,ordered_pcs,dispatched_pcs,delivered_pcs,returned_pcs,…}]}, profile, month, month_label }`

### `POST /sr/profile/photo` — `multipart/form-data`, field `photo` (JPG/PNG/WebP ≤ 3 MB; stored as a 160 px square WebP)
`{ ok, message, photo }`.

### `POST /sr/track` — GPS points while on duty
Same body as the DSR's [`/dsr/track`](dsr.md#post-dsrtrack--gps-points): `{ "points": [ { "t": 1795587450, "lat": 24.28, "lng": 88.75, "acc": 12, "bat": 80 } ] }` → `{ ok, saved, tracking }`.
The partner's **Live location** page shows SRs next to DSRs (name + "(SR)"); the SR's route of any day can be replayed. The app starts it automatically after login and keeps a foreground notification while it runs.

Password change: [`POST /auth/password`](auth.md).
