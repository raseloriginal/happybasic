# HappyBasic — Full System & Business Flow (Admin · Partner · SR · DSR)

> **Purpose:** hand this file to any AI/developer so they can understand the whole system and keep working on it without re-discovering everything.
> **Last synced with code:** 2026-11-20. If code and this doc disagree, **code wins** — then update this doc.

---

## 0. TL;DR (read this first)

HappyBasic is an FMCG **distribution management** system (Bangladesh, currency ৳ BDT, phones `+880…`).

```
ADMIN ──creates──► Areas, Categories, Companies (global), Partners, Dealers, SRs (+ links partner↔company), Platform fees
                                   │
PARTNER (distributor) ─► Products ─► Lots (stock in, FIFO) ─► Delivery Men (DSR) ─► Trips ─► Settlement approval
                                   ▲                                     │
SR (salesman, 1 company) ── places orders for retailers ──► "Complete day" ┘
                                                                         ▼
DSR (delivery man) ── delivers trip orders, damage, payment, ready sale, expenses ──► submits cash ──► Partner approves
```

Order lifecycle in one line:
`SR order (pending)` → `SR completes day` → `Partner assigns to trip (assigned)` → `Partner dispatches trip (stock FIFO-consumed)` → `DSR delivers (delivered / partial / due / cancelled)` → `DSR submits settlement (trip in_review)` → `Partner approves (trip settled: stock return, FIFO cost, SR O/C, retailer due, damage claim)`.

---

## 1. Tech stack & project layout

- **PHP 8.2+ custom MVC** (no framework), MySQL/MariaDB via PDO, runs on **XAMPP** at `http://localhost/happybasic`.
- Root `.htaccess` rewrites everything → `services/php/public/` → `index.php` front controller.
- Node (`services/node`, port 3001) and Python (`services/python`, port 8001) services exist as skeletons only (health endpoints). Call via `service('node')->get(...)`. **Not used by business logic.**
- `APP_TIMEZONE` should be `Asia/Dhaka` so PHP `date()` matches MySQL dates.

```
happybasic/
├── database/
│   ├── schema.sql                 # full schema (fresh install)
│   ├── migrations/001..005_*.sql  # apply in order on existing DB
│   ├── setup.php                  # php database/setup.php  -> create DB + tables
│   └── create-admin.php           # php database/create-admin.php --email=.. --name=..
├── services/php/
│   ├── core/            # Router, Request, Response, Database(PDO), Model, View, Session, Csrf, Auth, Validator, helpers.php
│   ├── config/          # app.php, database.php, services.php
│   ├── routes/          # web.php (requires admin.php, partner.php, sr.php, dsr.php)
│   ├── app/Controllers/{Admin,Partner,Sr,Dsr}/ + PanelAuthController, AuthController, HomeController
│   ├── app/Controllers/Concerns/JsonActions.php   # action(), check(), phone(), statusFrom(), passwordRule()
│   ├── app/Middleware/  # AdminAuth, PartnerAuth, SrAuth, DsrAuth, Csrf, Guest, Auth
│   ├── app/Models/      # ALL business logic lives here (static methods, raw SQL)
│   ├── app/Support/     # PanelAuth, HttpError, Format, Phone
│   ├── app/Views/{admin,partner,sr,dsr}/...  + layouts/main.php per panel
│   └── public/assets/{admin,partner,sr,dsr}/js/(panel.js + pages/*.js), css/
└── storage/ (logs, uploads)   # product images actually go to services/php/public/uploads/products/
```

---

## 2. Coding conventions (follow these when adding features)

### 2.1 Backend
- **Models are `final class` with static methods** and raw SQL through `Database::getInstance()` (`fetch`, `fetchAll`, `execute` → affected rows, `lastInsertId`, `transaction(fn(Database $db) => ...)`).
- **Business-rule errors:** `throw new HttpError('Human message', 422, ['field' => ['msg']])`. Status codes used: 404 not found, 409 conflict (has dependants), 422 validation/rule, 429 rate-limit, 403 inactive.
- **Controllers** use trait `JsonActions`:
  - `$this->action(fn() => [...])` → returns `{"ok": true, ...}` or on `HttpError` `{"ok": false, "message": ..., "errors": {...}}` with status.
  - `$this->check($request, $rules, $messages)` → validated array (missing keys = null).
  - `$this->phone($data, 'field')` → normalized BD phone or 422.
  - Page actions return `$this->view('partner.trips', [...data, 'title' => .., 'activeNav' => ..])`.
- **Context of logged-in actor:** `PartnerAuthMiddleware::partner()`, `SrAuthMiddleware::sr()` (`id, partner_id, company_id, name, user_id…`), `DsrAuthMiddleware::dsr()` (`id, partner_id, name, user_id`). Partner controllers extend `PartnerController` (`partnerId()`, `log()`, `dateInput()`, `dateQuery()`, `intInput()`).
- **Always scope queries by owner**: partner data by `partner_id`, SR by `sr_id`, DSR by its open trip. Never trust ids from the client without the scope check.
- **Activity log:** `ActivityLog::record($action, $module, $detail, $userId)` on every create/update/delete/approve.
- **Soft delete:** master data uses `deleted_at` (+ `status='inactive'`). Deleting a record that has dependants is blocked with 409 → user must reassign or deactivate. `User::softDelete()` also sets `phone = NULL` to free the number.
- **Codes:** inserted first with `TMP-<random>`, then updated to a readable code using the new id:
  `ORD-ymd-00001` (order), `RS-ymd-00001` (ready sale), `TRP-ymd-0001` (trip), `LOT-ymd-0001` (lot).
- **Money:** `DECIMAL`, PHP `round(x, 2)`; per-piece rates `DECIMAL(12,4)`. Float comparisons use `0.004/0.005` tolerance.
- **All quantities are stored in PIECES (`*_pcs`).** UI shows `"X Carton Y pcs"` via `Product::unitPcs($pcs, $qty_per_unit, $unit_type)`.

### 2.2 Frontend
- Server-rendered PHP views + one vanilla JS file per panel (`partner.js`, `sr.js`, `dsr.js`, `admin.js`) + `pages/<page>.js`.
- Initial data is passed as JSON in `data-*` attributes or inline JSON (`json_encode` with `JSON_HEX_*` flags) — no separate GET API for most pages.
- Mutations: `api(method, url, body)` helper → `fetch` with `X-CSRF-TOKEN` (from `<meta name="csrf-token">`), `X-Requested-With: XMLHttpRequest`, `Accept: application/json`. 401 → redirect to `data.redirect`; 419 → CSRF expired.
- Partner/SR panels have **SPA-style navigation** (fetch page, swap `#partnerContent`, header `X-Partner-SPA: 1`), boot loader, skeletons, toasts.
- Product cards without image show initials on a tint (`Product::visual()`).

### 2.3 Safety rule for DB work
The local `happybasic` DB contains the user's **real data**. Never hard-code ids in tests, never run unscoped `UPDATE/DELETE`; snapshot `MAX(id)` before a test and scope writes to the new rows only.

---

## 3. Authentication (4 separate logins)

| Panel   | URL               | Credential        | users.role | Session key / cookie                      | Middleware              |
|---------|-------------------|-------------------|-----------|--------------------------------------------|-------------------------|
| Admin   | `/admin/login`    | email + password  | `admin`   | `AdminAuthMiddleware::TOKEN_KEY` (Core\Auth) | `AdminAuthMiddleware`   |
| Partner | `/partner/login`  | phone + password  | `partner` | `panel_partner_token`, cookie `hb_partner_remember` | `PartnerAuthMiddleware` |
| SR      | `/sr/login`       | phone + password  | `sr`      | `panel_sr_token`, `hb_sr_remember`         | `SrAuthMiddleware`      |
| DSR     | `/dsr/login`      | phone + password  | `dsr`     | `panel_dsr_token`, `hb_dsr_remember`       | `DsrAuthMiddleware`     |

- `App\Support\PanelAuth` handles partner/SR/DSR: phone normalized (`Phone::normalize`), 5 failed attempts per IP → 15-minute lock (counted from `activity_logs`), session token stored in `user_sessions` (revocable, "remember me" cookie). Each panel has its own token, so admin + partner + SR + DSR can be signed in side by side in one browser.
- Middleware also checks the **business record** is active: SR needs active salesman + active partner + active company; DSR needs active delivery_man + active partner. Otherwise session is forgotten → redirect/401 JSON.
- All `/admin|partner|sr|dsr` routes pass through `CsrfMiddleware`.
- Role `dealer` exists in `users` (dealers get a login account) but **there is no dealer panel yet**.

---

## 4. Data model (tables & meaning)

### 4.1 Master data
| Table | Key columns | Notes |
|---|---|---|
| `users` | role, phone (unique), email, status, deleted_at | login accounts for every actor |
| `areas` | name, status | partners must belong to an area |
| `partners` | user_id, area_id, name, phone, tin, trade_license, nid, address, status | the distributor |
| `dealers` | partner_id, user_id, ... | a dealer belongs to one partner; used for "dealer" ownership |
| `companies` | name, status | **global catalog** (e.g. "ACI Limited"), shared by all partners |
| `partner_companies` | partner_id, company_id, ownership(`owned`/`dealer`), dealer_id, dealer_profit_share, partner_profit_share, platform_fee_per_lakh | **created automatically when an SR is saved**; unique (partner, company) |
| `platform_fee_history` | partner_id, company_id, fee_per_lakh, effective_from, changed_by | append-only |
| `salesmen` (SR) | partner_id, company_id, user_id, daily_target, monthly_target, **oc_balance** | **1 SR = 1 company** |
| `sr_order_days` | (sr_id, order_date) | row exists = SR completed that day's orders |
| `delivery_men` (DSR) | partner_id, user_id, name, phone, salary, status, deleted_at | zone/vehicle columns unused |
| `retailers` | partner_id, created_by_sr_id, name, phone, address, **lat/lng (required)**, **due_balance** | shared by all SRs of a partner |
| `categories` | name, slug | global, managed by admin |

### 4.2 Catalog & inventory (FIFO)
| Table | Notes |
|---|---|
| `products` | per partner + company. `company_price` = buying price/pc of the **newest lot**; `dealer_margin` %; `base_price` = dealer price/pc = `company_price × (1 + margin/100)`; `stock_pcs` mirrors Σ `lot_items.remaining_pcs`; `qty_per_unit`, `unit_type` (Carton, Case, Box, Pack, Dozen, Sack, Bag, Piece) |
| `lots` | one stock receipt from a company (`received_date`, `total_value`) |
| `lot_items` | **FIFO layers**: `qty_pcs`, `remaining_pcs`, `company_price_per_pc`, `expire_date` |

### 4.3 Trips
| Table | Notes |
|---|---|
| `trips` | `status`: `pending` → `dispatched` → `in_review` → `settled`. **Unique (dsr_id, trip_date)** = one trip per DSR per day |
| `trip_srs` | SRs assigned to the trip |
| `trip_van_stocks` | per product: `ordered_pcs` (from orders), `dispatched_pcs` (= loaded qty), `delivered_pcs`, `ready_sale_pcs`, `returned_pcs`, `base_rate_pc`, `is_checked` |
| `trip_stock_allocations` | which `lot_item` each dispatched piece came from (`dispatched_pcs`, `sold_pcs`, `returned_pcs`, `company_price_per_pc`) |

### 4.4 Orders & delivery
| Table | Notes |
|---|---|
| `orders` | 1 order = 1 company + 1 retailer (+1 SR, or `sr_id NULL` & `is_ready_sale=1`). Status enum: `pending, assigned, delivered, due, partial, cancelled`. Frozen: `platform_fee_rate`. Totals: `order_base_total, order_sr_total, order_oc` (at ordering) and `delivered_base_total, delivered_sr_total, delivery_oc, damage_amount, paid_amount, due_amount, platform_fee_amount` (at delivery) |
| `order_items` | `ordered_pcs, delivered_pcs, base_rate_pc (frozen dealer price), sr_rate_pc (SR's selling price/pc), order_oc, delivery_oc, fifo_cost_total` |
| `delivery_damages` | damaged goods returned by retailer at delivery (`qty_pcs`, `amount` at dealer price, `claimed_to_company`) |
| `retailer_due_collections` | old due collected by DSR during a trip |
| `trip_expenses` | DSR expenses (category list fixed) |

### 4.5 Settlement & ledgers
| Table | Notes |
|---|---|
| `trip_settlements` | snapshot of trip figures at submit + `cash_counted`, `cash_diff`, `cash_notes_json`, `status` (`submitted/approved/returned`), `review_note` |
| `sr_oc_ledger` | SR over/commission ledger (`delivery_oc`, `payout`, `adjustment`) |
| `company_ledger` | partner ↔ company account: `lot_purchase` (debit), `damage_claim`/`payment` (credit), `adjustment` (either). Balance = debit − credit = payable to company |

---

## 5. Key formulas & terms (glossary)

| Term | Meaning / formula |
|---|---|
| **Company price** | Partner's buying price per piece (from newest lot). |
| **Dealer price / Base price / base_rate_pc** | `company_price × (1 + dealer_margin%)`, rounded 2. Minimum selling price to retailer. |
| **SR price / sr_rate_pc** | Price SR actually agreed with retailer. SR enters a **line total**; `sr_rate_pc = total / pcs`. |
| **O/C (Over / Commission)** | `SR total − pcs × base_rate_pc`. Positive = **Over** (SR sold above dealer price, payable to SR). Negative = **Commission** (SR gave discount, deducted from SR). |
| `order_oc` | O/C on ordered qty. `delivery_oc` = O/C on **delivered** qty = `delivered_pcs × (sr_rate − base_rate)` — this is what is posted to the SR. |
| **Platform fee** | Fee per lakh (100,000 ৳) of sales, per partner+company. `amount = delivered_base_total × fee_per_lakh / 100000`. Rate frozen on order at creation (`PlatformFee::rateAt`). Counts only statuses `delivered, due, partial`. |
| **Bill (per order)** | `delivered_sr_total − damage_amount` = `paid_amount + due_amount`. |
| **Net Pay (trip cash)** | `delivered SR total + ready sale + old due collected − damage − expenses − new due`. SR O/C is **not** deducted. |
| **Cash diff** | `cash_counted − net_pay` (short if negative, excess if positive). Only recorded/shown; no auto deduction. |
| **Available stock** | `stock_pcs − reserved_pcs`, reserved = ordered pcs on orders that are `pending/assigned` and not on a dispatched trip (`Product::RESERVED_SQL`). |
| **FIFO** | Stock consumed oldest `lots.received_date`, then `lot_items.id`. Profit/COGS always from FIFO consumption (`order_items.fifo_cost_total`). |
| **Rates freeze** | Order freezes `base_rate_pc` + `platform_fee_rate`; price/fee changes never alter history. |

---

## 6. ADMIN panel (`/admin/*`)

Controllers: `app/Controllers/Admin/*`. Views: `app/Views/admin/*`. JS: `public/assets/admin/js/pages/*`.

Resource routes for `partners | companies | dealers | salesmen`:
`GET /admin/{res}` (page) · `POST /admin/{res}` (create) · `PUT /admin/{res}/{id}` · `PATCH /admin/{res}/{id}/status` · `DELETE /admin/{res}/{id}` (soft).

### 6.1 Setup order (required)
1. **Settings → Areas** (`POST /admin/settings/areas`) — partners need an area. Creating a name that was soft-deleted restores it. Delete blocked if partners use it.
2. **Settings → Categories** (global product categories; slug unique; restore on re-create).
3. **Companies** — global (name unique). Delete blocked if SRs assigned.
4. **Partners** — creates `users(role=partner)` + `partners`. Fields: name, phone, password, area, tin, trade license, nid, address, status. Delete blocked if dealers / SRs / active DSRs exist.
5. **Dealers** — belong to one partner, own login account. Changing a dealer's partner blocked if it has active SRs; deleting blocked if SRs use it.
6. **Salesmen (SR)** — the **bridge** partner ↔ company:
   - `ownership = owned` → pick partner directly.
   - `ownership = dealer` → pick dealer, partner = dealer's partner; enter `dealer_profit_share` %, partner share = 100 − dealer share.
   - Saving an SR **creates/updates `partner_companies`** (`Salesman::syncLink`). A partner↔company link has one ownership; if other SRs use the link, a conflicting ownership/dealer is rejected (422).
   - SR's partner cannot change once it has orders/retailers/trips.
7. **Platform Fees** (`/admin/platform-fees`) — set `fee per lakh` per partner+company link. `PUT /admin/platform-fees/{partnerId}` with `{company_id: fee}`; each real change appends a `platform_fee_history` row (effective now). `GET /admin/platform-fees/{partner}/history/{company}` shows periods with sales & fee earned.

### 6.2 Other admin features
- **Dashboard**: counts (partners, companies, SR, DSR, products), 6-month partner growth, partners per area, last 5 activity log entries. `/admin/health` system health.
- **Settings → Sessions**: revoke a session / revoke all other sessions; activity log viewer.

---

## 7. PARTNER panel (`/partner/*`)

Base controller `Partner\PartnerController`. Sidebar: Dashboard · Trips · Settlements · Day Closing · Lots · Products · Company Ledger · Orders · Delivery Men.

### 7.1 Products (`/partner/products`) — `Models/Product.php`
- Create/update (`POST /partner/products`, `POST /partner/products/{id}` — POST so multipart image works; image JPG/PNG/WebP ≤ 3 MB → `public/uploads/products/`).
- Company must be one of partner's linked companies (`Product::companyOptions` = `partner_companies`). Name unique per partner+company.
- Product has **no price until a lot is received** (`priced = base_price > 0`); unpriced products are hidden from SR ordering.
- Changing `dealer_margin` recomputes `base_price` from current `company_price`.
- After lots exist: company and `qty_per_unit` are **locked**.
- Delete (soft) blocked if stock or open orders exist → deactivate instead.

### 7.2 Lots (`/partner/lots`) — `Models/Lot.php`
- `POST /partner/lots` `{company_id, received_date, notes, items:[{product_id, pcs, price_pc, expire_date}]}`.
- Qty entered **in pieces**, price **per piece**; UI shows converted units. Expire date ≥ lot date; no duplicate product rows.
- Effects (one transaction):
  1. `lots` + `lot_items` (remaining_pcs = qty_pcs).
  2. `products.stock_pcs += pcs`.
  3. If this lot is the **newest by received_date** for that product → `company_price = price_pc`, `base_price = dealerPrice(price_pc, margin)`. (Back-dated lots don't change current price.)
  4. `company_ledger` **debit** `lot_purchase` = lot total.
- `DELETE /partner/lots/{id}` only if untouched (all `remaining_pcs == qty_pcs`): reduces stock, removes ledger row, restores product price from newest remaining lot.

### 7.3 Delivery Men / DSR (`/partner/delivery-men`) — `Models/DeliveryMan.php`
- Fields: name, phone, salary, password, status. Creates `users(role=dsr)`.
- Passwords never shown; only reset (`POST /partner/delivery-men/{id}/password`).
- Soft delete blocked while DSR has unsettled trips.

### 7.4 Trips (`/partner/trips`) — `Models/Trip.php`, `TripController`
**Planner** `GET /partner/trips/planner?order_date=&delivery_date=`:
- SR side: SRs with ≥1 `pending`, unassigned order on the order date; shows orders/retailers/products/value and `completed` (from `sr_order_days`). **Not-completed SRs show faded and cannot be assigned.**
- DSR side: active DSRs + their trip on the delivery date + any `open_trip` (dispatched/in_review).

**Create / assign** `POST /partner/trips` `{order_date, delivery_date, dsr_id, sr_ids[]}` → `Trip::assign`:
- `delivery_date ≥ order_date`; DSR must be active; DSR must have **no other dispatched/in_review trip** (one open trip per DSR).
- Reuses the DSR's `pending` trip for that delivery date, else creates one (`TRP-…`). If that trip is already dispatched → error.
- For each SR: insert `trip_srs`; orders of that SR+date with `pending` & no trip → `trip_id = trip`, `status = 'assigned'`.
- `syncOrdered`: recompute `trip_van_stocks.ordered_pcs` per product from orders; loaded qty (`dispatched_pcs`) shifts by the same difference; new products start loaded = ordered with `base_rate_pc = product.base_price`.

**Edit before dispatch** (trip must be `pending`):
- `PATCH /partner/trips/{id}/items/{product}` `{loaded_pcs?, checked?}` — change loaded qty (UI shows live +/- vs ordered), tick checklist.
- `POST /partner/trips/{id}/items` `{product_id, pcs}` — add **extra product** (ordered_pcs = 0) for ready sale; must be active & priced.
- `DELETE /partner/trips/{id}/items/{product}` — only extra products can be removed.
- `DELETE /partner/trips/{id}/srs/{sr}` — unassign SR: its orders back to `pending`, trip deleted if empty.

**Dispatch** `POST /partner/trips/{id}/dispatch` → `Trip::dispatch`:
- Requires: something loaded, **every row checked**, DSR has no other open trip.
- Per product: lock FIFO layers (`lot_items` ordered by `received_date, id`), if total remaining < loaded → collect shortage → whole dispatch fails with "Not enough stock: …".
- Else consume oldest first: `lot_items.remaining_pcs -= take`, insert `trip_stock_allocations`, `products.stock_pcs -= loaded`. Extra products get `base_rate_pc` = dealer price at dispatch.
- Trip → `dispatched`, `dispatched_at = NOW()`.

### 7.5 Settlements (`/partner/settlements`) — `Models/TripSettlement.php`
- List: trips dispatched/in_review/settled in date range (default last 7 days); `in_review` always on top.
- Each card = `TripSettlement::compute()` (live figures, SR O/C rows, due details, cash notes).
- `POST /partner/settlements/{tripId}/send-back` `{note}` (required) → settlement `returned` + note; trip back to `dispatched` (DSR can edit & resubmit).
- `POST /partner/settlements/{tripId}/approve` → see §10.

### 7.6 Orders (`/partner/orders`) — read-only list with filters (`from, to, sr_id, company_id, status`), items, delivery figures. `OrderController` + `Order::forPartner`.

### 7.7 Company Ledger (`/partner/company-ledger`) — `Models/CompanyLedger.php`
- Summary per linked company: purchases, payments, balance (payable).
- Statement with opening/closing balance for a date range.
- `POST /partner/company-ledger` `{company_id, type: payment|adjustment, side: debit|credit (adjustment only), amount, date, note}`. Payment = credit.
- Only manual entries (payment/adjustment) can be deleted. `lot_purchase` and `damage_claim` are system entries.

### 7.8 Dashboard (`/partner/dashboard?from=&to=`) — `PartnerDashboard::stats`: orders (by order date), retailers, stock value (Σ remaining × cost), lot purchases in range, trips (by delivery date).

---

## 8. SR panel (`/sr/*`) — mobile-first

Controllers `Sr/*`, model `Order`, `Retailer`, `SrStats`. Landing page `/sr` = Order page.

### 8.1 Order page (`/sr/order`)
- Map of the partner's retailers (Leaflet-style, lat/lng; fallback Dhaka 23.8103, 90.4125; starts at SR's last retailer).
- **Add retailer** `POST /sr/retailers` `{name, phone?, address, lat, lng}` — location required; duplicate name at same location rejected. `created_by_sr_id` = SR.
- Catalog = SR's **company** products for its partner that are active **and priced**. Shows unit price, piece price (dealer price), available pcs.
- **Place / edit order** `POST /sr/orders` or `PUT /sr/orders/{id}` `{retailer_id, items:[{product_id, pcs, total}]}` → `Order::save`:
  - Only for **today** (`date('Y-m-d')`); blocked if today is already completed.
  - One open order per SR+retailer+day: posting again for same retailer **replaces items** of the existing `pending` order.
  - `pcs ≥ 1`, `total ≥ 0`, no duplicate products.
  - `base_rate_pc` = current dealer price (or **kept frozen** from the existing order line on edit).
  - `sr_rate_pc = total / pcs`; `order_oc = total − pcs × base`.
  - Over-stock is **allowed with a warning** (`warnings[]`); shortage surfaces at dispatch.
  - New order freezes `platform_fee_rate = PlatformFee::rateAt(partner, company)`.
- **Cancel** `DELETE /sr/orders/{id}` — only `pending`, not on a trip, day not completed → status `cancelled`, reason "Cancelled by SR".
- **Complete Today's Orders** `POST /sr/orders/complete` — needs ≥1 non-cancelled order; inserts `sr_order_days`. Only then partner can assign the SR to a trip.
- **Reopen** `POST /sr/orders/reopen` — only if none of that day's orders is on a trip.
- `GET /sr/orders/today` → today's state (`orders`, totals: count/value/oc, `completed`, `locked`).

### 8.2 Other SR pages (DB driven)
- **Dashboard** `/sr/dashboard`: today vs `daily_target`, month totals vs `monthly_target`, O/C balance (`salesmen.oc_balance`). Cancelled orders never count.
- **History** `/sr/history`, `GET /sr/history/day?date=` — all orders of a date incl. cancelled.
- **Profile** `/sr/profile` + `POST /sr/profile/password` — company, partner, monthly performance, retailers added.

---

## 9. DSR panel (`/dsr/*`) — mobile-first

Controllers `Dsr/*` (base `DsrController`: `dsr()`, `trip()`, `log()`), model `DsrDelivery` + `TripSettlement`.

**A DSR works only on his single open trip** (`DsrDelivery::activeTrip`: status `dispatched` or `in_review`, oldest first). `editable` only when `dispatched`; `in_review` = read-only "waiting for partner review". If settlement was sent back, `review_note` is shown.

### 9.1 Delivery (`/dsr/delivery`, `GET /dsr/delivery/state`)
- **Stops** = trip orders grouped **by retailer** (one stop may hold orders of several companies/SRs). Stop status: Pending / Delivered / Due / Cancelled. Shows `existing_due` (collectable old due = `retailers.due_balance` − amounts already collected on other unsettled trips).
- **Save stop** `POST /dsr/stops/{retailerId}` body:
  ```json
  { "orders": [ { "id": 12, "cancelled": false, "items": [ { "product_id": 5, "pcs": 24 } ] } ],
    "damages": [ { "order_id": 12, "product_id": 7, "pcs": 2 } ],
    "paid": 1500.00, "cancel_reason": "Shop Closed" }
  ```
  Rules (`DsrDelivery::saveStop`):
  - Every non-ready-sale order of the retailer must be included.
  - Delivered pcs may **exceed ordered** but not exceed van availability (other stops' deliveries counted; this stop's previous values freed).
  - Only products that are on the order (extra products → Ready Sale).
  - Cancelled order needs a reason from `DsrDelivery::CANCEL_REASONS` (+ "Other"); saved as `cancel_reason = "DSR: <reason>"`, all amounts zeroed.
  - **Damage**: product of the same company as the order, amount = pcs × current dealer price, deducted from that order's bill; damage > delivered value → error.
  - `paid` ≤ Σbills + collectable old due. Payment fills orders in order; **extra over the bill = old due collected** → `retailer_due_collections`.
  - Per order: `status = delivered` (due 0) / `partial` (some paid) / `due` (nothing paid); sets `delivered_*`, `delivery_oc`, `damage_amount`, `paid_amount`, `due_amount`, `platform_fee_amount`.
  - Syncs `trip_van_stocks.delivered_pcs / ready_sale_pcs`.
  - **Saved immediately** (no approval needed for this step); stock/due/OC balances change only on approval.
- **Reset stop** `POST /dsr/stops/{retailerId}/reset` → orders back to `assigned`, damages/collections removed.
- **Ready sale** `POST /dsr/ready-sales` `{retailer_id | new_retailer{name,phone,address,lat,lng}, product_id, pcs}`:
  - Sells van stock (`available = dispatched − delivered`) at the **loaded dealer price** — DSR **cannot change price**.
  - New retailer can be created on the spot (location required).
  - Creates order `RS-…` with `sr_id NULL`, `is_ready_sale=1`, `status='delivered'`, fully paid, O/C 0, platform fee at current rate.
  - `DELETE /dsr/ready-sales/{orderId}` to undo.

### 9.2 Van stock (`/dsr/van-stock`) — per product: ordered, loaded, delivered, ready-sold, available, delivery O/C.

### 9.3 Expenses (`/dsr/expense`) — `POST /dsr/expenses` `{title, category, amount, note}`; categories: Fuel, Helper, Food, Toll & Parking, Van Repair, Mobile / Communication, Other. `DELETE /dsr/expenses/{id}`. Only while trip editable.

### 9.4 Settlement (`/dsr/settlement`) — `POST /dsr/settlement` `{notes: {"1000": 3, "500": 2, ...}}`
- Blocked if any order is still `assigned/pending` ("finish every stop first").
- Denominations: 1000, 500, 200, 100, 50, 20, 10, 5, 2, 1. `cash_counted = Σ value × qty`, `cash_diff = counted − net_pay`.
- Upserts `trip_settlements` (snapshot of all totals, status `submitted`, clears review_note) and sets trip → **`in_review`**.

### 9.5 Dashboard (`/dsr/dashboard`) — current trip summary.

---

## 10. Settlement approval — what happens (`TripSettlement::approve`, one transaction)

Precondition: trip belongs to partner and is `in_review`.

1. **Stock return + FIFO cost** (per `trip_van_stocks` row):
   - `return = dispatched_pcs − delivered_pcs`.
   - Walk the trip's allocations **newest lot first**; give back `return` pcs → `lot_items.remaining_pcs += back`, set allocation `returned_pcs/sold_pcs`. `products.stock_pcs += return`; `trip_van_stocks.returned_pcs = return`.
   - Remaining sold layers (oldest first) are assigned to delivered order lines in order (`o.id, oi.id`) → `order_items.fifo_cost_total`.
2. **SR O/C**: per SR, Σ `orders.delivery_oc` (non-cancelled) → `sr_oc_ledger(entry_type='delivery_oc')` and `salesmen.oc_balance += oc`.
3. **Retailer due**: `retailers.due_balance += Σ due_amount` of the trip; then `−= Σ retailer_due_collections` (floored at 0).
4. **Damage claim**: per company, Σ `qty_pcs × products.company_price` → `company_ledger` **credit** `damage_claim` (company bears the cost); `delivery_damages.claimed_to_company = 1`.
5. `trip_settlements.status = approved`, `approved_by`, `approved_at`; trip → **`settled`**, `settled_at`. The DSR is now free for a new trip.

---

## 11. Status state machines

```
orders.status:
  pending ──(partner assigns to trip)──► assigned ──(DSR saves stop)──► delivered | partial | due | cancelled
     │  ▲                                   ▲                                      │
     │  └──(partner unassigns SR)───────────┘ (reset stop puts back to assigned) ◄─┘
     └──(SR cancels, before trip & day not completed)──► cancelled
  ready sale: created directly as delivered (is_ready_sale = 1)

trips.status:
  pending ──dispatch──► dispatched ──DSR submits──► in_review ──partner approves──► settled
                            ▲                            │
                            └────── partner send-back ───┘   (trip_settlements.status = returned)

sr_order_days: (no row) open ──complete──► completed ──reopen (only if nothing on a trip)──► open
```

---

## 12. Worked example (numbers)

Product "Soap 100g": qty_per_unit 72 (Carton). Lot A (Jan 1): 144 pcs @ ৳30/pc. Lot B (Jan 5): 72 pcs @ ৳32/pc. Margin 10%.
- After Lot B (newest): company_price 32, dealer price = 35.20/pc. Ledger debit: 4,320 + 2,304.
- SR orders 100 pcs for Retailer R, total ৳3,600 → sr_rate 36.00, base 35.20 → order_oc = 3600 − 3520 = **+80 (Over)**.
- Partner assigns + loads 110 pcs (10 extra) + dispatches → FIFO takes 110 from Lot A (remaining A = 34).
- DSR delivers 100 pcs; retailer returns 2 damaged pcs (2 × 35.20 = 70.40). Bill = 3600 − 70.40 = 3,529.60. Retailer pays 3,000 → order `partial`, due 529.60. Ready-sale 5 pcs to new shop @35.20 = 176. Expense fuel ৳200.
- Net Pay = 3600 + 176 + 0 − 70.40 − 200 − 529.60 = **2,976.00**. DSR counts 2,970 → cash_diff −6 (short, recorded only).
- Approve: return 110 − 105 = 5 pcs to Lot A; FIFO cost for 105 sold pcs = 105 × 30; SR oc_balance += 80 (delivery O/C on 100 pcs); retailer due_balance += 529.60; company_ledger credit damage 2 × 32 = 64.

---

## 13. Confirmed business rules (from the owner — do not change without asking)

**Partner/SR**
- Separate logins for partner and SR (phone + password).
- DSR form: name, phone, salary, password only. Passwords never shown, only reset. Soft delete.
- Lots in pieces, price per piece; saving a lot updates product company price (newest lot only).
- Dealer price = latest lot company price/pc × (1 + margin%).
- Profit/COGS always from FIFO; each order freezes its rates.
- SR may order more than available stock (warning only). SR can edit/cancel until order is on a trip.
- SR must "Complete orders" for a date before being assignable; until then faded in New Trip picker.
- One trip per DSR per day. New Trip modal: SR date picker (SRs with ≥1 order that date) + DSR delivery date. Checklist with editable qty, live +/- vs ordered, extra products for ready sale.
- Dashboard has a date filter. SR panel: login + ordering are the core.

**DSR**
1. Only one dispatched-but-unsettled trip per DSR.
2. DSR can deliver more than ordered (limited by van stock).
3. DSR may collect retailer's previous due (extra payment → `retailer_due_collections`, adds to cash).
4. Damage = retailer returns damaged goods; deducted from that bill; company bears cost; entered per product.
5. Ready sale to existing or new retailer; DSR cannot change price.
6. Net Pay formula above; SR O/C not deducted from cash; posted to SR O/C ledger on approval.
7. Delivery/payment save immediately; stock return, retailer due, SR O/C apply on partner approval.
8. Partner can Approve or Send Back (DSR fixes & resubmits).
9. Cash short/excess only recorded and shown.
10. Cancel reasons: fixed (extended) list + optional note.

**Admin**
- Companies are global; partner gets linked to a company only via an SR (owned or via dealer).
- Platform fee per partner+company, history append-only, each order freezes its rate.
- Soft delete; records with dependants must be reassigned/deactivated.

---

## 14. Not built yet / known gaps (good next tasks)

- **Dealer panel** (role `dealer` exists, dealers have logins, `dealer_profit_share`/`partner_profit_share` stored but never used in any calculation/report).
- **SR O/C payout / adjustment UI** — `sr_oc_ledger.entry_type` supports `payout`/`adjustment`, `salesmen.oc_balance` exists, but no screen to pay out SRs.
- **Retailer due management** outside a trip (collect/adjust due, retailer ledger) — only via DSR stop.
- **Profit reports** — `order_items.fifo_cost_total` is filled on approval but no profit report page uses it yet.
- **Platform fee billing/collection** — fee amounts are recorded per order; no invoice/payment flow.
- Damage claim is credited at `products.company_price` (current price), not the lot cost of the damaged goods.
- `delivery_men.zone/vehicle_no/code`, `salesmen.code/area` mostly unused. Admin dashboard `products` count includes soft-deleted.
- Expiry tracking: `lot_items.expire_date` stored, FIFO is by received date (not FEFO); no expiry alerts.
- No automated tests. Test manually on XAMPP and follow §2.3.

---

## 15. Full route list

**Admin** (`routes/admin.php`)
```
GET  /admin/login | POST /admin/login | POST /admin/logout
GET  /admin, /admin/dashboard, /admin/health
GET|POST /admin/{partners|companies|dealers|salesmen}
PUT  /admin/{res}/{id} | PATCH /admin/{res}/{id}/status | DELETE /admin/{res}/{id}
GET  /admin/platform-fees | PUT /admin/platform-fees/{partnerId} | GET /admin/platform-fees/{partnerId}/history/{companyId}
GET  /admin/settings
POST /admin/settings/categories | PATCH /admin/settings/categories/{id}/status | DELETE /admin/settings/categories/{id}
POST /admin/settings/areas | PATCH /admin/settings/areas/{id}/status | DELETE /admin/settings/areas/{id}
DELETE /admin/settings/sessions/{id} | POST /admin/settings/sessions/revoke-others
```
**Partner** (`routes/partner.php`)
```
GET  /partner/login | POST /partner/login | POST /partner/logout
GET  /partner, /partner/dashboard
GET  /partner/trips | GET /partner/trips/planner | POST /partner/trips | GET /partner/trips/{id}
POST /partner/trips/{id}/items | PATCH /partner/trips/{id}/items/{product} | DELETE /partner/trips/{id}/items/{product}
DELETE /partner/trips/{id}/srs/{sr} | POST /partner/trips/{id}/dispatch
GET  /partner/settlements | POST /partner/settlements/{id}/approve | POST /partner/settlements/{id}/send-back
GET  /partner/day-closing
GET|POST /partner/lots | DELETE /partner/lots/{id}
GET|POST /partner/products | POST /partner/products/{id} | DELETE /partner/products/{id}
GET|POST /partner/company-ledger | DELETE /partner/company-ledger/{id}
GET  /partner/orders
GET|POST /partner/delivery-men | PUT /partner/delivery-men/{id} | PATCH /partner/delivery-men/{id}/status
POST /partner/delivery-men/{id}/password | DELETE /partner/delivery-men/{id}
```
**SR** (`routes/sr.php`)
```
GET  /sr/login | POST /sr/login | POST /sr/logout
GET  /sr, /sr/order | GET /sr/orders/today
POST /sr/retailers | POST /sr/orders | PUT /sr/orders/{id} | DELETE /sr/orders/{id}
POST /sr/orders/complete | POST /sr/orders/reopen
GET  /sr/dashboard | GET /sr/history | GET /sr/history/day | GET /sr/profile | POST /sr/profile/password
```
**DSR** (`routes/dsr.php`)
```
GET  /dsr/login | POST /dsr/login | POST /dsr/logout
GET  /dsr, /dsr/dashboard
GET  /dsr/delivery | GET /dsr/delivery/state
POST /dsr/stops/{retailer} | POST /dsr/stops/{retailer}/reset
POST /dsr/ready-sales | DELETE /dsr/ready-sales/{id}
GET  /dsr/van-stock
GET  /dsr/settlement | POST /dsr/settlement
GET  /dsr/expense | POST /dsr/expenses | DELETE /dsr/expenses/{id}
```

---

## 16. Where to look for what (file map)

| Need to change… | File |
|---|---|
| SR ordering rules, O/C, rate freeze | `app/Models/Order.php` |
| Trip create/assign/load/dispatch, FIFO consumption | `app/Models/Trip.php` |
| DSR stop delivery, damage, payment, ready sale, expenses | `app/Models/DsrDelivery.php` |
| Net pay, submit, approve, send back | `app/Models/TripSettlement.php` |
| Daily partner cash summary, FIFO P&L, print sheet | `app/Models/DayClosing.php` |
| Lot receive/delete, price update | `app/Models/Lot.php` |
| Product pricing, reserved/available stock | `app/Models/Product.php` |
| Partner↔company link, ownership, dealer share | `app/Models/Salesman.php` (`syncLink`) |
| Platform fee rate/history | `app/Models/PlatformFee.php` |
| Company payable ledger | `app/Models/CompanyLedger.php` |
| Retailer list/create | `app/Models/Retailer.php` |
| Panel login (phone) | `app/Support/PanelAuth.php`, `app/Controllers/PanelAuthController.php` |
| JSON response / validation helpers | `app/Controllers/Concerns/JsonActions.php` |
| Schema | `database/schema.sql` (+ add a new numbered migration for any change) |

**When you change the schema:** update `database/schema.sql` **and** add `database/migrations/00N_<name>.sql` (additive, never modifies existing rows). Then update this document.
