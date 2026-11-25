# DSR API — `/api/v1/dsr/*`

Role `dsr` (delivery man). Headers / errors / `X-Op-Id`: see [README.md](README.md).

A DSR has **one open trip** (status `dispatched`; `in_review` after submitting the settlement; `settled` after the partner approves).
Every GET that shows a trip accepts `?date=YYYY-MM-DD` to look at that day's trip; without it the open trip is used.
Trip object: `{ id, code, date, partner_id, status_key, editable, settlement_status, review_note, dispatched_at, sr_ids }` — `editable:false` means read-only (settled / in review).

## Day flow
1. Attendance → scan the godown QR ([attendance](#attendance)).
2. Partner dispatches the trip (push arrives) → stops appear in [delivery](#get-dsrdelivery).
3. For each shop: delivered pcs, damage, payment → [save stop](#post-dsrstopsretailer).
4. Optional: ready sale, expenses.
5. [Settlement](#settlement): count cash → submit → partner approves or sends back.
6. GPS points are sent all day ([track](#post-dsrtrack)).

## `GET /dsr/dashboard`
`{ ok, date, today, dsr:{name,partner,photo}, trip|null, attendance|null, stats:{stops,delivered,due,pending,cancelled,dispatched_pcs,available_pcs}, settlement|null }` — `settlement` is the live summary (same as [settlement.summary](#get-dsrsettlement)).

## `GET /dsr/delivery`
One call for the delivery screen:
```json
{ "ok": true, "trip": {…}|null, "selectedDate": "2026-11-22",
  "orders": [ /* stop */ ],
  "vanStock": [ /* van product */ ],
  "damageProducts": [ { "id": "1", "name": "…", "company": "…", "company_id": 4, "unit_type": "Dozen", "qty_per_unit": 12, "rate": 530, "image": "…" } ],
  "cancelReasons": [ "Shop Closed", "Owner / Decision Maker Not Available", "…" ],
  "server_time": 1795587450 }
```

### Stop object (one shop on the trip)
```json
{ "id": "188", "retailer_name": "…", "phone": "…", "address": "…", "lat": 24.28, "lng": 88.75,
  "sr_names": ["Rabiya islam"],
  "companies": [ { "id": "5", "order_code": "ORD-…", "name": "Transcom", "company_id": 4, "sr": "Rabiya islam",
                   "ready_sale": false, "status_key": "pending", "cancelled": false, "cancel_reason": null,
                   "items": [ { "product_id": "1", "name": "…", "unit_type": "Dozen", "qty_per_unit": 12,
                                "ordered_qty": 13, "qty": 0, "base_rate": 530, "sr_rate": 529.92, "stock": 21 } ] } ],
  "damages": [ { "order_id": 5, "product_id": 1, "pcs": 4, "amount": 2120, "name": "…" } ],
  "old_due_collected": 0, "existing_due": 0, "paid_amount": 0, "due_amount": 0,
  "cancel_reason": null, "status": "Pending", "editable": true }
```
* `companies[]` = one order per company (SR). `ready_sale:true` entries are DSR ready sales (not editable here).
* Item `qty` = delivered **pieces**; `ordered_qty` = ordered pieces; `stock` = pieces the van can still give for this product (includes what this order already took).
* `status`: `Pending`, `Delivered`, `Due`, `Partial`, `Cancelled`.
* `existing_due` = the shop's old due; paying more than the bill collects it (`old_due_collected`).

### Van product
`{ id, name, company, company_id, unit_type, qty_per_unit, base_rate, ordered_pcs, dispatched_pcs, delivered_pcs, ready_sold_pcs, available_pcs, delivery_oc, image, code, tint }`

## `GET /dsr/delivery/state` — lighter refresh
`{ ok, trip, selectedDate, orders, vanStock, damageProducts }`.

## `POST /dsr/stops/{retailer}` — save a shop's delivery (offline-capable)
```json
{ "orders": [ { "id": 5, "cancelled": false, "items": [ { "product_id": 1, "pcs": 12 } ] } ],
  "damages": [ { "order_id": 5, "product_id": 1, "pcs": 4 } ],
  "paid": 6000,
  "cancel_reason": "" }
```
Rules (enforced by the server):
* **Every** non-ready-sale order of that shop on the trip must be included, else 422.
* `pcs` may be more than ordered but never more than van stock for that product.
* A cancelled order needs a non-empty `cancel_reason` taken from `cancelReasons` (optionally `"Reason (note)"`).
* Bill = Σ delivered pcs × SR rate − damage. `paid` up to the bill settles it; anything above collects the shop's old due. Unpaid part becomes the shop's due (status `Due`/`Partial`).
* Allowed only while the trip is `dispatched` (not after the settlement is submitted).

Response: `{ ok, message, trip, selectedDate, orders, vanStock, damageProducts }` (fresh state).

## `POST /dsr/stops/{retailer}/reset` (online only)
Puts a saved stop back to `Pending` (undo). Returns fresh state.

## `POST /dsr/damages` — damage returns for one shop (offline-capable)
```json
{ "retailer_id": 188, "items": [ { "product_id": 1, "pcs": 4 } ] }
```
Replaces that shop's damage list (empty `items` clears it). Damage is valued at the dealer price and deducted from the bill. Response `{ ok, message, damageResult:{count,total,retailer}, …fresh state }`.

## `POST /dsr/ready-sales` — sell van stock on the spot
Existing shop (offline-capable):
```json
{ "mode": "existing", "retailer_id": 188, "items": [ { "product_id": 1, "pcs": 3 } ] }
```
New shop (online only; pinned at the given location):
```json
{ "mode": "new", "name": "…", "phone": "", "address": "", "lat": 24.28, "lng": 88.75, "items": [ … ] }
```
Price = the dealer price loaded on the van (cannot be changed). Response: `{ ok, message, receipt:{retailer,total,codes:[…],items:[{name,pcs,rate,total}]}, …fresh state, newRetailer? }` — print `receipt`.
`DELETE /dsr/ready-sales/{id}` removes one (online only).

## `GET /dsr/retailers`
All shops (for the ready-sale picker): `{ ok, retailers:[{id,name,phone,address,lat,lng,due,…}] }`.

## `GET /dsr/van-stock`
`{ ok, trip, selectedDate, products:[van product] }`.

## Expenses
`GET /dsr/expenses` → `{ ok, trip, selectedDate, expenses:[{id,title,category,amount,note,time,date}], categories:[Fuel, Helper, Food, Toll & Parking, Van Repair, Mobile / Communication, Other] }`

`POST /dsr/expenses` (offline-capable) `{ "title": "ডিজেল", "category": "Fuel", "amount": 500, "note": "" }` → `{ ok, message, expenses }`
`DELETE /dsr/expenses/{id}` (online only) → `{ ok, message, expenses }`

## Settlement
`GET /dsr/settlement` →
```json
{ "ok": true, "trip": {…}, "selectedDate": "…",
  "settlement": {
    "trip": {…}, "counts": { "orders": 6, "pending": 0, "cancelled": 1, "stops_total": 4, "stops_done": 4, "due_shops": 2 },
    "summary": { "order_amount": 25463.92, "total_load": 31800, "return_amount": 11130, "total_sales_base": 18550, "total_sales_sr": 18575,
                 "ready_sale": 2120, "prior_due_collected": 0, "system_cash": 6355, "damaged_amount": 2120, "daily_expenses": 345,
                 "delivery_oc": 25, "retailer_due": 12220, "paid": 6355, "net_pay": 6010 },
    "cash": { "counted": 6000, "diff": -10, "partner_received": 6000, "partner_diff": -10 } | null,
    "damage_review": {…}, "return_items": [ { "product_id": 1, "name": "…", "expected_return_pcs": 21, "counted_return_pcs": 21, "reason": "…" } ],
    "expenses": […], "notes": [ { "value": 1000, "qty": 6 }, … 500, 200, 100, 50, 20, 10, 5, 2, 1 ],
    "sr_oc_rows": […], "due_details": [ { "order_id": "…", "retailer": "…", "order_total": 3210, "paid": 0, "due": 3210 } ] } }
```
**Net pay** (= money to hand over) = delivered bill (SR price) + ready sale + old due collected − damage − expenses − new due. SR O/C is not deducted from cash.

`POST /dsr/settlement` (online only) — submit the cash count
```json
{ "notes": { "1000": 6, "500": 0, "200": 0, "100": 0, "50": 0, "20": 0, "10": 0, "5": 0, "2": 0, "1": 0 }, "note": "optional" }
```
422 while any order is still `Pending`. On success the trip becomes `in_review`; the partner **approves** (→ `settled`: unsold stock returns to its lots, FIFO cost, SR O/C, shop dues and damage claims are posted) or **sends back** with a note (trip returns to `dispatched`, `trip.settlement_status:"returned"`, `trip.review_note`) — the DSR corrects and submits again.

## Attendance
`GET /dsr/attendance[?date=]` → `{ ok, selectedDate, is_today, today:{…}|null, days:[{date,day,weekday,status,value,manual,time,late_min,distance}] }` (`status`: `present`, `half`, `absent`, `holiday`; the month of `selectedDate`).

`POST /dsr/attendance` (online only) — after scanning the partner's godown QR
```json
{ "token": "<t from the QR>", "lat": 24.28, "lng": 88.75, "accuracy": 12 }
```
The QR holds `https://<domain>/dsr/attendance?t=<token>` — the app sends the `t` value. The phone location is compared with the godown (radius set by the partner); duty start time decides `late_min`. Repeating the scan returns the first record (`already:true`). Response `{ ok, message, time, late_min, already }`.

## `POST /dsr/track` — GPS points
```json
{ "points": [ { "t": 1795587450, "lat": 24.2812929, "lng": 88.7517353, "acc": 12, "bat": 80 } ] }
```
Up to 300 per call; `t` unix seconds (older than 3 days, in the future, 0,0 are dropped); repeats are ignored; response `{ ok, saved, tracking }`. The partner sees them on **Live location** and the day's route. The app sends in batches every ~30 s and keeps unsent points on the phone.
