# HappyBasic — Polyglot MVC Architecture

Polyglot monorepo with a PHP 8.2+ MVC web application as the primary entry point and isolated directories for additional language services (Node.js, Python, Go, etc.).

## Layout

```
happybasic/
├── .env / .env.example     # Shared configuration (DB, service URLs, internal token)
├── .htaccess               # XAMPP rewrite -> services/php/public/
├── database/               # Shared SQL schemas & migrations
├── shared/                 # Cross-service contracts (JSON schemas, OpenAPI, specs)
├── storage/                # Shared logs & uploads
└── services/
    ├── php/                # Primary MVC web app (Router, Controller, Model, PDO, View, Auth, CSRF, Validator, ServiceClient)
    ├── node/               # Node.js service/worker (port 3001)
    └── python/             # Python service/worker (port 8001)
```

## Calling Other Services from PHP

Register endpoints in `services/php/config/services.php` and `.env`, then call via `service()`:

```php
$res = service('node')->get('/health');
$res = service('python')->post('/jobs/analyze', ['text' => 'hello']);
```

All internal requests include `X-Service-Token` from `INTERNAL_SERVICE_TOKEN` in `.env`.

## Adding a New Language Service

1. Create `services/<name>/` (e.g., `services/go/`).
2. Read shared settings from the root `.env` (`SERVICE_<NAME>_PORT`, `INTERNAL_SERVICE_TOKEN`).
3. Add `SERVICE_<NAME>_URL` to `.env` and register it in `services/php/config/services.php`.
4. Call it from PHP with `service('<name>')->get(...)` or `->post(...)`.

## Database & Admin Setup

```bash
php database/setup.php                                   # create DB + tables from database/schema.sql
php database/create-admin.php --email=you@example.com --name="Super Admin"   # prompts for password (min 8)
```

Existing DB? Apply new files in `database/migrations/` in order (e.g. `mysql -uroot happybasic < database/migrations/001_global_companies.sql`).

Then sign in at `/admin/login`. Add Areas first (Settings → Areas); partners must belong to an area. Companies are global; a partner gets connected to a company when an SR is added (Owned → pick partner, Dealer → partner comes from the dealer). Platform fee per lakh sales is set per partner+company on the Platform Fees page; every change is appended to `platform_fee_history` (effective from save time) and each order must freeze its rate in `orders.platform_fee_rate` via `PlatformFee::rateAt()`, so past sales never change.
Admin data uses soft delete (`deleted_at`); records with dependants must be reassigned or deactivated instead.

## Partner Panel & SR Ordering

Partners sign in at `/partner/login`, SRs at `/sr/login` (phone + password; each panel keeps its own session). Apply `database/migrations/004_partner_panel.sql` on existing databases. Set `APP_TIMEZONE=Asia/Dhaka` so PHP dates match MySQL.

- **Lots** are entered in pieces with a per-piece company price. Each `lot_items` row is a FIFO layer; the newest lot (by received date) sets the product's company price, and dealer price = company price × (1 + margin%). Saving a lot adds a `lot_purchase` debit to `company_ledger`.
- **SR orders** freeze `base_rate_pc` (dealer price) per item; O/C = SR total − pieces × base rate. SRs can edit / cancel until the order is on a trip, then press **Complete Today's Orders**; only completed SRs are assignable.
- **Trips**: one per DSR per delivery date. The partner can change loaded pieces, add extra products (ready sale), and **Dispatch**, which consumes stock oldest-lot-first into `trip_stock_allocations`.
- SR panel is fully database-driven: dashboard (today vs daily target, month totals, O/C balance), history by date, profile with monthly performance and password change.

## DSR Panel & Settlement

DSRs sign in at `/dsr/login`. Apply `database/migrations/005_dsr_settlement.sql` on existing databases. A DSR can hold only one dispatched-but-unsettled trip.

- **Delivery** groups the trip's orders by retailer. Per order: delivered pcs (may exceed the order, limited by van stock), cancel with a reason, damage returns (dealer price, deducted from the bill) and payment. Paying more than the bill collects the retailer's old due (`retailer_due_collections`). Status: delivered / partial / due / cancelled.
- **Ready sale** sells van stock at the loaded dealer price (DSR cannot change it) to an existing retailer or a new one pinned at the DSR's location.
- **Net Pay** = delivered (SR price) + ready sale + old due collected − damage − expenses − new due. SR O/C is not deducted from cash.
- DSR submits the cash count (trip → `in_review`); the partner **approves** (trip → `settled`) or **sends back** with a note. Approval returns unsold stock to its lots (newest allocations first), sets FIFO cost per sold line, posts SR delivery O/C to `sr_oc_ledger` / `salesmen.oc_balance`, updates retailer due balances and credits damage claims to `company_ledger`.

## Deployment workflow

- `main` = stable, `draft` = staging. A push to `draft` auto-deploys to https://v2.happybangladesh.com (GitHub Actions → SSH → `deploy.sh`).
- Test on v2, then merge `draft` into `main`.
- `.env`, uploads and logs live only on the server (gitignored). DB schema changes are **not** applied automatically — run new files from `database/migrations/` by hand.

### Database migrations (automatic)

Every DB change = a **new** file `database/migrations/NNN_description.sql` (next number, never edit an applied one). `deploy.sh` runs `php database/migrate.php`, which backs the DB up to `storage/backups/` (last 10 kept) and applies pending files once each, tracked in `schema_migrations`. A failing file stops the deploy (red in Actions) and is not recorded — MySQL cannot roll DDL back, so fix and push again. Check state: `php database/migrate.php --status`. On an existing DB, run `php database/migrate.php --baseline` once to mark current files as applied.
